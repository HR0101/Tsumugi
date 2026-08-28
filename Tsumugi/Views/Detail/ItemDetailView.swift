//
//  ItemDetailView.swift
//  Tsumugi
//
//  仕様書 S-03 / 5.2: Item 詳細画面.
//  ヘッダ（タイトル・出典・日付）/ スコアリング / タブ（要約・本文・診断・メモ）.
//

import SwiftUI
import SwiftData

struct ItemDetailView: View {

  @Bindable var item: Item

  @Environment(\.modelContext) private var modelContext
  @Environment(\.openURL) private var openURL
  @Environment(SettingsStore.self) private var settings
  @Environment(IngestService.self) private var ingest

  @State private var selectedTab: DetailTab = .summary
  @State private var isShowingReader = false
  @State private var isShowingFeedback = false
  @State private var feedbackTarget: FeedbackTarget = .credibility
  /// 本文へジャンプする際の対象オフセット（仕様書 SM-06）.
  @State private var pendingBodyOffset: Int?

  enum DetailTab: String, CaseIterable, Identifiable {
    case summary
    case body
    case diagnosis
    case notes

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .summary: return "要約"
      case .body: return "本文"
      case .diagnosis: return "診断"
      case .notes: return "メモ"
      }
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        header
        ItemWeaveBand(item: item)
        scoreSection
        warningSection
        tabPicker
        tabContent
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.bottom, Spacing.xxl)
    }
    .background(WashiBackground())
    .navigationTitle(item.displayHost)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbarContent }
    .task {
      // 仕様書 12.2: 詳細診断は Item を開いた時に初回実行する.
      await ingest.runDeepAnalysisIfNeeded(for: item)
      markAsRead()
    }
    .fullScreenCover(isPresented: $isShowingReader) {
      ReaderView(item: item, initialOffset: pendingBodyOffset)
    }
    .sheet(isPresented: $isShowingFeedback) {
      FeedbackSheet(item: item, target: feedbackTarget)
    }
  }

  // MARK: - ヘッダ

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(item.title)
        .font(WaFont.title)
        .foregroundStyle(Palette.ink)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)

      Text(metaLine)
        .font(.footnote)
        .foregroundStyle(Palette.inkMuted)

      if item.readingMinutes > 0 {
        Label("約 \(item.readingMinutes) 分で読めます", systemImage: "clock")
          .font(.footnote)
          .foregroundStyle(Palette.inkMuted)
      }

      if item.status.isInFlight || ingest.inFlightItemIDs.contains(item.id) {
        HStack(spacing: Spacing.sm) {
          ProgressView().controlSize(.small)
          Text(item.status.displayName)
            .font(.footnote)
            .foregroundStyle(Palette.inkMuted)
        }
        .padding(.top, Spacing.xs)
      }

      if let reason = item.failureReason {
        Label(reason, systemImage: "exclamationmark.circle")
          .font(.caption)
          .foregroundStyle(Palette.color(for: .doubtful))
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, Spacing.xs)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, Spacing.sm)
  }

  private var metaLine: String {
    var parts = [item.displayHost]
    if let author = item.author, !author.isEmpty { parts.append(author) }
    if let published = item.publishedAt {
      parts.append(DateStyle.short.string(from: published))
    } else {
      parts.append("発行日不明")
    }
    if let updated = item.updatedAtSource {
      parts.append("更新 \(DateStyle.short.string(from: updated))")
    }
    return parts.joined(separator: " · ")
  }

  // MARK: - スコア

  private var scoreSection: some View {
    HStack(alignment: .top, spacing: Spacing.md) {
      NavigationLink {
        CredibilityDetailView(item: item)
      } label: {
        credibilityCard
      }
      .buttonStyle(.plain)
      .disabled(item.credibility == nil)

      NavigationLink {
        FreshnessDetailView(item: item)
      } label: {
        freshnessCard
      }
      .buttonStyle(.plain)
      .disabled(item.freshness == nil)
    }
  }

  @ViewBuilder
  private var credibilityCard: some View {
    if let report = item.credibility {
      ScoreCard(
        title: "信頼度",
        threadMark: "経",
        score: report.totalScore,
        label: report.label,
        symbolName: report.band.symbolName,
        color: Palette.color(for: report.band),
        colorName: Palette.waColor(for: report.band).name,
        accessibilityText: report.accessibilityLabel + ". 詳細を開くにはダブルタップします."
      )
    } else {
      ScoreCard(
        title: "信頼度",
        threadMark: "経",
        score: nil,
        label: "",
        symbolName: "checkmark.seal",
        color: Palette.rule,
        colorName: "",
        accessibilityText: "信頼度は未診断です",
        pendingMessage: pendingMessage
      )
    }
  }

  @ViewBuilder
  private var freshnessCard: some View {
    if let report = item.freshness {
      ScoreCard(
        title: "鮮度",
        threadMark: "緯",
        score: report.freshnessScore,
        label: report.stalenessLabel.displayName,
        symbolName: report.stalenessLabel.symbolName,
        color: Palette.color(for: report.stalenessLabel),
        colorName: Palette.waColor(for: report.stalenessLabel).name,
        accessibilityText: report.accessibilityLabel + ". 詳細を開くにはダブルタップします."
      )
    } else {
      ScoreCard(
        title: "鮮度",
        threadMark: "緯",
        score: nil,
        label: "",
        symbolName: "leaf",
        color: Palette.rule,
        colorName: "",
        accessibilityText: "鮮度は未診断です",
        pendingMessage: pendingMessage
      )
    }
  }

  private var pendingMessage: String {
    if settings.hasExceededFreeQuota { return "今月の無料枠を使い切りました" }
    if item.bodyText == nil { return "本文を取得できていません" }
    return "診断を準備しています"
  }

  // MARK: - 警告

  @ViewBuilder
  private var warningSection: some View {
    let flags = item.flags
    let successorCount = item.freshness?.successors.count ?? 0

    if !flags.isEmpty || successorCount > 0 {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        ForEach(flags) { flag in
          Label {
            Text(flag.displayName)
              .font(.footnote)
              .foregroundStyle(Palette.ink)
          } icon: {
            Image(systemName: flag.symbolName)
              .foregroundStyle(Palette.color(for: .caution))
          }
        }
        if successorCount > 0 {
          Label {
            Text("より新しい情報が \(successorCount) 件見つかりました")
              .font(.footnote)
              .foregroundStyle(Palette.ink)
          } icon: {
            Image(systemName: "arrow.forward.circle")
              .foregroundStyle(Palette.color(for: .caution))
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Spacing.md)
      .background(Palette.color(for: .caution).opacity(0.10))
      .overlay(alignment: .leading) {
        Rectangle().fill(Palette.color(for: .caution)).frame(width: 2)
      }
      .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }
  }

  // MARK: - タブ

  private var tabPicker: some View {
    Picker("表示内容", selection: $selectedTab) {
      ForEach(DetailTab.allCases) { tab in
        Text(tab.displayName).tag(tab)
      }
    }
    .pickerStyle(.segmented)
  }

  @ViewBuilder
  private var tabContent: some View {
    switch selectedTab {
    case .summary:
      SummaryTabView(item: item) { offset in
        pendingBodyOffset = offset
        isShowingReader = true
      }
    case .body:
      BodyTabView(item: item) {
        pendingBodyOffset = nil
        isShowingReader = true
      }
    case .diagnosis:
      DiagnosisTabView(item: item) { target in
        feedbackTarget = target
        isShowingFeedback = true
      }
    case .notes:
      NotesTabView(item: item)
    }
  }

  // MARK: - ツールバー

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Menu {
        Button {
          item.isFavorite.toggle()
          try? modelContext.save()
        } label: {
          Label(
            item.isFavorite ? "お気に入りから外す" : "お気に入りに追加",
            systemImage: item.isFavorite ? "star.slash" : "star"
          )
        }

        Button {
          item.isRead.toggle()
          try? modelContext.save()
        } label: {
          Label(item.isRead ? "未読にする" : "既読にする", systemImage: item.isRead ? "circle" : "checkmark.circle")
        }

        Divider()

        Button {
          isShowingReader = true
        } label: {
          Label("リーダーで読む", systemImage: "doc.text")
        }
        .disabled(item.bodyText == nil)

        if let url = URL(string: item.canonicalURL) {
          Button {
            openURL(url)
          } label: {
            Label("ブラウザで原文を開く", systemImage: "safari")
          }
          // 仕様書 10.6: 対外共有は URL と自作の要約のみに限定する.
          ShareLink(item: url, subject: Text(item.title), message: Text(item.summary?.tldr ?? "")) {
            Label("原文リンクと要約を共有", systemImage: "square.and.arrow.up")
          }
        }

        Divider()

        Button {
          Task { await ingest.reanalyze(item) }
        } label: {
          Label("再診断する", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(item.bodyText == nil || ingest.inFlightItemIDs.contains(item.id))
      } label: {
        Label("その他", systemImage: "ellipsis.circle")
      }
    }
  }

  private func markAsRead() {
    guard !item.isRead else { return }
    item.isRead = true
    try? modelContext.save()
  }
}
