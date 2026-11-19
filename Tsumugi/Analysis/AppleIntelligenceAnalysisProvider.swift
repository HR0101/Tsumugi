//
//  AppleIntelligenceAnalysisProvider.swift
//  Tsumugi
//
//  Apple Intelligence（Foundation Models フレームワーク）を使う診断プロバイダ.
//
//  モデルは 2 種類ある.
//  ・Private Cloud Compute（iOS 27 以降）: 文脈 32,000 トークン. 長い記事も読める. 通信が必要.
//  ・オンデバイス（iOS 26 以降）: 文脈 4,096 トークン. 本文は冒頭だけを読む. 通信しない.
//
//  使えるモデルを優先順に並べ（engines）, 失敗したら次のモデルへ, 最後はルールベース診断へ退避する.
//  利用者がモデルを 1 つに指定した場合は, 退避したことを診断結果に表示する（fallbackNotice）.
//  総合スコアの合成はモデルに任せず, 必ず CredibilityScoring / FreshnessScoring で行う.
//  これにより, モデルが更新されても採点基準が揺れない（仕様書 14「モデル更新による非互換」対策）.
//

import Foundation
import FoundationModels
import os

// MARK: - モデルの種類

/// 文章生成に使う Apple Intelligence のモデル.
enum IntelligenceEngine: String, Sendable, CaseIterable {
  /// Apple のサーバ上で動く大きいモデル.
  case privateCloud
  /// 端末内で動くモデル.
  case onDevice

  /// 1 回の生成に使える分量.
  var budget: PromptBudget {
    switch self {
    case .privateCloud: return .extended
    case .onDevice: return .compact
    }
  }

  var displayName: String {
    switch self {
    case .privateCloud: return "Apple Intelligence（Private Cloud Compute）"
    case .onDevice: return "Apple Intelligence（オンデバイス）"
    }
  }

  /// 診断結果に記録するモデル識別子（仕様書 14）.
  var modelIdentifier: String {
    switch self {
    case .privateCloud: return "apple-fm-private-cloud"
    case .onDevice: return "apple-fm-on-device"
    }
  }
}

// MARK: - Private Cloud Compute の一時停止

/// Private Cloud Compute がモデル側の理由（通信・利用枠・利用資格など）で失敗したら, しばらく使わない.
/// 失敗のたびに毎回サーバへ問い合わせてから退避すると, 記事ごとに待ち時間が積み重なるため.
enum PrivateCloudCircuit {

  /// 失敗してから再び試すまでの時間（秒）.
  private static let cooldown: TimeInterval = 30 * 60
  /// 最後に失敗した時刻.
  private static let lastFailure = OSAllocatedUnfairLock<Date?>(initialState: nil)

  /// いま Private Cloud Compute を試してよいか.
  static var isClosed: Bool {
    lastFailure.withLock { date in
      guard let date else { return true }
      return Date.now.timeIntervalSince(date) >= cooldown
    }
  }

  /// 失敗を記録し, 一定時間は試さないようにする.
  static func recordFailure() {
    lastFailure.withLock { $0 = .now }
  }

  /// 失敗の記録を消す. テストで状態を元に戻すために使う.
  static func reset() {
    lastFailure.withLock { $0 = nil }
  }
}

// MARK: - 利用可否

/// Apple Intelligence のモデルが, いまこの端末で使えるか.
struct AppleIntelligenceAvailability: Sendable, Equatable {

  /// オンデバイスモデルの状態.
  enum OnDeviceState: Sendable, Equatable {
    case available
    /// Apple Intelligence に対応していない機種.
    case deviceNotEligible
    /// 設定で Apple Intelligence がオフになっている.
    case notEnabled
    /// モデルをダウンロード中など, まだ準備ができていない.
    case modelNotReady
    /// 出力言語に対応していない.
    case unsupportedLanguage
    /// 理由が分からないが使えない.
    case unavailable

    var message: String {
      switch self {
      case .available: return "利用できます"
      case .deviceNotEligible: return "この機種は Apple Intelligence に対応していません"
      case .notEnabled: return "設定アプリで Apple Intelligence をオンにしてください"
      case .modelNotReady: return "モデルを準備しています. しばらくお待ちください"
      case .unsupportedLanguage: return "出力言語に対応していません"
      case .unavailable: return "現在は利用できません"
      }
    }
  }

