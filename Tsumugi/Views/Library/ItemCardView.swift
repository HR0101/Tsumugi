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
            .font(.headline)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

          ItemMetaLine(item: item)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        thumbnail
      }

      if let tldr = item.summary?.tldr, !tldr.isEmpty {
        Text(tldr)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }

      ItemBadgeRow(item: item, isProcessing: isProcessing)

      if !item.tags.isEmpty {
        TagStrip(names: item.tags.map(\.name))
      }
    }
    .cardSurface()
    .overlay(alignment: .topTrailing) {
      if item.isFavorite {
        Image(systemName: "star.fill")
          .font(.caption)
          .foregroundStyle(.yellow)
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
          Rectangle().fill(Color.secondary.opacity(0.12))
        }
      }
      .frame(width: 72, height: 72)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .accessibilityHidden(true)
    }
  }
}

/// 出典・日付・読了時間の 1 行.
struct ItemMetaLine: View {
  let item: Item

  var body: some View {
    Text(components.joined(separator: " · "))
      .font(.caption)
      .foregroundStyle(.secondary)
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
        .foregroundStyle(.secondary)
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
        .foregroundStyle(.orange)
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
        color: .secondary,
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
        color: .secondary,
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
        Text("#\(name)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, 3)
          .background(Color.secondary.opacity(0.10), in: Capsule())
      }
      if names.count > limit {
        Text("+\(names.count - limit)")
          .font(.caption2)
          .foregroundStyle(.tertiary)
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
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        ItemMetaLine(item: item)
        ItemBadgeRow(item: item, isProcessing: isProcessing)
      }
      if item.isFavorite {
        Image(systemName: "star.fill")
          .font(.caption2)
          .foregroundStyle(.yellow)
      }
    }
    .padding(.vertical, Spacing.xs)
  }
}
