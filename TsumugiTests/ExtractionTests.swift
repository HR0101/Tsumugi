//
//  ExtractionTests.swift
//  TsumugiTests
//
//  仕様書 4.2（本文抽出）と 16.2 周辺の日付抽出を検証する.
//

import Testing
import Foundation
@testable import Tsumugi

@Suite("本文抽出（仕様書 4.2）")
struct ArticleExtractorTests {

  /// テスト用の記事 HTML.
  private var sampleHTML: String {
    """
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <title>2024年のAIトレンド総まとめ | Example Tech</title>
      <meta property="og:title" content="2024年のAIトレンド総まとめ">
      <meta property="og:site_name" content="Example Tech">
      <meta property="og:image" content="https://example.com/hero.png">
      <meta property="article:published_time" content="2024-03-12T00:00:00Z">
      <meta property="article:modified_time" content="2024-05-02T00:00:00Z">
      <meta name="author" content="山田太郎">
      <link rel="canonical" href="https://example.com/articles/ai-trend-2024">
      <script>var tracking = "これは本文ではない";</script>
      <style>body { color: red; }</style>
    </head>
    <body>
      <nav><a href="https://example.com/">ホーム</a></nav>
      <article>
        <h1>2024年のAIトレンド総まとめ</h1>
        <p>2024年のAI業界は推論コストの急落とオープンモデルの台頭が中心となり、実運用フェーズへの移行が進みました。</p>
        <p>推論コストは前年比で約80%低下したと、あるベンダーの価格表を根拠に報告されています。</p>
        <p>規制面ではEU AI Actの段階施行が始まり、事業者には対応が求められています。</p>
        <h2>オープンウェイトモデルの拡大</h2>
        <p>商用利用可能なオープンウェイトモデルが増え、自社環境での運用を選ぶ企業が増加しました。</p>
        <p>出典: <a href="https://www.mhlw.go.jp/report">公的機関のレポート</a> および <a href="https://example.org/blog">解説記事</a></p>
      </article>
      <footer><a href="https://example.com/about">運営者情報</a></footer>
    </body>
    </html>
    """
  }

  private func extractSample() -> ExtractedArticle {
    ArticleExtractor().parse(html: sampleHTML, url: "https://example.com/articles/ai-trend-2024?utm_source=x")
  }

  @Test("メタデータを抽出できる（仕様書 EX-03）")
  func metadataExtracted() {
    let article = extractSample()
    #expect(article.title == "2024年のAIトレンド総まとめ")
    #expect(article.author == "山田太郎")
    #expect(article.siteName == "Example Tech")
    #expect(article.language == "ja")
    #expect(article.heroImageURL == "https://example.com/hero.png")
    #expect(article.canonicalHint == "https://example.com/articles/ai-trend-2024")
  }

