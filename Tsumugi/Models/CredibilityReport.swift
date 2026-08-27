//
//  CredibilityReport.swift
//  Tsumugi
//
//  仕様書 4.4 / 7.1 `credibility_reports`: 信頼度診断の結果.
//

import Foundation
import SwiftData

@Model
final class CredibilityReport {
  /// 総合スコア 0〜100.
  var totalScore: Int
  /// 仕様書 4.4.2 のラベル.
  var label: String

  // MARK: - カテゴリ別スコア（仕様書 4.4.1）

  var sourceScore: Int
  var transparencyScore: Int
  var evidenceScore: Int
  var neutralityScore: Int
  var corroborationScore: Int

  /// 各カテゴリの根拠. 仕様書 4.4.4 によりブラックボックス化を避けるため必須.
  var rationale: [RationaleEntry]
  var flags: [CredibilityFlag]
  var corroborations: [Corroboration]
  private var confidenceRaw: String
  var model: String
  var createdAt: Date
  /// ユーザーがこの診断を「不正確」と報告したか（仕様書 4.4.4）.
  var userDisputed: Bool

  var item: Item?

  init(
    totalScore: Int,
    label: String,
    sourceScore: Int,
    transparencyScore: Int,
    evidenceScore: Int,
    neutralityScore: Int,
    corroborationScore: Int,
    rationale: [RationaleEntry],
    flags: [CredibilityFlag],
    corroborations: [Corroboration] = [],
    confidence: AnalysisConfidence,
    model: String
  ) {
    self.totalScore = totalScore
    self.label = label
    self.sourceScore = sourceScore
    self.transparencyScore = transparencyScore
    self.evidenceScore = evidenceScore
    self.neutralityScore = neutralityScore
    self.corroborationScore = corroborationScore
    self.rationale = rationale
    self.flags = flags
    self.corroborations = corroborations
    self.confidenceRaw = confidence.rawValue
    self.model = model
    self.createdAt = .now
    self.userDisputed = false
  }

  var confidence: AnalysisConfidence {
    get { AnalysisConfidence(rawValue: confidenceRaw) ?? .medium }
    set { confidenceRaw = newValue.rawValue }
  }

  var band: CredibilityBand { CredibilityBand.from(score: totalScore) }

  /// カテゴリ別スコアを列挙順で取り出す. レーダーチャート描画に使う.
  func score(for category: CredibilityCategory) -> Int {
    switch category {
    case .source: return sourceScore
    case .transparency: return transparencyScore
    case .evidence: return evidenceScore
    case .neutrality: return neutralityScore
    case .corroboration: return corroborationScore
    }
  }

  func rationale(for category: CredibilityCategory) -> RationaleEntry? {
    rationale.first { $0.category == category }
  }

  /// YMYL 分野のフラグが立っているか. 立っていれば専門家相談の固定文言を表示する.
  var hasYMYLFlag: Bool { flags.contains(where: \.isYMYL) }

  /// VoiceOver 用の読み上げ文（仕様書 10.5）.
  var accessibilityLabel: String {
    "信頼度 \(totalScore) 点, \(label)"
  }
}