  let onDevice: OnDeviceState
  /// Private Cloud Compute のモデルを使えるか.
  let isPrivateCloudAvailable: Bool
  /// Private Cloud Compute の状態を利用者に示す文.
  let privateCloudMessage: String

  var isOnDeviceAvailable: Bool { onDevice == .available }

  /// 使えるモデルを, 優先する順に並べたもの.
  var availableEngines: [IntelligenceEngine] {
    var engines: [IntelligenceEngine] = []
    if isPrivateCloudAvailable { engines.append(.privateCloud) }
    if isOnDeviceAvailable { engines.append(.onDevice) }
    return engines
  }

  /// 現在の端末の状態を調べる.
  /// - Parameter outputLanguage: 要約の出力言語（`ja` など）. オンデバイスモデルが対応しているかを確かめる.
  static func current(outputLanguage: String) -> AppleIntelligenceAvailability {
    let privateCloud = privateCloudState()
    return AppleIntelligenceAvailability(
      onDevice: onDeviceState(outputLanguage: outputLanguage),
      isPrivateCloudAvailable: privateCloud.isAvailable,
      privateCloudMessage: privateCloud.message
    )
  }

  private static func onDeviceState(outputLanguage: String) -> OnDeviceState {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
      return model.supportsLocale(Locale(identifier: outputLanguage)) ? .available : .unsupportedLanguage
    case .unavailable(.deviceNotEligible):
      return .deviceNotEligible
    case .unavailable(.appleIntelligenceNotEnabled):
      return .notEnabled
    case .unavailable(.modelNotReady):
      return .modelNotReady
    case .unavailable:
      return .unavailable
    }
  }

  /// Private Cloud Compute は iOS 27 以降で, かつ Apple から利用資格（managed entitlement）を
  /// 付与されたアプリでのみ使える. 資格がなければ unavailable になり, オンデバイスへ退避する.
  private static func privateCloudState() -> (isAvailable: Bool, message: String) {
    guard #available(iOS 27.0, *) else { return (false, "iOS 27 以降で利用できます") }
    guard PrivateCloudCircuit.isClosed else { return (false, "一時的に利用できません") }
    guard PrivateCloudComputeLanguageModel().isAvailable else { return (false, "この端末では利用できません") }
    return (true, "利用できます")
  }
}

// MARK: - プロバイダ

struct AppleIntelligenceAnalysisProvider: AnalysisProvider {

  /// 使うモデルを優先順に並べたもの. 空なら最初からルールベースで判定する.
  private let engines: [IntelligenceEngine]
  /// ルールベースへ退避したときに利用者へ示す説明. nil なら知らせない.
  private let fallbackNotice: String?
  /// すべてのモデルが失敗したときに結果を埋めるための予備プロバイダ.
  private let fallback = HeuristicAnalysisProvider()

  /// 二段検証の 2 回目に使う温度. 1 回目（貪欲法）と違う見方を引き出すため少しばらつかせる.
  private static let secondPassTemperature = 0.6

  /// - Parameters:
  ///   - engines: 使うモデルを優先順に並べたもの.
  ///   - fallbackNotice: ルールベースへ退避したときに診断結果へ表示する説明.
  init(engines: [IntelligenceEngine], fallbackNotice: String? = nil) {
    self.engines = engines
    self.fallbackNotice = fallbackNotice
  }

  /// 主に使うモデル. 使えるモデルがなければ nil.
  private var primaryEngine: IntelligenceEngine? { engines.first }

  var displayName: String {
    guard let primaryEngine else { return fallback.displayName }
    return primaryEngine.displayName
  }

  var modelIdentifier: String {
    primaryEngine?.modelIdentifier ?? fallback.modelIdentifier
  }

  var requiresNetwork: Bool { primaryEngine == .privateCloud }

  /// ルールベースで埋めたことの記録.
  private var fallbackRecord: FallbackRecord {
    FallbackRecord(modelIdentifier: fallback.modelIdentifier, notice: fallbackNotice)
  }

  // MARK: 要約

