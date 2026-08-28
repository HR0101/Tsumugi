//
//  IngestPipelineTests.swift
//  TsumugiTests
//
//  仕様書 6.2 の取り込みパイプラインを, 共有ペイロードから永続化まで通しで検証する.
//  Extension が渡した DOM を使うため, ネットワークには接続しない（仕様書 EX-01）.
//

import Testing
import Foundation
import SwiftData
@testable import Tsumugi

@MainActor
@Suite("取り込みパイプライン（仕様書 6.2）")
struct IngestPipelineTests {

  /// メモリ上だけの SwiftData コンテナを用意する.
  private func makeContext() throws -> ModelContext {
    let schema = Schema([
      Item.self, Tag.self, Highlight.self,
      Summary.self, CredibilityReport.self, FreshnessReport.self, AnalysisFeedback.self
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
  }

  /// テスト用の設定. 常にオンデバイス診断を使い, 段階的診断は無効にして一度に全部走らせる.
  private func makeSettings() -> SettingsStore {
    let defaults = UserDefaults(suiteName: "TsumugiTests.\(UUID().uuidString)")!
    let settings = SettingsStore(defaults: defaults, keychain: KeychainStore(service: "jp.tsumugi.tests"))
    settings.providerMode = .onDeviceOnly
    settings.stagedAnalysisEnabled = false
    settings.notificationsEnabled = false
    // 通知の許可ダイアログでテストが止まらないよう, 週次ダイジェストも無効にする.
    settings.weeklyDigestEnabled = false
    return settings
  }

  private var sampleHTML: String {
    """
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <title>生成AIの推論コストは本当に下がったのか | Example Tech</title>
      <meta property="og:title" content="生成AIの推論コストは本当に下がったのか">
      <meta property="og:site_name" content="Example Tech">
      <meta property="article:published_time" content="2024-03-12T00:00:00Z">
      <meta name="author" content="山田太郎">
      <link rel="canonical" href="https://example.com/articles/ai-cost">
    </head>
    <body>
      <article>
        <h1>生成AIの推論コストは本当に下がったのか</h1>
        <p>生成AIの推論コストは、この一年でおおきく変化したと各所で報告されています。LLMを実運用に載せる企業が増えたためです。</p>
        <p>あるベンダーの価格表によると、推論コストは前年比で約80%低下したとされています。ただし、この数値の出所は単一のベンダーに限られます。</p>
        <p>現時点で最も安価なAPIは1000トークンあたり0.5円ですが、価格改定は頻繁に行われています。</p>
        <p>大規模言語モデルの選定では、レイテンシとコストのどちらを優先するかで構成が変わると解説されています。</p>
        <p>プロンプトの版管理と出力の監査ログの整備が、運用上の課題として繰り返し指摘されています。</p>
        <p>出典: <a href="https://www.mhlw.go.jp/report">公的機関のレポート</a></p>
      </article>
    </body>
    </html>
    """
  }

  private func makePayload(url: String = "https://example.com/articles/ai-cost?utm_source=twitter") -> SharedPayload {
    SharedPayload(
      url: url,
      page: SharedPayload.Page(
        title: "生成AIの推論コストは本当に下がったのか",
        html: sampleHTML,
        meta: ["og:title": "生成AIの推論コストは本当に下がったのか"],
        selection: nil
      ),
      userTags: ["調査"],
      userNote: "社内共有用"
    )
  }

  @Test("DOM 付きペイロードなら抽出・要約・信頼度・鮮度がすべて揃う")
  func fullPipelineWithDOM() async throws {
    let context = try makeContext()
    let settings = makeSettings()
    let service = IngestService(modelContext: context, settings: settings)

    // Share Extension のキュー経由と同じ形で取り込む.
    await service.ingest(makePayload())

    let items = try context.fetch(FetchDescriptor<Item>())
    let item = try #require(items.first)

    // 仕様書 16.2: トラッキングパラメータが落ちて canonical が採用される.
    #expect(item.canonicalURL == "https://example.com/articles/ai-cost")

    // 仕様書 EX-03: メタデータ.
    #expect(item.title == "生成AIの推論コストは本当に下がったのか")
    #expect(item.author == "山田太郎")
    #expect(item.siteName == "Example Tech")
    #expect(item.publishedAt != nil)
    #expect(item.readingMinutes >= 1)
    #expect(item.bodyText?.isEmpty == false)
    #expect(item.contentHash?.count == 64)

    // 仕様書 4.3: 要約.
    let summary = try #require(item.summary)
    #expect(!summary.tldr.isEmpty)
    #expect(summary.model == "heuristic-v1")

    // 仕様書 4.4: 信頼度.
    let credibility = try #require(item.credibility)
    #expect((0...100).contains(credibility.totalScore))
    #expect(credibility.rationale.count == CredibilityCategory.allCases.count)
    // オンデバイス診断では外部照合を行わないため, 判定なしとして記録される.
    #expect(credibility.rationale(for: .corroboration)?.isDetermined == false)

    // 仕様書 4.5: 鮮度.
    let freshness = try #require(item.freshness)
    #expect((0...100).contains(freshness.freshnessScore))
    #expect(freshness.elapsedDays != nil)

    // ユーザー入力のタグとメモが引き継がれる.
    #expect(item.tags.contains { $0.name == "調査" })
    #expect(item.userNote == "社内共有用")

    #expect(item.status == .completed)
    #expect(item.analyzedAt != nil)
  }

  @Test("同じ URL は重複として扱い, タグとメモだけ追記する（仕様書 3.2）")
  func duplicateDetection() async throws {
    let context = try makeContext()
    let service = IngestService(modelContext: context, settings: makeSettings())

    await service.ingest(makePayload())

    // トラッキングパラメータ違い・www 有無で同じ記事を指す URL.
    var second = makePayload(url: "https://www.example.com/articles/ai-cost/?fbclid=zzz")
    second.userTags = ["追記タグ"]
    second.userNote = "2 回目のメモ"
    let result = await service.ingest(second)

    let items = try context.fetch(FetchDescriptor<Item>())
    #expect(items.count == 1)
    if case .duplicate = result {} else { Issue.record("重複として判定されませんでした") }

    let item = try #require(items.first)
    #expect(item.tags.contains { $0.name == "追記タグ" })
    #expect(item.userNote.contains("2 回目のメモ"))
  }

  @Test("段階的診断が有効なら保存時は要約まで, 開いたときに詳細診断する（仕様書 12.2）")
  func stagedAnalysis() async throws {
    let context = try makeContext()
    let settings = makeSettings()
    settings.stagedAnalysisEnabled = true
    let service = IngestService(modelContext: context, settings: settings)

    await service.ingest(makePayload())

    let items = try context.fetch(FetchDescriptor<Item>())
    let item = try #require(items.first)
    #expect(item.summary != nil)
    #expect(item.credibility == nil)
    #expect(item.freshness == nil)
    #expect(item.status == .partial)

    // 詳細画面を開いたときと同じ処理.
    await service.runDeepAnalysisIfNeeded(for: item)

    #expect(item.credibility != nil)
    #expect(item.freshness != nil)
    #expect(item.status == .completed)
    #expect(settings.monthlyAnalysisCount == 1)
  }

  @Test("無料枠を超えたら詳細診断せず要約のみで機能を残す（仕様書 12.3）")
  func freeQuotaFallback() async throws {
    let context = try makeContext()
    let settings = makeSettings()
    settings.stagedAnalysisEnabled = true
    for _ in 0..<SettingsStore.freeMonthlyAnalysisLimit { settings.recordAnalysis() }
    #expect(settings.hasExceededFreeQuota)

    let service = IngestService(modelContext: context, settings: settings)
    await service.ingest(makePayload())

    let items = try context.fetch(FetchDescriptor<Item>())
    let item = try #require(items.first)
    await service.runDeepAnalysisIfNeeded(for: item)

    #expect(item.summary != nil)
    #expect(item.credibility == nil)
    #expect(item.failureReason?.contains("無料枠") == true)
  }

  @Test("未対応形式は unsupportedFormat として保存する（仕様書 3.2）")
  func unsupportedFormat() async throws {
    let context = try makeContext()
    let service = IngestService(modelContext: context, settings: makeSettings())

    await service.ingest(SharedPayload(url: "https://example.com/paper.pdf"))

    let items = try context.fetch(FetchDescriptor<Item>())
    let item = try #require(items.first)
    #expect(item.status == .unsupportedFormat)
    #expect(item.failureReason?.contains("PDF") == true)
  }

  @Test("鮮度の週次バッチは AI を呼ばずに再計算できる（仕様書 4.5.4）")
  func stalenessBatch() async throws {
    let context = try makeContext()
    let service = IngestService(modelContext: context, settings: makeSettings())
    await service.ingest(makePayload())

    let items = try context.fetch(FetchDescriptor<Item>())
    let item = try #require(items.first)
    let before = try #require(item.freshness).evaluatedAt

    _ = await service.refreshStalenessBatch()

    let after = try #require(item.freshness).evaluatedAt
    #expect(after >= before)
  }
}
