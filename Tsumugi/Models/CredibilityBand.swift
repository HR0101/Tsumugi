//
//  CredibilityBand.swift
//  Tsumugi
//
//  仕様書 4.4.2: 信頼度スコアの帯とラベル.
//

import Foundation

/// 信頼度スコアの区分. 仕様書 4.4.2 の表に対応する.
enum CredibilityBand: String, Codable, CaseIterable, Sendable {
  case high
  case moderate
  case caution
  case doubtful
  case low

  private enum Threshold {
    static let high = 85
    static let moderate = 70
    static let caution = 50
    static let doubtful = 30
  }

  static func from(score: Int) -> CredibilityBand {
    if score >= Threshold.high { return .high }
    if score >= Threshold.moderate { return .moderate }
    if score >= Threshold.caution { return .caution }
    if score >= Threshold.doubtful { return .doubtful }
    return .low
  }

  /// 仕様書 9.4 `toLabel` と一致する日本語ラベル.
  var displayName: String {
    switch self {
    case .high: return "高い信頼性"
    case .moderate: return "おおむね信頼できる"
    case .caution: return "注意が必要"
    case .doubtful: return "疑わしい"
    case .low: return "信頼性が低い"
    }
  }

  var detail: String {
    switch self {
    case .high: return "一次情報・公的機関を中心に構成されています."
    case .moderate: return "出典は提示されていますが, 軽微な懸念があります."
    case .caution: return "出典が不足しているか, 記述に偏りが見られます."
    case .doubtful: return "検証が難しい主張が多く含まれます."
    case .low: return "宣伝性が強い, または裏付けが乏しい記述が目立ちます."
    }
  }

  /// 色に加えて必ず併記するアイコン. 仕様書 10.5（色覚多様性への配慮）.
  var symbolName: String {
    switch self {
    case .high: return "checkmark.seal.fill"
    case .moderate: return "checkmark.circle.fill"
    case .caution: return "exclamationmark.circle.fill"
    case .doubtful: return "exclamationmark.triangle.fill"
    case .low: return "xmark.octagon.fill"
    }
  }
}
