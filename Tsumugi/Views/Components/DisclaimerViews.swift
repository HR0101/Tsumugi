//
//  DisclaimerViews.swift
//  Tsumugi
//
//  仕様書 16.3:「診断画面の必須表示文言」と, 仕様書 10.6 の YMYL 分野の固定文言.
//  仕様書 4.4.4 の「AI の判定は参考情報である旨を常時表示する」に対応する.
//

import SwiftUI

/// 診断画面に常時表示する免責文（仕様書 16.3）.
struct DiagnosisDisclaimer: View {
  /// 一覧などで使う短縮版.
  var isCompact: Bool = false

  private static let fullText = """
  この診断は AI による自動評価であり, 正確性を保証するものではありません。
  評価対象は情報の提示方法（出典・透明性・検証可能性）であり,
  主張内容の正しさや思想的な立場を判定するものではありません。
  最終的な判断はご自身で行ってください。
  """

  private static let compactText =
    "この診断は AI による自動評価です. 主張の正しさではなく情報の提示方法を評価しています."

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: "info.circle")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Text(isCompact ? Self.compactText : Self.fullText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.md)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

/// YMYL 分野の記事に表示する固定文言（仕様書 10.6）.
struct YMYLNotice: View {
  let flags: [CredibilityFlag]

  private var applicable: [CredibilityFlag] {
    flags.filter(\.isYMYL)
  }

  var body: some View {
    if !applicable.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        ForEach(applicable) { flag in
          HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: flag.symbolName)
              .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
              Text(flag.displayName)
                .font(.footnote.weight(.semibold))
              Text(flag.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.md)
      .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
  }
}

/// 引用の体裁. 仕様書 10.6 により引用は 120 字以内に制限している.
struct QuoteBlock: View {
  let quote: String
  var caption: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(alignment: .top, spacing: Spacing.sm) {
        Rectangle()
          .fill(Color.secondary.opacity(0.4))
          .frame(width: 3)
          .clipShape(Capsule())
        Text("「\(quote)」")
          .font(.callout)
          .italic()
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let caption {
        Text(caption)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .accessibilityLabel("本文からの引用: \(quote)")
  }
}

/// 空状態の表示.
struct EmptyStateView: View {
  let symbolName: String
  let title: String
  let message: String
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: symbolName)
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(.tertiary)
      Text(title)
        .font(.headline)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
          .padding(.top, Spacing.xs)
      }
    }
    .frame(maxWidth: 360)
    .padding(Spacing.xl)
  }
}
