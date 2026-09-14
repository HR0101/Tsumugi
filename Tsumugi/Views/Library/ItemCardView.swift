//
//  ItemCardView.swift
//  Tsumugi
//
//  仕様書 LB-01: 一覧のカード表示.
//  サムネイル・信頼度バッジ・鮮度バッジ・読了時間を表示する.
//

import SwiftUI

struct ItemCardView: View {
  let item: Item
  let isProcessing: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      HStack(alignment: .top, spacing: Spacing.md) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(item.title)
            .font(WaFont.heading)
            .foregroundStyle(Palette.ink)
            .lineSpacing(2)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

          ItemMetaLine(item: item)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        thumbnail
      }

      if let tldr = item.summary?.tldr, !tldr.isEmpty {
        // 要約は本文と区別するため, 上に細い罫を渡す.
        VStack(alignment: .leading, spacing: Spacing.sm) {
          Rectangle().fill(Palette.rule).frame(height: Radius.hairline)
          Text(tldr)
            .font(.subheadline)
            .foregroundStyle(Palette.inkMuted)
            .lineSpacing(2)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      ItemBadgeRow(item: item, isProcessing: isProcessing)

      if !item.tags.isEmpty {
        TagStrip(names: item.tags.map(\.name))
      }
    }
    .paperPanel()
    .overlay(alignment: .topTrailing) {
      if item.isFavorite {
        Image(systemName: "bookmark.fill")
          .font(.caption)
          .foregroundStyle(Palette.color(for: .caution))
          .padding(Spacing.sm)
          .accessibilityLabel("お気に入り")
      }
    }
  }

  @ViewBuilder
  private var thumbnail: some View {
    if let urlString = item.heroImageURL, let url = URL(string: urlString) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().aspectRatio(contentMode: .fill)
        default:
          Rectangle().fill(Palette.rule.opacity(0.35))
        }
      }
      .frame(width: 68, height: 68)
      .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
          .strokeBorder(Palette.rule, lineWidth: Radius.hairline)
      }
      .accessibilityHidden(true)
    }
  }
}

/// 出典・日付・読了時間の 1 行.
struct ItemMetaLine: View {
  let item: Item

  var body: some View {
    Text(components.joined(separator: " ・ "))
      .font(.caption)
      .foregroundStyle(Palette.inkMuted)
      .lineLimit(2)
  }

  private var components: [String] {
    var parts = [item.displayHost]
    if let author = item.author, !author.isEmpty { parts.append(author) }
    if let published = item.publishedAt {
      parts.append(DateStyle.short.string(from: published))
    }
    if item.readingMinutes > 0 {
      parts.append("約 \(item.readingMinutes) 分")
    }
    return parts
  }
}

/// スコアバッジとステータスの行.
struct ItemBadgeRow: View {
  let item: Item
  let isProcessing: Bool

  var body: some View {
    HStack(spacing: Spacing.sm) {
      if isProcessing || item.status.isInFlight {
        HStack(spacing: Spacing.xs) {
          ProgressView().controlSize(.mini)
          Text(item.status.displayName)
            .font(.caption2)
        }
        .foregroundStyle(Palette.inkMuted)
      } else {
        credibilityBadge
        freshnessBadge
      }

      Spacer(minLength: 0)

      if !item.flags.isEmpty {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption2)
          Text("\(item.flags.count)")
            .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Palette.color(for: .caution))
        .accessibilityLabel("警告 \(item.flags.count) 件")
      }
    }
  }

  @ViewBuilder
  private var credibilityBadge: some View {
    if let report = item.credibility {
      ScoreBadge(
        symbolName: report.band.symbolName,
        label: "信頼度",
        score: report.totalScore,
        color: Palette.color(for: report.band),
        accessibilityText: report.accessibilityLabel
      )
    } else {
      ScoreBadge(
        symbolName: "checkmark.seal",
        label: "信頼度",
        score: nil,
        color: Palette.rule,
        accessibilityText: "信頼度は未診断です"
      )
    }
  }

  @ViewBuilder
  private var freshnessBadge: some View {
    if let report = item.freshness {
      ScoreBadge(
        symbolName: report.stalenessLabel.symbolName,
        label: "鮮度",
        score: report.freshnessScore,
        color: Palette.color(for: report.stalenessLabel),
        accessibilityText: report.accessibilityLabel
      )
    } else {
      ScoreBadge(
        symbolName: "leaf",
        label: "鮮度",
        score: nil,
        color: Palette.rule,
        accessibilityText: "鮮度は未診断です"
      )
    }
  }
}

/// タグを横に並べる.
struct TagStrip: View {
  let names: [String]
  var limit: Int = 4

  var body: some View {
    HStack(spacing: Spacing.xs) {
      ForEach(names.prefix(limit), id: \.self) { name in
        Text(name)
          .font(.caption2)
          .foregroundStyle(Palette.inkMuted)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, 3)
          .overlay {
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
              .strokeBorder(Palette.rule, lineWidth: Radius.hairline)
          }
      }
      if names.count > limit {
        Text("ほか \(names.count - limit)")
          .font(.caption2)
          .foregroundStyle(Palette.inkMuted)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("タグ: \(names.joined(separator: ", "))")
  }
}

/// 仕様書 LB-01: リスト表示（カードより情報密度を高くする）.
struct ItemRowView: View {
  let item: Item
  let isProcessing: Bool

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(item.title)
          .font(WaFont.subheading)
          .foregroundStyle(Palette.ink)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        ItemMetaLine(item: item)
        ItemBadgeRow(item: item, isProcessing: isProcessing)
      }
      if item.isFavorite {
        Image(systemName: "bookmark.fill")
          .font(.caption2)
          .foregroundStyle(Palette.color(for: .caution))
      }
    }
    .padding(.vertical, Spacing.xs)
  }
}