  @Test("発行日と更新日を優先順どおりに決定する（仕様書 EX-04）")
  func datesExtracted() {
    let article = extractSample()
    let calendar = Calendar(identifier: .gregorian)

    #expect(article.publishedAt != nil)
    #expect(article.updatedAt != nil)

    if let published = article.publishedAt {
      let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: published)
      #expect(components.year == 2024)
      #expect(components.month == 3)
      #expect(components.day == 12)
    }
    // 更新日は発行日より新しいので採用される.
    #expect((article.updatedAt ?? .distantPast) > (article.publishedAt ?? .distantFuture))
  }

  @Test("本文を抽出し, スクリプトとナビゲーションを除去する")
  func bodyExtracted() {
    let article = extractSample()
    #expect(article.isSuccessful)
    #expect(article.bodyText.contains("推論コストの急落"))
    #expect(article.bodyText.contains("EU AI Act"))
    #expect(!article.bodyText.contains("これは本文ではない"))
    #expect(!article.bodyText.contains("color: red"))
    #expect(article.charCount > 100)
    #expect(article.readingMinutes >= 1)
  }

  @Test("見出しを抽出できる")
  func headingsExtracted() {
    let article = extractSample()
    #expect(article.headings.contains("2024年のAIトレンド総まとめ"))
    #expect(article.headings.contains("オープンウェイトモデルの拡大"))
  }

  @Test("外部リンクと一次情報リンクを分類できる（仕様書 4.4.1 #3）")
  func linksClassified() {
    let article = extractSample()
    #expect(article.outboundLinks.count == 2)
    #expect(article.authoritativeLinkCount == 1)
    #expect(article.affiliateLinkCount == 0)
  }

  @Test("本文のハッシュが同一内容で一致する（仕様書 EX-06）")
  func contentHashStable() {
    let first = extractSample()
    let second = extractSample()
    #expect(first.contentHash == second.contentHash)
    #expect(first.contentHash.count == 64)
  }

  @Test("本文が短すぎる場合は抽出失敗として扱う（仕様書 EX-05）")
  func shortContentFails() {
    let article = ArticleExtractor().parse(
      html: "<html><body><p>短い</p></body></html>",
      url: "https://example.com/x"
    )
    #expect(!article.isSuccessful)
  }

  @Test("HTML エンティティをデコードする")
  func entitiesDecoded() {
    let article = ArticleExtractor().parse(
      html: """
      <html><body><article>
      <p>&quot;引用符&quot; と &amp; と &#x3042; と &#12356; を含む十分な長さの本文をここに書いておきます。</p>
      <p>もう一段落追加して, 抽出に必要な文字数を満たすようにします。日本語の本文として扱われます。</p>
      </article></body></html>
      """,
      url: "https://example.com/x"
    )
    #expect(article.bodyText.contains("\"引用符\""))
    #expect(article.bodyText.contains("&"))
    // 数値文字参照は 16 進・10 進の両方をデコードする（原文では「あ」と「い」の間に「と」が入る）.
    #expect(article.bodyText.contains("あ"))
    #expect(article.bodyText.contains("い"))
    #expect(!article.bodyText.contains("&#"))
  }

  @Test("noarchive 指定を検出する（仕様書 EX-07）")
  func noArchiveDetected() {
    let article = ArticleExtractor().parse(
      html: """
      <html><head><meta name="robots" content="noindex, noarchive"></head>
      <body><article><p>本文です。noarchive を指定したサイトの記事として扱われることを確認します。</p>
      <p>もう一段落追加して, 抽出に必要な文字数を満たすようにします。日本語の本文として扱われます。</p>
      </article></body></html>
      """,
      url: "https://example.com/x"
    )
    #expect(article.isNoArchive)
  }
}

@Suite("日付のパース（仕様書 EX-04）")
struct DateParsingTests {

  private func components(_ date: Date?) -> (year: Int, month: Int, day: Int)? {
    guard let date else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    return (year, month, day)
  }

  @Test("ISO 8601 をパースできる")
  func iso8601() {
    #expect(DateParsing.parse("2024-03-12T00:00:00Z") != nil)
    #expect(DateParsing.parse("2024-03-12T09:00:00+09:00") != nil)
    #expect(DateParsing.parse("2024-03-12") != nil)
  }

  @Test("日本語の日付表現をパースできる")
  func japaneseFormat() {
    let parsed = components(DateParsing.parse("2024年3月12日"))
    #expect(parsed?.year == 2024)
    #expect(parsed?.month == 3)
    #expect(parsed?.day == 12)
  }

  @Test("本文中の日付を拾える")
  func dateInText() {
    let parsed = components(DateParsing.firstDate(inText: "この記事は2024年3月12日に公開されました。"))
    #expect(parsed?.year == 2024)
    #expect(parsed?.month == 3)
    #expect(parsed?.day == 12)
  }

  @Test("URL パス中の日付を拾える")
  func dateInURLPath() {
    let parsed = components(DateParsing.dateFromURLPath("https://example.com/2024/03/12/article-title"))
    #expect(parsed?.year == 2024)
    #expect(parsed?.month == 3)
    #expect(parsed?.day == 12)
  }

  @Test("解釈できない文字列は nil を返す")
  func invalidReturnsNil() {
    #expect(DateParsing.parse("いつか") == nil)
    #expect(DateParsing.parse(nil) == nil)
    #expect(DateParsing.parse("") == nil)
  }

  @Test("日数差を計算できる")
  func daysBetween() {
    let from = Date(timeIntervalSince1970: 0)
    let to = Date(timeIntervalSince1970: 86_400 * 10)
    #expect(DateParsing.daysBetween(from, and: to) == 10)
  }
}
