//
//  AnalysisFeedback.swift
//  Tsumugi
//
//  仕様書 4.4.4 / 7.1 `analysis_feedbacks`: 診断結果へのユーザーフィードバック.
//

import Foundation
import SwiftData

/// フィードバックの対象.
enum FeedbackTarget: String, Codable, CaseIterable, Sendable {
  case credibility
  case freshness
  case summary

  var displayName: String {
    switch self {
    case .credibility: return "信頼度診断"
    case .freshness: return "鮮度診断"
    case .summary: return "要約"
    }
  }
}

/// フィードバックの内容.
enum FeedbackVerdict: String, Codable, CaseIterable, Sendable {
  case tooLow
  case tooHigh
  case wrongRationale
  case other

  var displayName: String {
    switch self {
    case .tooLow: return "評価が低すぎる"
    case .tooHigh: return "評価が高すぎる"
    case .wrongRationale: return "根拠が事実と異なる"
    case .other: return "その他"
    }
  }
}

@Model
final class AnalysisFeedback {
  @Attribute(.unique) var id: UUID
  var itemID: UUID
  private var targetRaw: String
  private var verdictRaw: String
  var comment: String
  var createdAt: Date
  /// サーバへ送信済みか. オフライン時は未送信のまま蓄積する.
  var isSynced: Bool

  init(itemID: UUID, target: FeedbackTarget, verdict: FeedbackVerdict, comment: String = "") {
    self.id = UUID()
    self.itemID = itemID
    self.targetRaw = target.rawValue
    self.verdictRaw = verdict.rawValue
    self.comment = comment
    self.createdAt = .now
    self.isSynced = false
  }

  var target: FeedbackTarget { FeedbackTarget(rawValue: targetRaw) ?? .credibility }
  var verdict: FeedbackVerdict { FeedbackVerdict(rawValue: verdictRaw) ?? .other }
}
