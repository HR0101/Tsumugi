//
//  ClaudeAnalysisProvider.swift
//  Tsumugi
//
//  Claude API を使う診断プロバイダ.
//  仕様書 9.1 のモデル階層に従い, 用途ごとに異なるモデルを使い分ける.
//
//  総合スコアの合成は LLM に任せず, 必ず CredibilityScoring / FreshnessScoring で行う.
//  これにより, モデルを差し替えても採点基準が揺れない（仕様書 14「モデル更新による非互換」対策）.
//

import Foundation

struct ClaudeAnalysisProvider: AnalysisProvider {

  let displayName = "Claude API"
  let requiresNetwork = true

  private let client: ClaudeAPIClient
  private let configuration: ClaudeConfiguration
  /// LLM が失敗したときに結果を埋めるための予備プロバイダ.
  private let fallback = HeuristicAnalysisProvider()

  init(configuration: ClaudeConfiguration, urlSession: URLSession = .shared) {
    self.configuration = configuration
    self.client = ClaudeAPIClient(configuration: configuration, urlSession: urlSession)
  }

  var modelIdentifier: String {
    configuration.modelID(for: .large)
  }

  // MARK: - 要約

  func summarize(_ input: AnalysisInput) async throws -> SummaryDraft {
    // 仕様書 12.2: 短文記事は要約をスキップしてコストを抑える.
    guard !input.isTooShortToSummarize else {
      return try await fallback.summarize(input)
    }

    let data = try await client.requestStructuredJSON(
      tier: .medium,
      system: AnalysisPrompts.summarySystem(language: input.outputLanguage),
      userPrompt: AnalysisPrompts.summaryUser(input),
      schema: AnalysisSchemas.summary,
      effort: "medium"
    )

    let response = try decode(SummaryResponse.self, from: data)

    // 仕様書 9.6: 数値・固有名詞が原文に存在するか機械検証する.
    let validatedFacts = GroundingValidator.validate(facts: response.facts, against: input.bodyText).facts
    let validatedClaims = GroundingValidator.validate(claims: response.claims, against: input.bodyText)

    return SummaryDraft(
      tldr: response.tldr,
      keyPoints: response.keyPoints,
      detailed: response.detailed,
      claims: validatedClaims,
      facts: validatedFacts,
      highlightFocused: nil
    )
  }

  // MARK: - 信頼度診断

  func assessCredibility(_ input: AnalysisInput) async throws -> CredibilityDraft {
    var draft = try await requestCredibility(input, effort: "high")

    // 仕様書 9.6「二段検証」: 極端な値のときだけ再評価する.
    let provisional = CredibilityScoring.compose(
      scores: draft.scores,
      flags: draft.flags,
      confidence: draft.confidence
    )
    if GroundingValidator.needsSecondPass(totalScore: provisional.total) {
      if let second = try? await requestCredibility(input, effort: "xhigh") {
        draft = merge(first: draft, second: second)
      }
    }

    return draft
  }

  private func requestCredibility(_ input: AnalysisInput, effort: String) async throws -> CredibilityDraft {
    let data = try await client.requestStructuredJSON(
      tier: .large,
      system: AnalysisPrompts.credibilitySystem,
      userPrompt: AnalysisPrompts.credibilityUser(input),
      schema: AnalysisSchemas.credibility,
      effort: effort
    )

    let response = try decode(CredibilityResponse.self, from: data)

    // 仕様書 9.6「引用強制」: 原文に存在しない引用は破棄する.
    let validation = GroundingValidator.validate(rationale: response.rationaleEntries, against: input.bodyText)

    // 判定できた項目だけをスコアに含める（仕様書 9.6「不明の明示」）.
    let determinedCategories = Set(validation.entries.filter(\.isDetermined).map(\.category))
    let scores = response.categoryScores.filter { determinedCategories.contains($0.key) }

    // 引用の検証を大きく落とした場合は確信度を下げる.
    var confidence = response.confidenceValue
    if validation.report.quotePassRate < 0.5 { confidence = .low }

    return CredibilityDraft(
      scores: scores,
      rationale: validation.entries,
      flags: response.flagValues,
      corroborations: [],
      confidence: confidence
    )
  }

  /// 二段検証の結果を統合する. スコアは平均し, 確信度は低い方を採る.
  private func merge(first: CredibilityDraft, second: CredibilityDraft) -> CredibilityDraft {
    var merged = first
    var averaged: [CredibilityCategory: Int] = [:]
    for category in CredibilityCategory.allCases {
      switch (first.scores[category], second.scores[category]) {
      case let (lhs?, rhs?): averaged[category] = (lhs + rhs) / 2
      case let (lhs?, nil): averaged[category] = lhs
      case let (nil, rhs?): averaged[category] = rhs
      case (nil, nil): break
      }
    }
    merged.scores = averaged
    merged.flags = Array(Set(first.flags).union(second.flags)).sorted { $0.rawValue < $1.rawValue }
    merged.confidence = [first.confidence, second.confidence].contains(.low)
      ? .low
      : ([first.confidence, second.confidence].contains(.medium) ? .medium : .high)
    return merged
  }

  // MARK: - 鮮度診断

