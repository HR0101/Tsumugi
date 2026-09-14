//
//  ScoreViews.swift
//  Tsumugi
//
//  スコアの表示部品.
//
//  数値は明朝体で組み, 帯の色には草木染めの和名を添える.
//  「72 点」という数字だけでなく「山吹色＝注意が必要」という色の名前も示すことで,
//  仕様書 10.5 の「色だけに頼らない」を満たしつつ, 配色の由来も伝わるようにしている.
//

import SwiftUI

/// 一覧で使う小さな札（木札に見立てた四角い札）.
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
        .font(.caption2)
      Text(label)
        .font(.caption2)
      if let score {
        Text("\(score)")
          .font(.custom("HiraMinProN-W6", size: 13, relativeTo: .caption))
          .monospacedDigit()
      } else {
        Text("—")
          .font(.caption2)
      }
    }
    .foregroundStyle(color)
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, 3)
    .overlay {
      RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        .strokeBorder(color.opacity(0.45), lineWidth: Radius.hairline)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }
}

/// 詳細画面のスコア札. 短冊のように, 左端に染めた糸を 1 本通す.
struct ScoreCard: View {
  let title: String
  /// 経糸・緯糸のどちらかを示す 1 文字.
  let threadMark: String
  let score: Int?
  let label: String
  let symbolName: String
  let color: Color
  /// 帯に対応する伝統色の和名.
  let colorName: String
  let accessibilityText: String
  var pendingMessage: String = "まだ診断していません"

  var body: some View {
    HStack(spacing: 0) {
      // 短冊の左端を通る糸.
      Rectangle()
        .fill(score == nil ? Palette.rule : color)
        .frame(width: 3)

      VStack(alignment: .leading, spacing: Spacing.sm) {
        HStack(spacing: Spacing.xs) {
          Text(threadMark)
            .font(.custom("HiraMinProN-W6", size: 12, relativeTo: .caption2))
            .foregroundStyle(Palette.inkMuted)
          Image(systemName: symbolName)
            .font(.caption)
          Text(title)
            .font(WaFont.subheading)
        }
        .foregroundStyle(score == nil ? Palette.inkMuted : color)

        if let score {
          HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(score)")
              .font(WaFont.numeralMedium)
              .monospacedDigit()
              .contentTransition(.numericText())
              .foregroundStyle(Palette.ink)
            Text("点")
              .font(.caption2)
              .foregroundStyle(Palette.inkMuted)
          }
          Text(label)
            .font(.footnote)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
          Text(colorName)
            .font(.caption2)
            .foregroundStyle(Palette.inkMuted)
        } else {
          Text("—")
            .font(WaFont.numeralMedium)
            .foregroundStyle(Palette.rule)
          Text(pendingMessage)
            .font(.footnote)
            .foregroundStyle(Palette.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(Spacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background {
      ZStack {
        Rectangle().fill(Palette.paper)
        WashiGrain()
      }
    }
    .overlay {
      Rectangle().strokeBorder(Palette.rule, lineWidth: Radius.hairline)
    }
    .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }
}

/// 警告の札.
struct FlagChip: View {
  let flag: CredibilityFlag
  var isCompact: Bool = false

  private var tint: Color {
    flag.isYMYL ? Palette.indigo : Palette.color(for: .doubtful)
  }

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: flag.symbolName)
        .font(.caption2)
      Text(flag.displayName)
        .font(isCompact ? .caption2 : .caption)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, 3)
    .overlay {
      RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
        .strokeBorder(tint.opacity(0.45), lineWidth: Radius.hairline)
    }
    .accessibilityLabel("警告: \(flag.displayName). \(flag.detail)")
  }
}

/// スコアの内訳を示す 1 本の糸.
struct ScoreBar: View {
  let value: Int
  let color: Color
  var height: CGFloat = 3

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(Palette.rule.opacity(0.6))
          .frame(height: Radius.hairline)
          .frame(maxHeight: .infinity, alignment: .center)
        Rectangle()
          .fill(color)
          .frame(width: geometry.size.width * CGFloat(max(0, min(100, value))) / 100, height: height)
          .frame(maxHeight: .infinity, alignment: .center)
      }
    }
    .frame(height: max(height, 6))
    .accessibilityHidden(true)
  }
}
