//
//  StalenessLabel.swift
//  Tsumugi
//
//  仕様書 4.5.3 / 9.5: 鮮度スコアに対応する陳腐化ラベル.
//

import Foundation

/// 情報の新しさを表すラベル.
enum StalenessLabel: String, Codable, CaseIterable, Sendable {
  case current
  case aging
  case stale
  case obsolete
  case timeless
  case unknown

  /// 仕様書 9.5 `toStalenessLabel` に対応する閾値.
  private enum Threshold {
    static let current = 75
    static let aging = 45
    static let stale = 20
  }

  /// スコアからラベルを決定する（`timeless` / `unknown` は呼び出し側で判定する）.
  static func from(score: Int) -> StalenessLabel {
    if score >= Threshold.current { return .current }
    if score >= Threshold.aging { return .aging }
    if score >= Threshold.stale { return .stale }
    return .obsolete
  }

  var displayName: String {
    switch self {
    case .current: return "最新"
    case .aging: return "やや古い"
    case .stale: return "古くなっている可能性"
    case .obsolete: return "陳腐化の可能性が高い"
    case .timeless: return "時間で古くならない"
    case .unknown: return "判定できません"
    }
  }

  var detail: String {
    switch self {
    case .current: return "この分野の情報更新ペースから見て, まだ十分に通用する内容です."
    case .aging: return "公開から時間が経っています. 重要な数値や手順は最新情報での確認をおすすめします."
    case .stale: return "この分野の半減期を大きく超えています. 前提が変わっている可能性があります."
    case .obsolete: return "内容が現状と大きく食い違っている可能性があります. 後続情報の確認を強くおすすめします."
    case .timeless: return "歴史や普遍的知識を扱うため, 時間経過による劣化は考慮しません."
    case .unknown: return "発行日を特定できなかったため, 鮮度は参考値です（上限 50 点）."
    }
  }

  var symbolName: String {
    switch self {
    case .current: return "leaf.fill"
    case .aging: return "clock.badge"
    case .stale: return "clock.badge.exclamationmark"
    case .obsolete: return "exclamationmark.octagon.fill"
    case .timeless: return "infinity"
    case .unknown: return "questionmark.circle"
    }
  }
}
