//
//  TsumugiApp.swift
//  Tsumugi
//

import SwiftUI
import SwiftData

@main
struct TsumugiApp: App {

  /// SwiftData のコンテナ. 仕様書 7.3 のモデル群を登録する.
  private let modelContainer: ModelContainer = {
    let schema = Schema([
      Item.self,
      Tag.self,
      Highlight.self,
      Summary.self,
      CredibilityReport.self,
      FreshnessReport.self,
      AnalysisFeedback.self
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    do {
      return try ModelContainer(for: schema, configurations: [configuration])
    } catch {
      fatalError("SwiftData のコンテナを作成できませんでした: \(error)")
    }
  }()

  @State private var settings = SettingsStore()

  init() {
    // ナビゲーションバー・タブバーを和の配色と明朝体にそろえる.
    WaAppearance.apply()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(settings)
        .tint(Palette.indigo)
    }
    .modelContainer(modelContainer)
  }
}
