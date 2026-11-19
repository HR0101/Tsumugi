//
//  LibraryView.swift
//  Tsumugi
//
//  仕様書 S-02: ライブラリ（ホーム）.
//  検索バー / フィルタチップ / Item カードリスト.
//

import SwiftUI
import SwiftData

struct LibraryView: View {

  @Environment(\.modelContext) private var modelContext
  @Environment(SettingsStore.self) private var settings
  @Environment(IngestService.self) private var ingest
  @Environment(AppOverlayState.self) private var overlay: AppOverlayState?

  /// SwiftData から全件取得し, 絞り込みはメモリ上で行う.
  /// フィルタ条件が動的に変わるため, 述語をその都度作り直すより単純で速い.
  @Query(sort: \Item.savedAt, order: .reverse) private var allItems: [Item]

  @State private var filter = LibraryFilter()
  @State private var isShowingFilterSheet = false
  @State private var selectedItemID: UUID?

  private var items: [Item] {
    filter.apply(to: allItems)
  }

  private var favoriteCount: Int {
    allItems.filter(\.isFavorite).count
  }

  var body: some View {
    NavigationStack {
      Group {
        if allItems.isEmpty {
          emptyLibrary
        } else if items.isEmpty {
          EmptyStateView(
            symbolName: "line.3.horizontal.decrease.circle",
            title: "条件に合う記事がありません",
            message: "絞り込み条件を変えるか, 条件をクリアしてください.",
            actionTitle: "条件をクリア",
            action: {
              withAnimation(ElasticMotion.jellyPop) {
                filter.reset()
              }
            }
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          content
        }
      }
      .background(WashiBackground())
      .navigationTitle("ライブラリ")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $filter.searchText, prompt: "タイトル・本文・要約・メモから探す")
      .toolbar { toolbarContent }
      .sheet(isPresented: $isShowingFilterSheet) {
        FilterSheet(filter: filter)
      }
      .navigationDestination(for: Item.self) { item in
        ItemDetailView(item: item)
      }
      .refreshable {
        await ingest.drainSharedQueue()
      }
    }
  }

  // MARK: - 本体

