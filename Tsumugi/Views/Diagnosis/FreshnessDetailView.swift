//
//  FreshnessDetailView.swift
//  Tsumugi
//
//  仕様書 S-05: 鮮度診断詳細.
//  鮮度ゲージ / 半減期グラフ / 陳腐化ポイント / 後続情報カード.
//

import SwiftUI

struct FreshnessDetailView: View {
  let item: Item

  @Environment(\.openURL) private var openURL
  @State private var isShowingFeedback = false

  var body: some View {
    ScrollView {
      if let report = item.freshness {
        VStack(alignment: .leading, spacing: Spacing.lg) {
          gaugeSection(report)
          halfLifeSection(report)
          adjustmentSection(report)
          obsoleteSection(report)
          successorSection(report)
          DiagnosisDisclaimer()
          footerSection(report)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
      } else {
        EmptyStateView(
          symbolName: "leaf",
          title: "鮮度は未診断です",
          message: "本文が取得できている記事を開くと診断が実行されます."
        )
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxl)
      }
    }
    .background(Palette.canvas)
    .navigationTitle("情報の新しさ")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isShowingFeedback) {
      FeedbackSheet(item: item, target: .freshness)
    }
  }

  // MARK: - ゲージ

  private func gaugeSection(_ report: FreshnessReport) -> some View {
    let color = Palette.color(for: report.stalenessLabel)

    return VStack(alignment: .leading, spacing: Spacing.md) {
      HStack(alignment: .center, spacing: Spacing.lg) {
        Gauge(value: Double(report.freshnessScore), in: 0...100) {
          EmptyView()
        } currentValueLabel: {
          Text("\(report.freshnessScore)")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(color)
        .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: Spacing.xs) {
          HStack(spacing: Spacing.xs) {
            Image(systemName: report.stalenessLabel.symbolName)
            Text(report.stalenessLabel.displayName)
              .font(.headline)
          }
          .foregroundStyle(color)

          Text(report.stalenessLabel.detail)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Divider()

      HStack {
        infoColumn(title: "トピック", value: report.topicClass.displayName, symbolName: report.topicClass.symbolName)
        Spacer()
        infoColumn(
          title: "半減期",
          value: report.halfLifeDays.map { "\($0) 日" } ?? "減衰なし",
          symbolName: "hourglass"
        )
        Spacer()
        infoColumn(
          title: "経過",
          value: report.elapsedDays.map { "\($0) 日" } ?? "不明",
          symbolName: "calendar"
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
    .accessibilityElement(children: .contain)
    .accessibilityLabel(report.accessibilityLabel)
  }

  private func infoColumn(title: String, value: String, symbolName: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(title, systemImage: symbolName)
        .font(.caption2)
        .foregroundStyle(.tertiary)
      Text(value)
        .font(.caption.weight(.semibold))
    }
  }

  // MARK: - 半減期グラフ

  @ViewBuilder
  private func halfLifeSection(_ report: FreshnessReport) -> some View {
    if let halfLife = report.halfLifeDays, let elapsed = report.elapsedDays {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Text("半減期モデル").sectionTitleStyle()

        DecayChart(
          halfLifeDays: halfLife,
          elapsedDays: elapsed,
          finalScore: report.freshnessScore,
          tint: Palette.color(for: report.stalenessLabel)
        )

        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text("鮮度 = 100 × 0.5 ^ (経過日数 ÷ 半減期) + 補正")
            .font(.caption.weight(.medium))
            .monospaced()
          Text("\(report.topicClass.displayName)分野は情報の更新が \(halfLife) 日でおよそ半分の価値になる, という前提で計算しています. 時間減衰のみでは \(report.decayedScore) 点, 補正を含めて \(report.freshnessScore) 点です.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
    } else if report.stalenessLabel == .unknown {
      Label(
        "発行日を特定できなかったため, 鮮度スコアの上限を 50 点に制限しています.",
        systemImage: "calendar.badge.exclamationmark"
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
    } else if report.stalenessLabel == .timeless {
      Label(
        "歴史や普遍的な知識を扱う記事のため, 時間による減衰を適用していません.",
        systemImage: "infinity"
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
    }
  }

  // MARK: - 補正項

  @ViewBuilder
  private func adjustmentSection(_ report: FreshnessReport) -> some View {
    if !report.adjustments.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Text("適用された補正").sectionTitleStyle()

        ForEach(report.adjustments) { adjustment in
          HStack(alignment: .top, spacing: Spacing.md) {
            Text(adjustment.delta > 0 ? "+\(adjustment.delta)" : "\(adjustment.delta)")
              .font(.subheadline.weight(.bold))
              .monospacedDigit()
              .foregroundStyle(adjustment.delta > 0 ? Palette.color(for: .high) : Palette.color(for: .doubtful))
              .frame(width: 40, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
              Text(adjustment.reason.displayName)
                .font(.subheadline.weight(.medium))
              if let evidence = adjustment.evidence, !evidence.isEmpty {
                Text(evidence)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }

        HStack {
          Text("補正の合計")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Text(report.totalAdjustment > 0 ? "+\(report.totalAdjustment)" : "\(report.totalAdjustment)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
    }
  }

  // MARK: - 陳腐化ポイント

  @ViewBuilder
  private func obsoleteSection(_ report: FreshnessReport) -> some View {
    if !report.obsoletePoints.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Text("陳腐化している可能性のある記述").sectionTitleStyle()
        ForEach(report.obsoletePoints) { point in
          VStack(alignment: .leading, spacing: Spacing.sm) {
            QuoteBlock(quote: point.quote)
            HStack(alignment: .top, spacing: Spacing.sm) {
              Image(systemName: "exclamationmark.bubble")
                .font(.caption)
                .foregroundStyle(.orange)
              Text(point.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(.bottom, Spacing.sm)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
    }
  }

  // MARK: - 後続情報

  @ViewBuilder
  private func successorSection(_ report: FreshnessReport) -> some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text("後続情報").sectionTitleStyle()

      if report.successors.isEmpty {
        Label(
          "後続情報の検索には Web 検索が必要なため, この診断では提示していません.",
          systemImage: "magnifyingglass"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      } else {
        ForEach(report.successors) { successor in
          Button {
            if let url = URL(string: successor.url) { openURL(url) }
          } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
              HStack(alignment: .top) {
                Text(successor.title)
                  .font(.subheadline.weight(.medium))
                  .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                  .font(.caption)
                  .foregroundStyle(.tertiary)
              }
              if let published = successor.publishedAt {
                Text(DateStyle.short.string(from: published))
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
              Text(successor.diffSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            }
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }

  // MARK: - フッタ

  private func footerSection(_ report: FreshnessReport) -> some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Button {
        isShowingFeedback = true
      } label: {
        Label(
          report.userDisputed ? "フィードバック送信済み" : "この診断は不正確だと報告する",
          systemImage: report.userDisputed ? "checkmark.circle" : "hand.thumbsdown"
        )
        .font(.footnote)
      }
      .buttonStyle(.bordered)

      Text("評価日時: \(DateStyle.long.string(from: report.evaluatedAt))")
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
