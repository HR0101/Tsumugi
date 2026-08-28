//
//  SummaryTabView.swift
//  Tsumugi
//
//  仕様書 5.2 / 4.3: 詳細画面の「要約」タブ.
//  TL;DR / キーポイント / 詳細要約 / 主張と根拠 / 抽出された事実.
//

import SwiftUI
import SwiftData

struct SummaryTabView: View {
  let item: Item
  /// 原文の該当箇所へジャンプする（仕様書 SM-06）.
  let onJumpToBody: (Int) -> Void

  @State private var isDetailedExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      if let summary = item.summary {
        if summary.wasSkipped {
          skippedNotice
        } else {
          tldrSection(summary)
          keyPointsSection(summary)
          detailedSection(summary)
        }
        claimsSection(summary)
        factsSection(summary)
        highlightFocusedSection(summary)
        modelFootnote(summary)
      } else {
        EmptyStateView(
          symbolName: "text.alignleft",
          title: "要約はまだありません",
          message: item.bodyText == nil
            ? "本文を取得できていないため要約を生成できません. 原文リンクからご確認ください."
            : "要約を生成しています. しばらくお待ちください."
        )
        .frame(maxWidth: .infinity)
      }
    }
  }

  // MARK: - 各セクション

  private var skippedNotice: some View {
    Label(
      "本文が短いため要約を省略しました. 「本文」タブから全文をご覧いただけます.",
      systemImage: "text.badge.minus"
    )
    .font(.footnote)
    .foregroundStyle(.secondary)
    .cardSurface(padding: Spacing.md)
  }

  private func tldrSection(_ summary: Summary) -> some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text("TL;DR").sectionTitleStyle()
      Text(summary.tldr)
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }

  @ViewBuilder
  private func keyPointsSection(_ summary: Summary) -> some View {
    if !summary.keyPoints.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Text("キーポイント").sectionTitleStyle()
        ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { index, point in
          HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(index + 1)")
              .font(.caption.weight(.bold))
              .foregroundStyle(Color.accentColor)
              .frame(width: 18, alignment: .trailing)
            Text(point)
              .font(.callout)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
    }
  }

  @ViewBuilder
  private func detailedSection(_ summary: Summary) -> some View {
    if let detailed = summary.detailed, !detailed.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        HStack {
          Text("詳細要約").sectionTitleStyle()
          Spacer()
          Button(isDetailedExpanded ? "折りたたむ" : "すべて読む") {
            withAnimation(.easeInOut(duration: 0.2)) { isDetailedExpanded.toggle() }
          }
          .font(.caption)
        }
        Text(detailed)
          .font(.callout)
          .lineSpacing(4)
          .lineLimit(isDetailedExpanded ? nil : 6)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
    }
  }

  /// 仕様書 SM-02: 主張と根拠を分離して表示する.
  @ViewBuilder
  private func claimsSection(_ summary: Summary) -> some View {
    if !summary.claims.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Text("主張と根拠").sectionTitleStyle()
        ForEach(summary.claims) { claim in
          VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(claim.claim)
              .font(.callout.weight(.medium))
              .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: Spacing.sm) {
              Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
              Text(claim.evidence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.sm) {
              Text(claim.evidenceQualityLabel)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(evidenceColor(claim).opacity(0.14), in: Capsule())
                .foregroundStyle(evidenceColor(claim))

              if let offset = claim.sourceOffset?.first {
                Button {
                  onJumpToBody(offset)
                } label: {
                  Label("原文を見る", systemImage: "text.viewfinder")
                    .font(.caption2)
                }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, Spacing.sm)

          if claim.id != summary.claims.last?.id {
            Divider()
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
    }
  }

  /// 仕様書 SM-03: 数値・固有名詞・日付の構造化抽出.
  @ViewBuilder
  private func factsSection(_ summary: Summary) -> some View {
    if !summary.facts.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.md) {
        HStack {
          Text("記事中の数値・固有名詞").sectionTitleStyle()
          Spacer()
          Text("原文照合済み")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        ForEach(summary.facts) { fact in
          HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: fact.symbolName)
              .font(.caption)
              .foregroundStyle(Color.accentColor)
              .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
              Text(fact.value)
                .font(.callout.weight(.semibold))
              if !fact.context.isEmpty {
                Text(fact.context)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
    }
  }

  /// 仕様書 SM-07: ハイライト部分を重点化した要約.
  @ViewBuilder
  private func highlightFocusedSection(_ summary: Summary) -> some View {
    if let focused = summary.highlightFocused, !focused.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text("ハイライト箇所を中心に").sectionTitleStyle()
        Text(focused)
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
    }
  }

  private func modelFootnote(_ summary: Summary) -> some View {
    Text("生成モデル: \(summary.model) / 出力言語: \(summary.language) / \(DateStyle.short.string(from: summary.createdAt))")
      .font(.caption2)
      .foregroundStyle(.tertiary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func evidenceColor(_ claim: Claim) -> Color {
    switch claim.evidenceQuality {
    case "primary_source", "official", "academic": return Palette.color(for: .high)
    case "secondary": return Palette.color(for: .caution)
    case "single_vendor": return Palette.color(for: .doubtful)
    case "none": return Palette.color(for: .low)
    default: return .secondary
    }
  }
}
