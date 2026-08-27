//
//  AnalysisPipeline.swift
//  Tsumugi
//
//  仕様書 6.2「処理パイプライン」をクライアント側で実行する.
//
//  ingest → normalize_url → dedupe_check → extract
//    → classify_topic / summarize / credibility_analyze / freshness_analyze（並列）
//    → persist → notification
//
//  仕様書 12.2「段階的診断」に従い, 保存時は抽出＋要約まで,
//  信頼度・鮮度の詳細診断は Item を開いた時に初回実行する.
//

import Foundation

/// パイプラインが返す診断結果一式（SwiftData への書き込み前の中間表現）.
struct AnalysisOutcome: Sendable {
  var summary: SummaryDraft?
  var credibility: CredibilityDraft?
  var freshness: FreshnessDraft?
  var suggestedTags: [String]
  /// 一部の診断が失敗した場合のメッセージ.
  var partialFailures: [String]

  var isComplete: Bool {
    summary != nil && credibility != nil && freshness != nil && partialFailures.isEmpty
  }
}

/// 診断パイプライン.
struct AnalysisPipeline: Sendable {

  private enum Constant {
    /// 仕様書 6.2: 並列 3 ジョブの合計タイムアウト.
    static let totalTimeout: TimeInterval = 60
    /// 個別ジョブのタイムアウト.
    static let jobTimeout: TimeInterval = 45
  }

  private let provider: AnalysisProvider

  init(provider: AnalysisProvider) {
    self.provider = provider
  }

  var providerName: String { provider.displayName }
  var modelIdentifier: String { provider.modelIdentifier }

  // MARK: - 段階 1: 要約まで（仕様書 12.2）

  /// 保存直後に実行する軽い診断. 要約とタグ提案のみを行う.
  func runSummaryStage(_ input: AnalysisInput) async -> AnalysisOutcome {
    var failures: [String] = []

    async let summaryTask = attempt("要約") { try await provider.summarize(input) }
    async let tagTask = attempt("タグ提案") { try await provider.suggestTags(input) }

    let (summaryResult, tagResult) = await (summaryTask, tagTask)

    if let message = summaryResult.failure { failures.append(message) }
    if let message = tagResult.failure { failures.append(message) }

    return AnalysisOutcome(
      summary: summaryResult.value,
      credibility: nil,
      freshness: nil,
      suggestedTags: tagResult.value ?? [],
      partialFailures: failures
    )
  }

  // MARK: - 段階 2: 詳細診断

  /// 信頼度診断と鮮度診断を並列で実行する（仕様書 6.2）.
  func runDiagnosisStage(_ input: AnalysisInput) async -> AnalysisOutcome {
    var failures: [String] = []

    async let credibilityTask = attempt("信頼度診断") { try await provider.assessCredibility(input) }
    async let freshnessTask = attempt("鮮度診断") { try await provider.assessFreshness(input) }

    let (credibilityResult, freshnessResult) = await (credibilityTask, freshnessTask)

    if let message = credibilityResult.failure { failures.append(message) }
    if let message = freshnessResult.failure { failures.append(message) }

    return AnalysisOutcome(
      summary: nil,
      credibility: credibilityResult.value,
      freshness: freshnessResult.value,
      suggestedTags: [],
      partialFailures: failures
    )
  }

  /// 要約と詳細診断をまとめて実行する（段階的診断を無効にした場合の経路）.
  func runFullPipeline(_ input: AnalysisInput) async -> AnalysisOutcome {
    async let summaryStage = runSummaryStage(input)
    async let diagnosisStage = runDiagnosisStage(input)
    let (first, second) = await (summaryStage, diagnosisStage)

    return AnalysisOutcome(
      summary: first.summary,
      credibility: second.credibility,
      freshness: second.freshness,
      suggestedTags: first.suggestedTags,
      partialFailures: first.partialFailures + second.partialFailures
    )
  }

  // MARK: - スコア合成

  /// 信頼度の下書きから, 決定的な合成関数で最終スコアを算出する（仕様書 9.4）.
  static func composeCredibility(
    draft: CredibilityDraft,
    strictness: AnalysisStrictness,
    model: String
  ) -> CredibilityReport {
    let composed = CredibilityScoring.compose(
      scores: draft.scores,
      flags: draft.flags,
      confidence: draft.confidence,
      penaltyMultiplier: strictness.penaltyMultiplier
    )

    return CredibilityReport(
      totalScore: composed.total,
      label: composed.label,
      sourceScore: draft.scores[.source] ?? 0,
      transparencyScore: draft.scores[.transparency] ?? 0,
      evidenceScore: draft.scores[.evidence] ?? 0,
      neutralityScore: draft.scores[.neutrality] ?? 0,
      corroborationScore: draft.scores[.corroboration] ?? 0,
      rationale: draft.rationale,
      flags: draft.flags,
      corroborations: draft.corroborations,
      confidence: draft.confidence,
      model: model
    )
  }

  /// 鮮度の下書きから, 半減期モデルで最終スコアを算出する（仕様書 9.5）.
  static func composeFreshness(
    draft: FreshnessDraft,
    publishedAt: Date?,
    updatedAt: Date?,
    now: Date = .now
  ) -> FreshnessReport {
    let composed = FreshnessScoring.compute(
      topicClass: draft.topicClass,
      publishedAt: publishedAt,
      updatedAt: updatedAt,
      adjustments: draft.adjustments,
      now: now
    )

    return FreshnessReport(
      freshnessScore: composed.score,
      stalenessLabel: composed.label,
      topicClass: draft.topicClass,
      halfLifeDays: composed.halfLifeDays,
      elapsedDays: composed.elapsedDays,
      decayedScore: composed.decayedScore,
      adjustments: draft.adjustments,
      obsoletePoints: draft.obsoletePoints,
      successors: draft.successors
    )
  }

  // MARK: - 内部処理

  /// 個別ジョブの結果.
  private struct JobResult<T: Sendable>: Sendable {
    var value: T?
    var failure: String?
  }

  /// タイムアウト付きでジョブを実行し, 失敗しても全体を止めない.
  /// 仕様書 3.2:「診断タイムアウトは 60 秒で打ち切り, 部分結果を保存し `partial` ステータス」.
  private func attempt<T: Sendable>(
    _ name: String,
    _ operation: @escaping @Sendable () async throws -> T
  ) async -> JobResult<T> {
    do {
      let value = try await withTimeout(seconds: Constant.jobTimeout, operation: operation)
      return JobResult(value: value, failure: nil)
    } catch let error as TimeoutError {
      return JobResult(value: nil, failure: "\(name): \(error.localizedDescription)")
    } catch {
      return JobResult(value: nil, failure: "\(name): \(error.localizedDescription)")
    }
  }
}
