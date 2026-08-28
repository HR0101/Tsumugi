//
//  DiagnosisTabView.swift
//  Tsumugi
//
//  仕様書 5.2: 詳細画面の「診断」タブ.
//  信頼度・鮮度の要点をまとめ, それぞれの詳細画面（S-04 / S-05）へ導く.
//

import SwiftUI
import SwiftData

struct DiagnosisTabView: View {
  let item: Item
  let onFeedback: (FeedbackTarget) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      DiagnosisDisclaimer()

      if let credibility = item.credibility {
        YMYLNotice(flags: credibility.flags)
        credibilitySummary(credibility)
      }

      if let freshness = item.freshness {
        freshnessSummary(freshness)
      }

      if item.credibility == nil && item.freshness == nil {
        EmptyStateView(
          symbolName: "sparkle.magnifyingglass",
          title: "診断はまだありません",
          message: "記事を開くと信頼度と鮮度の診断が実行されます. 本文を取得できていない記事は診断できません."
        )
        .frame(maxWidth: .infinity)
      }
    }
  }

  // MARK: - 信頼度

  private func credibilitySummary(_ report: CredibilityReport) -> some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      HStack {
        Text("信頼度の内訳").sectionTitleStyle()
        Spacer()
        NavigationLink {
          CredibilityDetailView(item: item)
        } label: {
          Text("詳しく見る").font(.caption)
        }
      }

      ForEach(CredibilityCategory.allCases) { category in
        let entry = report.rationale(for: category)
        let isDetermined = entry?.isDetermined ?? true

        VStack(alignment: .leading, spacing: Spacing.xs) {
          HStack {
            Label(category.shortName, systemImage: category.symbolName)
              .font(.caption.weight(.medium))
              .labelStyle(.titleAndIcon)
            Spacer()
            Text(isDetermined ? "\(report.score(for: category))" : "判定なし")
              .font(.caption.weight(.bold))
              .monospacedDigit()
              .foregroundStyle(isDetermined ? .primary : .secondary)
          }
          if isDetermined {
            ScoreBar(value: report.score(for: category), color: Palette.color(for: report.band))
          } else {
            ScoreBar(value: 0, color: .secondary)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          isDetermined
            ? "\(category.displayName) \(report.score(for: category)) 点"
            : "\(category.displayName) は判定できませんでした"
        )
      }

      if !report.flags.isEmpty {
        FlowLayout(spacing: Spacing.sm) {
          ForEach(report.flags) { flag in
            FlagChip(flag: flag)
          }
        }
        .padding(.top, Spacing.xs)
      }

      HStack {
        Text(report.confidence.displayName)
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          onFeedback(.credibility)
        } label: {
          Label("この診断は不正確", systemImage: "hand.thumbsdown")
            .font(.caption2)
        }
        .foregroundStyle(report.userDisputed ? Color.accentColor : Color.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }

  // MARK: - 鮮度

  private func freshnessSummary(_ report: FreshnessReport) -> some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      HStack {
        Text("情報の新しさ").sectionTitleStyle()
        Spacer()
        NavigationLink {
          FreshnessDetailView(item: item)
        } label: {
          Text("詳しく見る").font(.caption)
        }
      }

      HStack(spacing: Spacing.md) {
        Label(report.topicClass.displayName, systemImage: report.topicClass.symbolName)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        if let halfLife = report.halfLifeDays {
          Text("半減期 \(halfLife) 日")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Text(report.stalenessLabel.detail)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if !report.obsoletePoints.isEmpty {
        VStack(alignment: .leading, spacing: Spacing.sm) {
          Text("陳腐化している可能性のある記述")
            .font(.caption.weight(.semibold))
          ForEach(report.obsoletePoints.prefix(2)) { point in
            QuoteBlock(quote: point.quote, caption: point.reason)
          }
        }
        .padding(.top, Spacing.xs)
      }

      HStack {
        Spacer()
        Button {
          onFeedback(.freshness)
        } label: {
          Label("この診断は不正確", systemImage: "hand.thumbsdown")
            .font(.caption2)
        }
        .foregroundStyle(report.userDisputed ? Color.accentColor : Color.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }
}

/// 仕様書 4.4.4: ユーザーが判定に反論できるフィードバック導線.
struct FeedbackSheet: View {
  let item: Item
  let target: FeedbackTarget

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  @State private var verdict: FeedbackVerdict = .wrongRationale
  @State private var comment = ""

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("内容", selection: $verdict) {
            ForEach(FeedbackVerdict.allCases, id: \.self) { value in
              Text(value.displayName).tag(value)
            }
          }
          .pickerStyle(.inline)
          .labelsHidden()
        } header: {
          Text("\(target.displayName)のどこが不正確でしたか")
        }

        Section {
          TextEditor(text: $comment)
            .frame(minHeight: 100)
        } header: {
          Text("補足（任意）")
        } footer: {
          Text("送信内容はこの端末に保存され, 診断ロジックの改善に使われます. サーバ同期を有効にすると開発者へ送信されます.")
        }
      }
      .navigationTitle("診断へのフィードバック")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("送信") { submit() }
        }
      }
    }
  }

  private func submit() {
    let feedback = AnalysisFeedback(itemID: item.id, target: target, verdict: verdict, comment: comment)
    modelContext.insert(feedback)

    switch target {
    case .credibility: item.credibility?.userDisputed = true
    case .freshness: item.freshness?.userDisputed = true
    case .summary: break
    }

    try? modelContext.save()
    dismiss()
  }
}
