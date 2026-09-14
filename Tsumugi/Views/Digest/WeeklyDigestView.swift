//
//  WeeklyDigestView.swift
//  Tsumugi
//
//  仕様書 S-11: 週次ダイジェスト.
//  陳腐化アラート / 未読リマインド / 保存傾向レポート.
//

import SwiftUI
import SwiftData

struct WeeklyDigestView: View {

  @Query(sort: \Item.savedAt, order: .reverse) private var allItems: [Item]
  @Environment(IngestService.self) private var ingest
  @Environment(SettingsStore.self) private var settings

  @State private var isRefreshing = false

  /// 直近 1 週間に保存した記事.
  private var recentItems: [Item] {
    guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) else { return [] }
    return allItems.filter { $0.savedAt >= weekAgo }
  }

  /// 陳腐化している可能性のある記事.
  private var staleItems: [Item] {
    allItems
      .filter { item in
        guard let label = item.freshness?.stalenessLabel else { return false }
        return label == .stale || label == .obsolete
      }
      .sorted { ($0.freshnessScore ?? 0) < ($1.freshnessScore ?? 0) }
  }

  /// 注意が必要な記事（信頼度 50 未満）.
  private var cautionItems: [Item] {
    allItems
      .filter { ($0.credibilityScore ?? 100) < 50 }
      .sorted { ($0.credibilityScore ?? 0) < ($1.credibilityScore ?? 0) }
  }

  private var unreadItems: [Item] {
    allItems.filter { !$0.isRead }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.lg) {
          summaryCard
          if !staleItems.isEmpty { section(title: "古くなった可能性のある記事", symbolName: "clock.badge.exclamationmark", items: Array(staleItems.prefix(5))) }
          if !cautionItems.isEmpty { section(title: "注意が必要な記事", symbolName: "exclamationmark.triangle", items: Array(cautionItems.prefix(5))) }
          if !unreadItems.isEmpty { section(title: "未読リマインド", symbolName: "book", items: Array(recommendedUnread.prefix(3))) }
          trendCard

          if allItems.isEmpty {
            EmptyStateView(
              symbolName: "chart.bar.doc.horizontal",
              title: "まだデータがありません",
              message: "記事を保存すると, 週ごとの傾向と陳腐化アラートがここに表示されます."
            )
            .frame(maxWidth: .infinity)
          }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
      }
      .background(WashiBackground())
      .navigationTitle("ダイジェスト")
      .navigationDestination(for: Item.self) { item in
        ItemDetailView(item: item)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await refresh() }
          } label: {
            if isRefreshing {
              ProgressView().controlSize(.small)
            } else {
              Label("鮮度を再評価", systemImage: "arrow.clockwise")
            }
          }
          .disabled(isRefreshing || allItems.isEmpty)
        }
      }
    }
  }

  // MARK: - サマリ

  private var summaryCard: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text("今週のまとめ").sectionTitleStyle()

      HStack(spacing: Spacing.lg) {
        statColumn(value: recentItems.count, label: "保存", symbolName: "tray.and.arrow.down", color: .accentColor)
        statColumn(value: unreadItems.count, label: "未読", symbolName: "book", color: .secondary)
        statColumn(value: staleItems.count, label: "要確認", symbolName: "clock.badge.exclamationmark", color: Palette.color(for: .stale))
        statColumn(value: cautionItems.count, label: "注意", symbolName: "exclamationmark.triangle", color: Palette.color(for: .doubtful))
      }

      if staleItems.isEmpty && cautionItems.isEmpty && !allItems.isEmpty {
        Label("いま注意が必要な記事はありません.", systemImage: "checkmark.circle")
          .font(.footnote)
          .foregroundStyle(Palette.inkMuted)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
  }

  private func statColumn(value: Int, label: String, symbolName: String, color: Color) -> some View {
    VStack(spacing: Spacing.xs) {
      Image(systemName: symbolName)
        .font(.caption)
        .foregroundStyle(color)
      Text("\(value)")
        .font(WaFont.numeralMedium)
        .monospacedDigit()
      Text(label)
        .font(.caption2)
        .foregroundStyle(Palette.inkMuted)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label) \(value) 件")
  }

  // MARK: - 記事リスト

  private func section(title: String, symbolName: String, items: [Item]) -> some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Label(title, systemImage: symbolName)
        .font(WaFont.subheading)
        .foregroundStyle(Palette.inkMuted)

      ForEach(items) { item in
        NavigationLink(value: item) {
          ItemRowView(item: item, isProcessing: ingest.inFlightItemIDs.contains(item.id))
        }
        .buttonStyle(.plain)

        if item.id != items.last?.id { Divider() }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
  }

  /// 仕様書 LB-12 の「今日読むべき 3 件」に相当する簡易レコメンド.
  /// 信頼度が高く, 鮮度が落ちる前の未読記事を優先する.
  private var recommendedUnread: [Item] {
    unreadItems.sorted { lhs, rhs in
      score(for: lhs) > score(for: rhs)
    }
  }

  private func score(for item: Item) -> Double {
    let credibility = Double(item.credibilityScore ?? 50)
    let freshness = Double(item.freshnessScore ?? 50)
    // 鮮度が落ちかけている記事ほど「先に読むべき」なので, 中程度の鮮度を高く評価する.
    let urgency = 100 - abs(freshness - 55)
    return credibility * 0.6 + urgency * 0.4
  }

  // MARK: - 保存傾向

  private var trendCard: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text("保存の傾向").sectionTitleStyle()

      if topicCounts.isEmpty {
        Text("診断済みの記事が増えると, よく読んでいる分野が見えてきます.")
          .font(.footnote)
          .foregroundStyle(Palette.inkMuted)
      } else {
        ForEach(topicCounts, id: \.topic) { entry in
          VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
              Label(entry.topic.displayName, systemImage: entry.topic.symbolName)
                .font(.caption)
              Spacer()
              Text("\(entry.count) 件")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.inkMuted)
            }
            ScoreBar(
              value: Int(Double(entry.count) / Double(maxTopicCount) * 100),
              color: .accentColor
            )
          }
        }
      }

      if let average = averageCredibility {
        Divider().padding(.vertical, Spacing.xs)
        HStack {
          Text("保存した記事の平均信頼度")
            .font(.caption)
            .foregroundStyle(Palette.inkMuted)
          Spacer()
          Text("\(average)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Palette.color(for: CredibilityBand.from(score: average)))
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
  }

  private var topicCounts: [(topic: TopicClass, count: Int)] {
    let topics = allItems.compactMap { $0.freshness?.topicClass }
    let counts = Dictionary(grouping: topics, by: { $0 }).mapValues(\.count)
    return counts
      .sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }
      .prefix(5)
      .map { (topic: $0.key, count: $0.value) }
  }

  private var maxTopicCount: Int {
    max(topicCounts.first?.count ?? 1, 1)
  }

  private var averageCredibility: Int? {
    let scores = allItems.compactMap(\.credibilityScore)
    guard !scores.isEmpty else { return nil }
    return scores.reduce(0, +) / scores.count
  }

  private func refresh() async {
    isRefreshing = true
    await ingest.refreshStalenessBatch()
    isRefreshing = false
  }
}