  func assessFreshness(_ input: AnalysisInput) async throws -> FreshnessDraft {
    let data = try await client.requestStructuredJSON(
      tier: .medium,
      system: AnalysisPrompts.freshnessSystem,
      userPrompt: AnalysisPrompts.freshnessUser(input),
      schema: AnalysisSchemas.freshness,
      effort: "medium"
    )

    let response = try decode(FreshnessResponse.self, from: data)
    let validated = GroundingValidator.validate(obsoletePoints: response.obsoletePointValues, against: input.bodyText)

    return FreshnessDraft(
      topicClass: response.topicClassValue,
      adjustments: response.adjustmentValues,
      obsoletePoints: validated.points,
      // 後続情報の提示には Web 検索が必要なため v1.0 では空とする（仕様書 4.5.3 は v1.1 で対応）.
      successors: []
    )
  }

  // MARK: - タグ提案

  func suggestTags(_ input: AnalysisInput) async throws -> [String] {
    let data = try await client.requestStructuredJSON(
      tier: .small,
      system: AnalysisPrompts.tagSystem,
      userPrompt: AnalysisPrompts.tagUser(input),
      schema: AnalysisSchemas.tags
    )
    let response = try decode(TagResponse.self, from: data)
    return response.tags
  }

  // MARK: - デコード

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw AnalysisError.invalidResponse
    }
  }
}

// MARK: - API レスポンスの DTO

private struct SummaryResponse: Decodable {
  let tldr: String
  let keyPoints: [String]
  let detailed: String?
  let claims: [Claim]
  let facts: [Fact]

  private enum CodingKeys: String, CodingKey {
    case tldr, detailed, claims, facts
    case keyPoints = "key_points"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    tldr = try container.decode(String.self, forKey: .tldr)
    keyPoints = try container.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
    detailed = try container.decodeIfPresent(String.self, forKey: .detailed)
    claims = try container.decodeIfPresent([Claim].self, forKey: .claims) ?? []
    facts = try container.decodeIfPresent([Fact].self, forKey: .facts) ?? []
  }
}

private struct CredibilityResponse: Decodable {
  struct Scores: Decodable {
    let source: Int?
    let transparency: Int?
    let evidence: Int?
    let neutrality: Int?
    let corroboration: Int?
  }

  struct RationaleItem: Decodable {
    let category: String
    let reason: String
    let quote: String?
    let determined: Bool?
  }

  let scores: Scores
  let rationale: [RationaleItem]
  let flags: [String]
  let confidence: String

  /// 判定できたカテゴリのスコアのみを辞書にする.
  var categoryScores: [CredibilityCategory: Int] {
    var result: [CredibilityCategory: Int] = [:]
    if let value = scores.source { result[.source] = clamp(value) }
    if let value = scores.transparency { result[.transparency] = clamp(value) }
    if let value = scores.evidence { result[.evidence] = clamp(value) }
    if let value = scores.neutrality { result[.neutrality] = clamp(value) }
    if let value = scores.corroboration { result[.corroboration] = clamp(value) }
    return result
  }

  var rationaleEntries: [RationaleEntry] {
    rationale.compactMap { item in
      guard let category = CredibilityCategory(rawValue: item.category) else { return nil }
      return RationaleEntry(
        category: category,
        reason: item.reason,
        quote: item.quote,
        isDetermined: item.determined ?? true
      )
    }
  }

  var flagValues: [CredibilityFlag] {
    flags.compactMap(CredibilityFlag.init(rawValue:))
  }

  var confidenceValue: AnalysisConfidence {
    AnalysisConfidence(rawValue: confidence) ?? .medium
  }

  private func clamp(_ value: Int) -> Int { max(0, min(100, value)) }
}

private struct FreshnessResponse: Decodable {
  struct AdjustmentItem: Decodable {
    let reason: String
    let evidence: String?
  }

  let topicClass: String
  let adjustments: [AdjustmentItem]
  let obsoletePoints: [ObsoletePoint]

  private enum CodingKeys: String, CodingKey {
    case adjustments
    case topicClass = "topic_class"
    case obsoletePoints = "obsolete_points"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    topicClass = try container.decode(String.self, forKey: .topicClass)
    adjustments = try container.decodeIfPresent([AdjustmentItem].self, forKey: .adjustments) ?? []
    obsoletePoints = try container.decodeIfPresent([ObsoletePoint].self, forKey: .obsoletePoints) ?? []
  }

  var topicClassValue: TopicClass {
    TopicClass(rawValue: topicClass) ?? .software
  }

  /// 補正値は仕様書 4.5.2 の固定値を使う. LLM に点数を決めさせない.
  var adjustmentValues: [FreshnessAdjustment] {
    var seen = Set<FreshnessAdjustment.Reason>()
    return adjustments.compactMap { item in
      guard let reason = FreshnessAdjustment.Reason(rawValue: item.reason) else { return nil }
      guard seen.insert(reason).inserted else { return nil }
      return FreshnessAdjustment(reason: reason, delta: reason.delta, evidence: item.evidence)
    }
  }

  var obsoletePointValues: [ObsoletePoint] { obsoletePoints }
}

private struct TagResponse: Decodable {
  let tags: [String]
}
