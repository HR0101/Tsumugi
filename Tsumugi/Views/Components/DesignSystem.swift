//
//  DesignSystem.swift
//  Tsumugi
//
//  画面全体で共有する配色・余白・書体の定義.
//  仕様書 10.5 に従い, 色は必ずアイコン形状とテキストラベルを伴って使う.
//

import SwiftUI

enum Palette {

  /// 信頼度スコアの帯に対応する色（仕様書 4.4.2）.
  static func color(for band: CredibilityBand) -> Color {
    switch band {
    case .high: return Color(red: 0.13, green: 0.55, blue: 0.33)
    case .moderate: return Color(red: 0.42, green: 0.60, blue: 0.20)
    case .caution: return Color(red: 0.76, green: 0.58, blue: 0.10)
    case .doubtful: return Color(red: 0.82, green: 0.42, blue: 0.12)
    case .low: return Color(red: 0.76, green: 0.22, blue: 0.22)
    }
  }

  /// 鮮度ラベルに対応する色.
  static func color(for label: StalenessLabel) -> Color {
    switch label {
    case .current: return Color(red: 0.13, green: 0.55, blue: 0.40)
    case .aging: return Color(red: 0.68, green: 0.55, blue: 0.15)
    case .stale: return Color(red: 0.82, green: 0.45, blue: 0.13)
    case .obsolete: return Color(red: 0.74, green: 0.24, blue: 0.24)
    case .timeless: return Color(red: 0.30, green: 0.40, blue: 0.66)
    case .unknown: return Color.secondary
    }
  }

  /// 記事カードの背景.
  static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
  /// 画面の背景.
  static let canvas = Color(uiColor: .systemGroupedBackground)
  /// 罫線.
  static let hairline = Color(uiColor: .separator)
}

enum Spacing {
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 16
  static let xl: CGFloat = 24
  static let xxl: CGFloat = 32
}

enum Radius {
  static let card: CGFloat = 14
  static let chip: CGFloat = 8
}

extension View {
  /// カード状の背景を適用する.
  func cardSurface(padding: CGFloat = Spacing.lg) -> some View {
    self
      .padding(padding)
      .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
  }

  /// セクション見出しの体裁.
  func sectionTitleStyle() -> some View {
    self
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.secondary)
      .textCase(nil)
  }
}

/// 画面全体で使う日付表記.
enum DateStyle {
  static let short: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yyyy/MM/dd"
    return formatter
  }()

  static let long: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yyyy年M月d日"
    return formatter
  }()

  static func relative(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: .now)
  }
}
