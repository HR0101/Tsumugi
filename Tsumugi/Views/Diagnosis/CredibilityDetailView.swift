//
//  CredibilityDetailView.swift
//  Tsumugi
//
//  仕様書 S-04: 信頼度診断詳細.
//  総合スコア / 5 カテゴリのレーダーチャート / 各根拠 / フラグ / 外部照合結果.
//

import SwiftUI

struct CredibilityDetailView: View {
  let item: Item

  @Environment(\.openURL) private var openURL
  @State private var isShowingFeedback = false

  var body: some View {
    ScrollView {
      if let report = item.credibility {
        VStack(alignment: .leading, spacing: Spacing.lg) {
          totalSection(report)
          radarSection(report)
          rationaleSection(report)
          flagSection(report)
          corroborationSection(report)
          DiagnosisDisclaimer()
          footerSection(report)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
      } else {
        EmptyStateView(
          symbolName: "checkmark.seal",
          title: "信頼度は未診断です",
          message: "本文が取得できている記事を開くと診断が実行されます."
        )
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxl)
      }
    }
    .background(WashiBackground())
    .navigationTitle("信頼度診断")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isShowingFeedback) {
      FeedbackSheet(item: item, target: .credibility)
    }
  }

  // MARK: - 総合スコア

  private func totalSection(_ report: CredibilityReport) -> some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text("\(report.totalScore)")
            .font(WaFont.numeralLarge)
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
          Text("点")
            .font(.subheadline)
            .foregroundStyle(Palette.inkMuted)
        }
        Spacer()
        Image(systemName: report.band.symbolName)
          .font(.system(size: 34))
          .foregroundStyle(Palette.color(for: report.band))
      }

      HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
        Text(report.label)
          .font(WaFont.heading)
          .foregroundStyle(Palette.color(for: report.band))
        Text(Palette.waColor(for: report.band).name)
          .font(.caption2)
          .foregroundStyle(Palette.inkMuted)
      }

      Text(report.band.detail)
        .font(.footnote)
        .foregroundStyle(Palette.inkMuted)
        .fixedSize(horizontal: false, vertical: true)

      ScoreBar(value: report.totalScore, color: Palette.color(for: report.band), height: 5)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(report.accessibilityLabel). \(report.band.detail)")
  }

  // MARK: - レーダーチャート

  private func radarSection(_ report: CredibilityReport) -> some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text("カテゴリ別スコア").sectionTitleStyle()

      RadarChart(
        axes: CredibilityCategory.allCases.map { category in
          RadarChart.Axis(
            id: category.rawValue,
            label: category.shortName,
            value: report.score(for: category),
            isDetermined: report.rationale(for: category)?.isDetermined ?? true
          )
        },
        tint: Palette.color(for: report.band)
      )

      // 重みの内訳を明示し, ブラックボックス化を避ける（仕様書 4.4.4）.
      VStack(spacing: Spacing.xs) {
        ForEach(CredibilityCategory.allCases) { category in
          HStack {
            Text(category.displayName)
              .font(.caption)
            Spacer()
            Text("重み \(Int(category.weight * 100))%")
              .font(.caption2)
              .foregroundStyle(Palette.inkMuted.opacity(0.72))
            Text(
              (report.rationale(for: category)?.isDetermined ?? true)
                ? "\(report.score(for: category)) 点"
                : "判定なし"
            )
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .frame(width: 60, alignment: .trailing)
          }
        }
      }
      .padding(.top, Spacing.sm)

      if report.rationale.contains(where: { !$0.isDetermined }) {
        Label(
          "判定できなかった項目はスコア計算から除外し, 残りの項目の重みを再正規化しています.",
          systemImage: "info.circle"
        )
        .font(.caption2)
        .foregroundStyle(Palette.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
  }

  // MARK: - 根拠

  private func rationaleSection(_ report: CredibilityReport) -> some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text("判定の根拠").sectionTitleStyle()

      ForEach(CredibilityCategory.allCases) { category in
        if let entry = report.rationale(for: category) {
          VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
              Label(category.displayName, systemImage: category.symbolName)
                .font(WaFont.subheading)
              Spacer()
              if entry.isDetermined {
                Text("\(report.score(for: category))")
                  .font(.subheadline.weight(.bold))
                  .monospacedDigit()
                  .foregroundStyle(Palette.color(for: CredibilityBand.from(score: report.score(for: category))))
              } else {
                Text("判定できませんでした")
                  .font(.caption)
                  .foregroundStyle(Palette.inkMuted)
              }
            }

            Text(entry.reason)
              .font(.footnote)
              .foregroundStyle(Palette.inkMuted)
              .fixedSize(horizontal: false, vertical: true)

            if let quote = entry.quote, !quote.isEmpty {
              QuoteBlock(quote: quote, caption: "本文からの引用")
            }

            Text(category.criteria)
              .font(.caption2)
              .foregroundStyle(Palette.inkMuted.opacity(0.72))
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, Spacing.sm)

          if category != CredibilityCategory.allCases.last {
            Divider()
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
  }

  // MARK: - フラグ

  @ViewBuilder
  private func flagSection(_ report: CredibilityReport) -> some View {
    if !report.flags.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.md) {
        Text("警告フラグ").sectionTitleStyle()
        ForEach(report.flags) { flag in
          HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: flag.symbolName)
              .font(.subheadline)
              .foregroundStyle(flag.isYMYL ? Color.accentColor : .orange)
              .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
              HStack {
                Text(flag.displayName)
                  .font(WaFont.subheading)
                Spacer()
                if flag.penalty > 0 {
                  Text("−\(Int(flag.penalty))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.color(for: .caution))
                    .monospacedDigit()
                }
              }
              Text(flag.detail)
                .font(.caption)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        Text("減点は総合スコアの算出時に適用されています.")
          .font(.caption2)
          .foregroundStyle(Palette.inkMuted.opacity(0.72))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .paperPanel()
    }
  }

  // MARK: - 外部照合

  @ViewBuilder
  private func corroborationSection(_ report: CredibilityReport) -> some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text("外部ソースとの照合").sectionTitleStyle()

      if report.corroborations.isEmpty {
        Label(
          "この診断では他ソースとの照合を行っていません. 重要な判断の前には, 別の情報源でもご確認ください.",
          systemImage: "questionmark.circle"
        )
        .font(.footnote)
        .foregroundStyle(Palette.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
      } else {
        ForEach(report.corroborations) { corroboration in
          Button {
            if let url = URL(string: corroboration.url) { openURL(url) }
          } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
              HStack(alignment: .top) {
                Image(systemName: corroboration.verdict.symbolName)
                  .foregroundStyle(verdictColor(corroboration.verdict))
                Text(corroboration.title)
                  .font(WaFont.subheading)
                  .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                  .font(.caption)
                  .foregroundStyle(Palette.inkMuted.opacity(0.72))
              }
              Text(corroboration.note)
                .font(.caption)
                .foregroundStyle(Palette.inkMuted)
                .multilineTextAlignment(.leading)
              if let published = corroboration.publishedAt {
                Text(DateStyle.short.string(from: published))
                  .font(.caption2)
                  .foregroundStyle(Palette.inkMuted.opacity(0.72))
              }
            }
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
  }

  private func verdictColor(_ verdict: Corroboration.Verdict) -> Color {
    switch verdict {
    case .supports: return Palette.color(for: .high)
    case .contradicts: return Palette.color(for: .low)
    case .unverified: return .secondary
    }
  }

  // MARK: - フッタ

  private func footerSection(_ report: CredibilityReport) -> some View {
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

      Text("診断モデル: \(report.model) / \(report.confidence.displayName) / \(DateStyle.long.string(from: report.createdAt))")
        .font(.caption2)
        .foregroundStyle(Palette.inkMuted.opacity(0.72))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