  @ViewBuilder
  private var content: some View {
    ScrollView {
      LazyVStack(spacing: Spacing.lg) {
        filterChips

        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          JellyRubberCard(appearIndex: min(index, 6), dragMode: .horizontalScrollSafe) {
            NavigationLink(value: item) {
              Group {
                switch filter.layout {
                case .card:
                  ItemCardView(item: item, isProcessing: ingest.inFlightItemIDs.contains(item.id))
                case .list:
                  ItemRowView(item: item, isProcessing: ingest.inFlightItemIDs.contains(item.id))
                    .paperPanel(padding: Spacing.md)
                }
              }
            }
            .buttonStyle(SquishyPillButtonStyle(pressScaleX: 1.02, pressScaleY: 0.98))
          }
          .contextMenu { contextMenu(for: item) }
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
              delete(item)
            } label: {
              Label("削除", systemImage: "trash")
            }
          }
        }
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.md)
    }
  }

  private var filterChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Spacing.sm) {
        chip(
          title: "絞り込み" + (filter.activeCount > 0 ? "（\(filter.activeCount)）" : ""),
          symbolName: "line.3.horizontal.decrease",
          isOn: filter.isActive
        ) {
          isShowingFilterSheet = true
        }

        chip(title: "未読", symbolName: "circle", isOn: filter.readState == .unread) {
          filter.readState = filter.readState == .unread ? .all : .unread
        }

        chip(
          title: "お気に入り",
          symbolName: "star",
          badgeCount: favoriteCount > 0 ? favoriteCount : nil,
          isOn: filter.favoritesOnly
        ) {
          filter.favoritesOnly.toggle()
        }

        chip(title: "要注意", symbolName: "exclamationmark.triangle", isOn: hasCautionFilter) {
          toggleCautionFilter()
        }

        chip(title: "古い情報", symbolName: "clock.badge.exclamationmark", isOn: hasStaleFilter) {
          toggleStaleFilter()
        }
      }
      .padding(.horizontal, 2)
      .padding(.vertical, Spacing.xs)
    }
  }

  /// 絞り込みの札. 木札を並べたような四角い形にし, スクイッシュ押下を加える.
  private func chip(
    title: String,
    symbolName: String,
    badgeCount: Int? = nil,
    isOn: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      withAnimation(ElasticMotion.jellyPop) {
        action()
      }
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: symbolName)
          .font(.caption2)
        Text(title)
          .font(.caption)
        if let badgeCount {
          Text("\(badgeCount)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .contentTransition(.numericText())
            .opacity(0.85)
        }
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .foregroundStyle(isOn ? Palette.paper : Palette.ink)
      .background {
        if isOn {
          RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
            .fill(Palette.indigo)
        } else {
          PaperSurface(cornerRadius: Radius.chip, isRaised: false)
        }
      }
    }
    .buttonStyle(SquishyPillButtonStyle(pressScaleX: 1.07, pressScaleY: 0.90))
    .sensoryFeedback(.selection, trigger: isOn)
    .accessibilityAddTraits(isOn ? [.isSelected] : [])
  }

  private var emptyLibrary: some View {
    EmptyStateView(
      symbolName: "square.and.arrow.down",
      title: "まだ一本も紡いでいません",
      message: "Safari の共有シートから「Tsumugi」を選ぶと記事を保存できます. URL を直接貼り付けても保存できます.",
      actionTitle: "URL から保存",
      action: { overlay?.isShowingAddURLSheet = true }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Menu {
        Picker("表示形式", selection: $filter.layout) {
          Label("カード", systemImage: LibraryLayout.card.symbolName).tag(LibraryLayout.card)
          Label("リスト", systemImage: LibraryLayout.list.symbolName).tag(LibraryLayout.list)
        }
        Divider()
        Picker("並び順", selection: $filter.sort) {
          ForEach(LibrarySort.allCases) { sort in
            Label(sort.displayName, systemImage: sort.symbolName).tag(sort)
          }
        }
        Toggle("昇順", isOn: $filter.isAscending)
      } label: {
        Label("表示", systemImage: "arrow.up.arrow.down.circle")
      }
      // 藍は主操作（URL から保存）だけに残し, 表示切替は墨にする.
      .tint(Palette.ink)
    }

    ToolbarItem(placement: .topBarTrailing) {
      Button {
        overlay?.isShowingAddURLSheet = true
      } label: {
        Label("URL から保存", systemImage: "plus")
      }
    }
  }

  @ViewBuilder
  private func contextMenu(for item: Item) -> some View {
    Button {
      item.isRead.toggle()
      try? modelContext.save()
      overlay?.showToast(
        item.isRead ? "既読にしました" : "未読にしました",
        icon: item.isRead ? "checkmark.circle.fill" : "circle"
      )
    } label: {
      Label(item.isRead ? "未読にする" : "既読にする", systemImage: item.isRead ? "circle" : "checkmark.circle")
    }

    Button {
      item.isFavorite.toggle()
      try? modelContext.save()
      overlay?.showToast(
        item.isFavorite ? "お気に入りに追加しました" : "お気に入りから外しました",
        icon: item.isFavorite ? "bookmark.fill" : "bookmark"
      )
    } label: {
      Label(item.isFavorite ? "お気に入りから外す" : "お気に入りに追加", systemImage: item.isFavorite ? "star.slash" : "star")
    }

    if let url = URL(string: item.canonicalURL) {
      ShareLink(item: url) {
        Label("原文リンクを共有", systemImage: "square.and.arrow.up")
      }
    }

    Divider()

    Button(role: .destructive) {
      delete(item)
    } label: {
      Label("削除", systemImage: "trash")
    }
  }

  // MARK: - 操作

  private var hasCautionFilter: Bool {
    filter.credibilityBands.contains(.caution) || filter.credibilityBands.contains(.doubtful) || filter.credibilityBands.contains(.low)
  }

  private func toggleCautionFilter() {
    let cautionSet: Set<CredibilityBand> = [.caution, .doubtful, .low]
    if hasCautionFilter {
      filter.credibilityBands.subtract(cautionSet)
    } else {
      filter.credibilityBands.formUnion(cautionSet)
    }
  }

  private var hasStaleFilter: Bool {
    filter.stalenessLabels.contains(.stale) || filter.stalenessLabels.contains(.obsolete)
  }

  private func toggleStaleFilter() {
    let staleSet: Set<StalenessLabel> = [.stale, .obsolete]
    if hasStaleFilter {
      filter.stalenessLabels.subtract(staleSet)
    } else {
      filter.stalenessLabels.formUnion(staleSet)
    }
  }

  private func delete(_ item: Item) {
    withAnimation(ElasticMotion.liquidClose) {
      modelContext.delete(item)
      try? modelContext.save()
    }
    overlay?.showToast("記事を削除しました", icon: "trash")
  }
}
