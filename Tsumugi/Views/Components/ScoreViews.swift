//
//  ScoreViews.swift
//  Tsumugi
//
//  スコアの表示部品.
//  仕様書 10.5:「色分けに加え, 必ずアイコン形状とテキストラベルを併記する」.
//

import SwiftUI

/// 一覧カード用の小さなスコアバッジ.
struct ScoreBadge: View {
  let symbolName: String
  let label: String
  let score: Int?
  let color: Color
  /// VoiceOver に読ませる文（仕様書 10.5）.
  let accessibilityText: String

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: symbolName)
        .font(.caption2.weight(.semibold))
      Text(label)
        .font(.caption2.weight(.medium))
      if let score {
        Text("\(score)")
          .font(.caption.weight(.bold))
          .monospacedDigit()
      } else {
        Text("—")
          .font(.caption.weight(.bold))
      }
    }
    .foregroundStyle(color)
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background(color.opacity(0.12), in: Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }
}

/// 詳細画面のスコアカード. 仕様書 5.2 のレイアウトに対応する.
struct ScoreCard: View {
  let title: String
  let score: Int?
  let label: String
  let symbolName: String
  let color: Color
  let accessibilityText: String
  /// 未診断のときに表示する説明.
  var pendingMessage: String = "まだ診断していません"

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: symbolName)
          .font(.subheadline.weight(.semibold))
        Text(title)
          .font(.subheadline.weight(.semibold))
      }
      .foregroundStyle(color)

      if let score {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text("\(score)")
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
          Text("/100")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(label)
          .font(.footnote.weight(.medium))
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("—")
          .font(.system(size: 40, weight: .bold, design: .rounded))
          .foregroundStyle(.tertiary)
        Text(pendingMessage)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
    .overlay(alignment: .leading) {
      // 色に頼らない手がかりとして, 左端に帯を置く.
      Rectangle()
        .fill(color)
        .frame(width: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .padding(.vertical, Spacing.md)
        .padding(.leading, 2)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }
}

/// 警告フラグのチップ.
struct FlagChip: View {
  let flag: CredibilityFlag
  var isCompact: Bool = false

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: flag.symbolName)
        .font(.caption2)
      Text(flag.displayName)
        .font(isCompact ? .caption2 : .caption)
    }
    .foregroundStyle(flag.isYMYL ? Color.accentColor : Color.orange)
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xs)
    .background(
      (flag.isYMYL ? Color.accentColor : Color.orange).opacity(0.12),
      in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
    )
    .accessibilityLabel("警告: \(flag.displayName). \(flag.detail)")
  }
}

/// スコアの内訳を示す横棒.
struct ScoreBar: View {
  let value: Int
  let color: Color
  var height: CGFloat = 6

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.secondary.opacity(0.15))
        Capsule()
          .fill(color)
          .frame(width: geometry.size.width * CGFloat(max(0, min(100, value))) / 100)
      }
    }
    .frame(height: height)
    .accessibilityHidden(true)
  }
}
