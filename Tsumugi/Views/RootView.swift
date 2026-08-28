//
//  RootView.swift
//  Tsumugi
//
//  アプリのルート. タブでライブラリ・検索・ダイジェスト・設定を切り替える.
//  仕様書 3.1: 起動・復帰時に App Group の共有キューを取り込む.
//

import SwiftUI
import SwiftData

struct RootView: View {

  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(SettingsStore.self) private var settings

  @State private var ingest: IngestService?
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
      } else {
        ProgressView()
      }
    }
    .task {
      // ModelContext が確定してからサービスを組み立てる.
      if ingest == nil {
        ingest = IngestService(modelContext: modelContext, settings: settings)
      }
      isShowingOnboarding = !settings.hasCompletedOnboarding
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
