//
//  RootView.swift
//  Tsumugi
//
//  アプリのルート. タブでライブラリ・検索・ダイジェスト・設定を切り替える.
//  仕様書 3.1: 起動・復帰時に App Group の共有キューを取り込む.
//

import SwiftUI
import SwiftData
import Observation

/// アプリ全体の弾性シート・トーストを管理するオーバーレイ状態.
@Observable
final class AppOverlayState {
  var isShowingAddURLSheet = false
  var draftURLText = ""
  var toastMessage: String?
  var toastIcon: String = "checkmark.circle.fill"
  var duplicateItemTitle: String?

  private var toastDismissTask: Task<Void, Never>?

  func showToast(
    _ message: String,
    icon: String = "checkmark.circle.fill",
    duration: Duration = .seconds(2.2)
  ) {
    toastDismissTask?.cancel()
    toastIcon = icon
    toastMessage = message
    toastDismissTask = Task { @MainActor in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      toastMessage = nil
    }
  }
}

struct RootView: View {

  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(SettingsStore.self) private var settings

  @State private var ingest: IngestService?
  @State private var overlay = AppOverlayState()
  @State private var selectedTab: Tab = .library
  @State private var isShowingOnboarding = false
  /// 通知やユニバーサルリンクから開く対象（仕様書 OT-03）.
  @State private var deepLinkItemID: UUID?

  enum Tab: String, Hashable {
    case library
    case search
    case digest
    case settings
  }

  var body: some View {
    Group {
      if let ingest {
        TabView(selection: $selectedTab) {
          LibraryView()
            .tabItem { Label("ライブラリ", systemImage: "books.vertical") }
            .tag(Tab.library)

          SearchView()
            .tabItem { Label("検索", systemImage: "magnifyingglass") }
            .tag(Tab.search)

          WeeklyDigestView()
            .tabItem { Label("ダイジェスト", systemImage: "chart.bar.doc.horizontal") }
            .tag(Tab.digest)

          SettingsView()
            .tabItem { Label("設定", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .environment(ingest)
        .environment(overlay)
      } else {
        ProgressView()
      }
    }
    .overlay {
      ElasticSheetOverlay(
        isPresented: $overlay.isShowingAddURLSheet,
        onScrimTap: {
          if overlay.draftURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            overlay.isShowingAddURLSheet = false
          } else {
            overlay.isShowingAddURLSheet = false
            overlay.showToast("下書きを保存しました", icon: "tray.and.arrow.down")
          }
        }
      ) {
        ElasticAddURLComposer(
          draftText: $overlay.draftURLText,
          onSave: { urlString in
            await saveURL(urlString)
          },
          onSaveDraft: { text in
            overlay.draftURLText = text
            overlay.isShowingAddURLSheet = false
            overlay.showToast("下書きを保存しました", icon: "tray.and.arrow.down")
          },
          onDiscard: {
            overlay.draftURLText = ""
            overlay.isShowingAddURLSheet = false
          }
        )
      }
    }
    .overlay(alignment: .top) {
      JellyToastPill(message: overlay.toastMessage, icon: overlay.toastIcon)
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
    .alert(
      "すでに保存済みです",
      isPresented: Binding(
        get: { overlay.duplicateItemTitle != nil },
        set: { if !$0 { overlay.duplicateItemTitle = nil } }
      )
    ) {
      Button("OK", role: .cancel) { overlay.duplicateItemTitle = nil }
    } message: {
      Text(overlay.duplicateItemTitle ?? "")
    }
    .task {
      // ModelContext が確定してからサービスを組み立てる.
      if ingest == nil {
        ingest = IngestService(modelContext: modelContext, settings: settings)
      }
      #if DEBUG
      let isDesignPreview = ProcessInfo.processInfo.arguments.contains("--design-preview")
      isShowingOnboarding = !isDesignPreview && !settings.hasCompletedOnboarding
      #else
      isShowingOnboarding = !settings.hasCompletedOnboarding
      #endif
      await ingest?.drainSharedQueue()
    }
    .onChange(of: scenePhase) { _, newPhase in
      // 共有シートから戻ってきたタイミングでキューを取り込む.
      guard newPhase == .active else { return }
      Task { await ingest?.drainSharedQueue() }
    }
    .sheet(isPresented: $isShowingOnboarding) {
      NavigationStack {
        OnboardingView()
      }
      .interactiveDismissDisabled()
    }
    .onOpenURL { url in
      handle(url: url)
    }
  }

  private func saveURL(_ urlString: String) async {
    guard let ingest else { return }
    let result = await ingest.ingestURL(urlString)
    switch result {
    case .saved:
      overlay.draftURLText = ""
      overlay.isShowingAddURLSheet = false
      overlay.showToast("記事を紡ぎました", icon: "checkmark.circle.fill")
    case .duplicate(let id):
      overlay.isShowingAddURLSheet = false
      var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
      descriptor.fetchLimit = 1
      let title = (try? modelContext.fetch(descriptor).first?.title) ?? "同じ URL の記事がすでに保存されています."
      overlay.duplicateItemTitle = title
    case .invalidURL:
      overlay.showToast("URL を読み取れませんでした", icon: "exclamationmark.triangle.fill")
    }
  }

  /// 仕様書 OT-03: `tsumugi://item/{id}` 形式のカスタム URL スキーム.
  private func handle(url: URL) {
    guard url.scheme == "tsumugi" else { return }
    switch url.host() {
    case "item":
      let idString = url.pathComponents.last ?? ""
      deepLinkItemID = UUID(uuidString: idString)
      selectedTab = .library
    case "digest":
      selectedTab = .digest
    default:
      selectedTab = .library
    }
  }
}