  func summarize(_ input: AnalysisInput) async throws -> SummaryDraft {
    // 仕様書 12.2: 短文記事は要約を省略する.
    guard !input.isTooShortToSummarize else {
      return try await fallback.summarize(input)
    }

    let generated: (value: GeneratedSummary, budget: PromptBudget)
    do {
      generated = try await generate(
        GeneratedSummary.self,
        engines: engines,
        instructions: { AnalysisPrompts.summarySystem(language: input.outputLanguage, budget: $0) },
        prompt: { AnalysisPrompts.summaryUser(input, budget: $0) }
      )
    } catch {
      var draft = try await fallback.summarize(input)
      draft.fallback = fallbackRecord
      return draft
    }

    var draft = generated.value.makeDraft(factLimit: generated.budget.factLimit)
    // 仕様書 9.6: 数値・固有名詞が原文に存在するか機械検証する.
    draft.facts = GroundingValidator.validate(facts: draft.facts, against: input.bodyText).facts
    draft.claims = GroundingValidator.validate(claims: draft.claims, against: input.bodyText)
    return draft
  }

  // MARK: 信頼度診断

  func assessCredibility(_ input: AnalysisInput) async throws -> CredibilityDraft {
    var draft: CredibilityDraft
    do {
      draft = try await requestCredibility(input, isSecondPass: false)
    } catch {
      var draft = try await fallback.assessCredibility(input)
      draft.fallback = fallbackRecord
      return draft
    }

    // 仕様書 9.6「二段検証」: 極端な値のときだけ再評価する.
    let provisional = CredibilityScoring.compose(
      scores: draft.scores,
      flags: draft.flags,
      confidence: draft.confidence
    )
    if GroundingValidator.needsSecondPass(totalScore: provisional.total),
       let second = try? await requestCredibility(input, isSecondPass: true) {
      draft = merge(first: draft, second: second)
    }
    return draft
  }

  private func requestCredibility(_ input: AnalysisInput, isSecondPass: Bool) async throws -> CredibilityDraft {
    let instructions = AnalysisPrompts.credibilitySystem
      + (isSecondPass ? AnalysisPrompts.credibilitySecondPassNote : "")
    let generated = try await generate(
      GeneratedCredibility.self,
      engines: engines,
      instructions: { _ in instructions },
      prompt: { AnalysisPrompts.credibilityUser(input, budget: $0) },
      temperature: isSecondPass ? Self.secondPassTemperature : nil
    )
    let response = generated.value

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
    merged.confidence = lowerConfidence(first.confidence, second.confidence)
    return merged
  }

  private func lowerConfidence(_ lhs: AnalysisConfidence, _ rhs: AnalysisConfidence) -> AnalysisConfidence {
    if [lhs, rhs].contains(.low) { return .low }
    if [lhs, rhs].contains(.medium) { return .medium }
    return .high
  }

  // MARK: 鮮度診断

  func assessFreshness(_ input: AnalysisInput) async throws -> FreshnessDraft {
    let response: GeneratedFreshness
    do {
      response = try await generate(
        GeneratedFreshness.self,
        engines: engines,
        instructions: { _ in AnalysisPrompts.freshnessSystem },
        prompt: { AnalysisPrompts.freshnessUser(input, budget: $0) }
      ).value
    } catch {
      var draft = try await fallback.assessFreshness(input)
      draft.fallback = fallbackRecord
      return draft
    }

    let validated = GroundingValidator.validate(obsoletePoints: response.obsoletePointValues, against: input.bodyText)
    return FreshnessDraft(
      topicClass: response.topicClassValue,
      adjustments: response.adjustmentValues,
      obsoletePoints: validated.points,
      // 後続情報の提示には Web 検索が必要なため v1.0 では空とする（仕様書 4.5.3 は v1.1 で対応）.
      successors: []
    )
  }

  // MARK: タグ提案

  func suggestTags(_ input: AnalysisInput) async throws -> [String] {
    // タグは短い入力で足りるので, 通信しないオンデバイスモデルを優先する.
    // オンデバイスではタグ付け専用の設定（contentTagging）を使う.
    let tagEngines = engines.contains(.onDevice) ? [IntelligenceEngine.onDevice] : engines
    do {
      let tags = try await generate(
        GeneratedTags.self,
        engines: tagEngines,
        useCase: .contentTagging,
        instructions: { _ in AnalysisPrompts.tagSystem },
        prompt: { _ in AnalysisPrompts.tagUser(input) }
      ).value.cleanedTags
      return tags.isEmpty ? try await fallback.suggestTags(input) : tags
    } catch {
      return try await fallback.suggestTags(input)
    }
  }

  // MARK: 生成

