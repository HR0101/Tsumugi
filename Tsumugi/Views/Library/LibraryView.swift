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

  /// SwiftData から全件取得し, 絞り込みはメモリ上で行う.
  /// フィルタ条件が動的に変わるため, 述語をその都度作り直すより単純で速い.
  @Query(sort: \Item.savedAt, order: .reverse) private var allItems: [Item]

  @State private var filter = LibraryFilter()
  @State private var isShowingFilterSheet = false
  @State private var isShowingAddSheet = false
  @State private var selectedItemID: UUID?
  @State private var duplicateItemTitle: String?

  private var items: [Item] {
    filter.apply(to: allItems)
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
            action: { filter.reset() }
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          content
        }
      }
      .background(Palette.canvas)
      .navigationTitle("ライブラリ")
      .searchable(text: $filter.searchText, prompt: "タイトル・本文・要約・メモから検索")
      .toolbar { toolbarContent }
      .sheet(isPresented: $isShowingFilterSheet) {
        FilterSheet(filter: filter)
      }
      .sheet(isPresented: $isShowingAddSheet) {
        AddByURLSheet { urlString in
          await save(urlString: urlString)
        }
      }
      .navigationDestination(for: Item.self) { item in
        ItemDetailView(item: item)
      }
      .refreshable {
        await ingest.drainSharedQueue()
      }
      .alert(
        "すでに保存済みです",
        isPresented: Binding(
          get: { duplicateItemTitle != nil },
          set: { if !$0 { duplicateItemTitle = nil } }
        )
      ) {
        Button("OK", role: .cancel) { duplicateItemTitle = nil }
      } message: {
        Text(duplicateItemTitle ?? "")
      }
    }
  }

  // MARK: - 本体

  @ViewBuilder
  private var content: some View {
    ScrollView {
      LazyVStack(spacing: Spacing.md) {
        filterChips

        ForEach(items) { item in
          NavigationLink(value: item) {
            Group {
              switch filter.layout {
              case .card:
                ItemCardView(item: item, isProcessing: ingest.inFlightItemIDs.contains(item.id))
              case .list:
                ItemRowView(item: item, isProcessing: ingest.inFlightItemIDs.contains(item.id))
                  .cardSurface(padding: Spacing.md)
              }
            }
          }
          .buttonStyle(.plain)
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

        chip(title: "お気に入り", symbolName: "star", isOn: filter.favoritesOnly) {
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
    }
  }

  private func chip(title: String, symbolName: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: symbolName)
          .font(.caption)
        Text(title)
          .font(.caption.weight(.medium))
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(
        isOn ? Color.accentColor.opacity(0.16) : Palette.cardBackground,
        in: Capsule()
      )
      .foregroundStyle(isOn ? Color.accentColor : Color.primary)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? [.isSelected] : [])
  }

  private var emptyLibrary: some View {
    EmptyStateView(
      symbolName: "square.and.arrow.down",
      title: "まだ記事がありません",
      message: "Safari の共有シートから「Tsumugi」を選ぶと記事を保存できます. URL を直接貼り付けて保存することもできます.",
      actionTitle: "URL から保存",
      action: { isShowingAddSheet = true }
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
    }

    ToolbarItem(placement: .topBarTrailing) {
      Button {
        isShowingAddSheet = true
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
    } label: {
      Label(item.isRead ? "未読にする" : "既読にする", systemImage: item.isRead ? "circle" : "checkmark.circle")
    }

    Button {
      item.isFavorite.toggle()
      try? modelContext.save()
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
    withAnimation {
      modelContext.delete(item)
      try? modelContext.save()
    }
  }

  private func save(urlString: String) async {
    let result = await ingest.ingestURL(urlString)
    switch result {
    case .duplicate(let id):
      duplicateItemTitle = allItems.first { $0.id == id }?.title ?? "同じ URL の記事がすでに保存されています."
    case .invalidURL:
      duplicateItemTitle = nil
    case .saved:
      break
    }
  }
}

/// URL を直接入力して保存するシート.
struct AddByURLSheet: View {
  let onSave: (String) async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var urlString = ""
  @State private var isSaving = false

  private var isValid: Bool {
    guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
    return url.scheme?.hasPrefix("http") == true && url.host() != nil
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("https://example.com/article", text: $urlString, axis: .vertical)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .lineLimit(1...4)
        } header: {
          Text("記事の URL")
        } footer: {
          Text("保存後に本文を取得し, 要約を生成します. 共有シートから保存した場合と違い, 表示中のページの DOM は使えないため, ペイウォールのある記事は本文を取得できないことがあります.")
        }
      }
      .navigationTitle("URL から保存")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            Task {
              isSaving = true
              await onSave(urlString.trimmingCharacters(in: .whitespacesAndNewlines))
              isSaving = false
              dismiss()
            }
          }
          .disabled(!isValid || isSaving)
        }
      }
      .overlay {
        if isSaving {
          ProgressView("保存しています…")
            .padding(Spacing.xl)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
        }
      }
    }
  }
}
