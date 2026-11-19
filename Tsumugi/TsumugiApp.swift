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
    #if DEBUG
    let isDesignPreview = ProcessInfo.processInfo.arguments.contains("--design-preview")
    #else
    let isDesignPreview = false
    #endif
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isDesignPreview)
    do {
      let container = try ModelContainer(for: schema, configurations: [configuration])
      #if DEBUG
      if isDesignPreview {
        let samples: [(String, String, String, Int, Int)] = [
          ("生成AIの推論コストはどこまで下がったのか", "技術研究所", "主要モデルの公開価格を比較すると、推論コストは短期間で大きく低下しました。導入を検討する際は、価格だけでなく精度と運用負荷も確認する必要があります。", 82, 91),
          ("医療機関における生成AI利用の新しい指針", "政策研究室", "医療現場での利用範囲と、患者情報を扱う際の確認事項を整理した指針が公表されました。現場では更新日と一次資料を確かめることが重要です。", 72, 87),
          ("知らないと損をするAIツールの真実", "まとめニュース", "注目を集める表現が多い一方、出典や比較条件は示されていません。主張を利用する前に原文の根拠を確認してください。", 38, 42)
        ]
        for (index, sample) in samples.enumerated() {
          let item = Item(originalURL: "https://example.com/preview/\(index)", canonicalURL: "https://example.com/preview/\(index)", urlHash: "design-preview-\(index)", title: sample.0)
          item.siteName = sample.1
          item.author = index == 0 ? "佐藤健一" : nil
          item.publishedAt = Calendar.current.date(byAdding: .day, value: -(index + 1) * 8, to: .now)
          item.readingMinutes = index + 3
          item.bodyText = String(repeating: sample.2 + "\n\n", count: 8)
          item.charCount = item.bodyText?.count ?? 0
          item.status = .completed
          let summary = Summary(tldr: sample.2, keyPoints: [sample.2], model: "preview", language: "ja")
          summary.item = item
          item.summary = summary
          let credibility = CredibilityReport(totalScore: sample.3, label: index == 2 ? "確認が必要" : "おおむね良好", sourceScore: sample.3, transparencyScore: sample.3, evidenceScore: sample.3, neutralityScore: sample.3, corroborationScore: sample.3, rationale: [], flags: [], confidence: .medium, model: "preview")
          credibility.item = item
          item.credibility = credibility
          let freshness = FreshnessReport(freshnessScore: sample.4, stalenessLabel: index == 2 ? .aging : .current, topicClass: .software, halfLifeDays: 180, elapsedDays: 8, decayedScore: sample.4, adjustments: [])
          freshness.item = item
          item.freshness = freshness
          container.mainContext.insert(item)
        }
        try container.mainContext.save()
      }
      #endif
      return container
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