  /// モデルを優先順に試し, 最初に成功した結果と, そのとき使った予算を返す.
  private func generate<Content: Generable>(
    _ type: Content.Type,
    engines: [IntelligenceEngine],
    useCase: SystemLanguageModel.UseCase = .general,
    instructions: (PromptBudget) -> String,
    prompt: (PromptBudget) -> String,
    temperature: Double? = nil
  ) async throws -> (value: Content, budget: PromptBudget) {
    var lastError: Error = AnalysisError.notConfigured
    for engine in engines {
      if engine == .privateCloud && !PrivateCloudCircuit.isClosed { continue }
      do {
        return try await generate(
          type,
          engine: engine,
          useCase: useCase,
          instructions: instructions,
          prompt: prompt,
          temperature: temperature
        )
      } catch {
        // 記事の内容が原因ではない失敗（通信・利用枠・利用資格など）なら, しばらく PCC を使わない.
        if engine == .privateCloud && !Self.isContentRelated(error) {
          PrivateCloudCircuit.recordFailure()
        }
        // 失敗したら次のモデルを試す.
        lastError = error
      }
    }
    throw AnalysisError.providerFailure(message: lastError.localizedDescription)
  }

  /// 1 つのモデルで生成する. 文脈の枠からあふれたら本文を半分にして再試行する.
  private func generate<Content: Generable>(
    _ type: Content.Type,
    engine: IntelligenceEngine,
    useCase: SystemLanguageModel.UseCase,
    instructions: (PromptBudget) -> String,
    prompt: (PromptBudget) -> String,
    temperature: Double?
  ) async throws -> (value: Content, budget: PromptBudget) {
    var budget = engine.budget
    while true {
      do {
        let session = makeSession(engine: engine, useCase: useCase, instructions: instructions(budget))
        let options = makeOptions(budget: budget, temperature: temperature)
        let response = try await session.respond(
          to: prompt(budget),
          generating: type,
          includeSchemaInPrompt: true,
          options: options
        )
        return (response.content, budget)
      } catch {
        guard Self.isContextOverflow(error), let smaller = budget.halvingBody() else {
          throw error
        }
        budget = smaller
      }
    }
  }

  /// 毎回新しいセッションを作る. 前の記事のやり取りが文脈に残らないようにするため.
  /// useCase はオンデバイスモデルにだけ効く（Private Cloud Compute には用途別の設定がない）.
  private func makeSession(
    engine: IntelligenceEngine,
    useCase: SystemLanguageModel.UseCase,
    instructions: String
  ) -> LanguageModelSession {
    if engine == .privateCloud {
      if #available(iOS 27.0, *) {
        return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
      }
    }
    let model = useCase == .general ? SystemLanguageModel.default : SystemLanguageModel(useCase: useCase)
    return LanguageModelSession(model: model, instructions: instructions)
  }

  /// 1 回目は貪欲法で毎回同じ結果になるようにし, 2 回目だけ温度を与える.
  private func makeOptions(budget: PromptBudget, temperature: Double?) -> GenerationOptions {
    if let temperature {
      return GenerationOptions(temperature: temperature, maximumResponseTokens: budget.maximumResponseTokens)
    }
    return GenerationOptions(samplingMode: .greedy, maximumResponseTokens: budget.maximumResponseTokens)
  }

  /// 記事の内容が原因のエラーか（文脈あふれ・ガードレール・回答拒否）.
  /// これらは別の記事なら成功しうるので, モデルそのものの不調とはみなさない.
  private static func isContentRelated(_ error: Error) -> Bool {
    if isContextOverflow(error) { return true }
    if #available(iOS 27.0, *), let modelError = error as? LanguageModelError {
      switch modelError {
      case .guardrailViolation, .refusal: return true
      default: return false
      }
    }
    if let generationError = error as? LanguageModelSession.GenerationError {
      switch generationError {
      case .guardrailViolation, .refusal: return true
      default: return false
      }
    }
    return false
  }

  /// 文脈の枠（入力＋出力のトークン数）からあふれたエラーか.
  private static func isContextOverflow(_ error: Error) -> Bool {
    if #available(iOS 27.0, *), let modelError = error as? LanguageModelError,
       case .contextSizeExceeded = modelError {
      return true
    }
    if let generationError = error as? LanguageModelSession.GenerationError,
       case .exceededContextWindowSize = generationError {
      return true
    }
    return false
  }
}
