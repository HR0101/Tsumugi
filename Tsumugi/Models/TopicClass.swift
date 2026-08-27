//
//  TopicClass.swift
//  Tsumugi
//
//  仕様書 4.5.1 / 9.5: トピック分類と分野別の情報半減期.
//

import Foundation

/// 記事のトピック分類. 鮮度診断の半減期を決定する.
enum TopicClass: String, Codable, CaseIterable, Sendable {
  case ai
  case software
  case hardware
  case market
  case regulation
  case medical
  case academic
  case news
  case howto
  case timeless

  /// 仕様書 9.5 `HALF_LIFE_DAYS`. `nil` は減衰しない（普遍的知識）ことを表す.
  var halfLifeDays: Int? {
    switch self {
    case .ai: return 120
    case .software: return 240
    case .hardware: return 365
    case .market: return 60
    case .regulation: return 500
    case .medical: return 900
    case .academic: return 1_500
    case .news: return 30
    case .howto: return 1_200
    case .timeless: return nil
    }
  }

  /// トピックを特定できなかった場合に適用する既定の半減期（日）.
  static let fallbackHalfLifeDays = 240

  var displayName: String {
    switch self {
    case .ai: return "AI・生成 AI"
    case .software: return "ソフトウェア / ライブラリ"
    case .hardware: return "ハードウェア / ガジェット"
    case .market: return "市況・経済指標"
    case .regulation: return "法令・制度・税制"
    case .medical: return "医療・健康"
    case .academic: return "学術・基礎研究"
    case .news: return "ニュース（速報性）"
    case .howto: return "ハウツー（普遍）"
    case .timeless: return "歴史・古典・普遍的知識"
    }
  }

  var symbolName: String {
    switch self {
    case .ai: return "brain"
    case .software: return "chevron.left.forwardslash.chevron.right"
    case .hardware: return "iphone.gen3"
    case .market: return "chart.line.uptrend.xyaxis"
    case .regulation: return "building.columns"
    case .medical: return "cross.case"
    case .academic: return "graduationcap"
    case .news: return "newspaper"
    case .howto: return "list.bullet.clipboard"
    case .timeless: return "books.vertical"
    }
  }
}
