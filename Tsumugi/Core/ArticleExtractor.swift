//
//  ArticleExtractor.swift
//  Tsumugi
//
//  仕様書 4.2: 本文抽出（Readability 相当のアルゴリズムをオンデバイスで実装）.
//
//  仕様書 EX-01 に従い, Share Extension が渡した DOM を第一候補とする.
//  DOM が無い場合のみ URL から fetch する（第二候補）.
//

import Foundation

/// 本文抽出の失敗理由.
enum ExtractionError: LocalizedError {
  case noContent
  case unsupportedFormat(String)
  case networkFailure(underlying: Error)
  case invalidURL

  var errorDescription: String? {
    switch self {
    case .noContent:
      return "本文を抽出できませんでした. 原文リンクのみを保存しています."
    case .unsupportedFormat(let format):
      return "\(format) は現在のバージョンでは未対応の形式です."
    case .networkFailure:
      return "ページを取得できませんでした. 通信環境をご確認ください."
    case .invalidURL:
      return "URL の形式が正しくありません."
    }
  }
}

/// HTML から本文とメタデータを取り出す.
///
/// 2MB の HTML に正規表現を掛けるため, メインスレッドを塞がないよう `Sendable` にして
/// アクターに閉じ込めない（プロジェクトの既定は `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`）.
struct ArticleExtractor: Sendable {

  // MARK: - 定数

  private enum Constant {
    /// 本文とみなすために必要な最低文字数.
    static let minimumBodyLength = 160
    /// 段落として採用する最低文字数.
    static let minimumParagraphLength = 24
    /// 日本語の平均読字速度（文字 / 分）.
    static let japaneseCharsPerMinute = 500.0
    /// 英語の平均読字速度（語 / 分）を文字数に換算した値.
    static let latinCharsPerMinute = 1_200.0
    /// サーバ fetch のタイムアウト（秒）.
    static let fetchTimeout: TimeInterval = 15
    /// fetch した HTML の上限（仕様書 SE-04 と同じ 2MB）.
    static let maxHTMLBytes = 2 * 1024 * 1024
  }

  /// アフィリエイトリンクと推定するホスト・パラメータ.
  private static let affiliateMarkers = [
    "amzn.to", "amazon.co.jp/dp", "amazon.com/dp", "tag=", "a8.net", "rakuten.co.jp/",
    "valuecommerce", "linksynergy", "moshimo", "af.moshimo", "accesstrade", "click.linksynergy"
  ]

  /// 一次情報・公的機関・学術のドメイン特徴.
  private static let authoritativeMarkers = [
    ".go.jp", ".gov", ".ac.jp", ".edu", "doi.org", "arxiv.org", "pubmed", "nih.gov",
    "who.int", "oecd.org", "e-gov.go.jp", "jstage.jst.go.jp", "nature.com", "science.org"
  ]

  /// v1.0 で未対応の拡張子（仕様書 3.2）.
  private static let unsupportedExtensions = ["pdf", "mp4", "mov", "mp3", "m4a", "zip"]

  private let urlSession: URLSession

  init(urlSession: URLSession = .shared) {
    self.urlSession = urlSession
  }

  // MARK: - 公開 API

  /// 共有ペイロードから記事を抽出する.
  ///
  /// - Throws: `ExtractionError`.
  func extract(from payload: SharedPayload) async throws -> ExtractedArticle {
    if let unsupported = unsupportedFormatName(for: payload.url) {
      throw ExtractionError.unsupportedFormat(unsupported)
    }

    // 仕様書 EX-01: Extension が取得した DOM を第一候補とする.
    if let html = payload.page.html, html.count > Constant.minimumBodyLength {
      let article = parse(html: html, url: payload.url, fallbackTitle: payload.page.title, meta: payload.page.meta)
      if article.isSuccessful { return article }
    }

    // 第二候補: URL から取得する.
    let fetched = try await fetchHTML(from: payload.url)
    let article = parse(html: fetched, url: payload.url, fallbackTitle: payload.page.title, meta: payload.page.meta)
    guard article.isSuccessful else { throw ExtractionError.noContent }
    return article
  }

  /// HTML 文字列から記事を組み立てる. テストから直接呼べるよう分離している.
  func parse(html: String, url: String, fallbackTitle: String? = nil, meta providedMeta: [String: String] = [:]) -> ExtractedArticle {
    // JS の preprocessing が渡した meta を優先し, 不足分を HTML から補う.
    var meta = parseMetaTags(from: html)
    for (key, value) in providedMeta where !value.isEmpty {
      meta[key.lowercased()] = value
    }

    let cleaned = HTMLText.removingNoiseElements(from: html)
    let bodyRegion = selectContentRegion(in: cleaned)
    let blocks = extractBlocks(from: bodyRegion)
    let bodyText = HTMLText.normalizingWhitespace(blocks.paragraphs.joined(separator: "\n\n"))

    let title = resolveTitle(meta: meta, html: html, fallback: fallbackTitle, url: url)
    let published = resolvePublishedDate(meta: meta, html: cleaned, bodyText: bodyText, url: url)
    let updated = resolveUpdatedDate(meta: meta, html: cleaned, publishedAt: published)
    let charCount = bodyText.count
    let language = meta["og:locale"] ?? HTMLText.firstMatch(in: html, pattern: "<html[^>]*\\blang=[\"']([^\"']+)[\"']")

    return ExtractedArticle(
      title: title,
      author: resolveAuthor(meta: meta, html: cleaned),
      publishedAt: published,
      updatedAt: updated,
      siteName: meta["og:site_name"] ?? URL(string: url)?.host(),
      language: language.map { String($0.prefix(2)).lowercased() },
      heroImageURL: meta["og:image"] ?? meta["twitter:image"],
      canonicalHint: HTMLText.firstMatch(
        in: html,
        pattern: "<link[^>]*rel=[\"']canonical[\"'][^>]*href=[\"']([^\"']+)[\"']"
      ) ?? HTMLText.firstMatch(
        in: html,
        pattern: "<link[^>]*href=[\"']([^\"']+)[\"'][^>]*rel=[\"']canonical[\"']"
      ),
      bodyText: bodyText,
      headings: blocks.headings,
      charCount: charCount,
      readingMinutes: estimateReadingMinutes(text: bodyText),
      contentHash: URLNormalizer.sha256(bodyText),
      links: extractLinks(from: cleaned, articleURL: url),
      isNoArchive: (meta["robots"] ?? "").lowercased().contains("noarchive"),
      isSuccessful: charCount >= Constant.minimumBodyLength
    )
  }

  /// 本文抽出に失敗した記事でも最低限のメタ情報を返す（仕様書 EX-05）.
  func minimalArticle(for payload: SharedPayload) -> ExtractedArticle {
    let meta = payload.page.meta.reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
    return ExtractedArticle(
      title: payload.displayTitle,
      author: meta["author"] ?? meta["article:author"],
      publishedAt: DateParsing.parse(meta["article:published_time"]) ?? DateParsing.dateFromURLPath(payload.url),
      updatedAt: DateParsing.parse(meta["article:modified_time"]),
      siteName: meta["og:site_name"] ?? URL(string: payload.url)?.host(),
      language: nil,
      heroImageURL: payload.heroImageURL,
      canonicalHint: nil,
      bodyText: "",
      headings: [],
      charCount: 0,
      readingMinutes: 0,
      contentHash: URLNormalizer.sha256(payload.url),
      links: [],
      isNoArchive: false,
      isSuccessful: false
    )
  }

  // MARK: - 本文領域の選択

  /// 本文が含まれる可能性が最も高い領域を選ぶ.
  /// `<article>` → `<main>` → `[role=main]` → `<body>` の順に候補を評価し,
  /// テキスト量が最も多いものを採用する（Readability の密度評価を簡略化したもの）.
  private func selectContentRegion(in html: String) -> String {
    let candidatePatterns = [
      "<article\\b[^>]*>(.*?)</article>",
      "<main\\b[^>]*>(.*?)</main>",
      "<div[^>]*\\brole=[\"']main[\"'][^>]*>(.*?)</div>",
      "<div[^>]*\\bclass=[\"'][^\"']*(?:article-body|post-content|entry-content|content-body)[^\"']*[\"'][^>]*>(.*?)</div>"
    ]

    var best = ""
    var bestLength = 0
    for pattern in candidatePatterns {
      for capture in HTMLText.matches(in: html, pattern: pattern, groups: [1]) {
        guard let candidate = capture.first else { continue }
        let length = HTMLText.strippingTags(candidate).count
        if length > bestLength {
          best = candidate
          bestLength = length
        }
      }
    }

    if bestLength >= Constant.minimumBodyLength { return best }

    // 候補が見つからなければ body 全体からナビゲーション類を除いて使う.
    let body = HTMLText.firstMatch(in: html, pattern: "<body\\b[^>]*>(.*?)</body>") ?? html
    return HTMLText.removingChromeElements(from: body)
  }

  /// ブロック要素を順序どおりに取り出す.
  private func extractBlocks(from html: String) -> (paragraphs: [String], headings: [String]) {
    let pattern = "<(p|h1|h2|h3|h4|h5|h6|li|blockquote|pre|dd)\\b[^>]*>(.*?)</\\1>"
    var paragraphs: [String] = []
    var headings: [String] = []
    var seen = Set<String>()

    for capture in HTMLText.matches(in: html, pattern: pattern, groups: [1, 2]) {
      let tag = capture[0].lowercased()
      let text = HTMLText.normalizingWhitespace(HTMLText.strippingTags(capture[1]))
      guard !text.isEmpty else { continue }

      let isHeading = tag.hasPrefix("h") && tag.count == 2
      if isHeading {
        headings.append(text)
        // 見出しは本文にも Markdown 風の印を付けて残す.
        let level = String(repeating: "#", count: min(Int(tag.dropFirst()) ?? 2, 6))
        paragraphs.append("\(level) \(text)")
        continue
      }

      guard text.count >= Constant.minimumParagraphLength else { continue }
      // 同じ文言の重複（サイドバーの再掲など）を落とす.
      guard seen.insert(text).inserted else { continue }
      paragraphs.append(tag == "li" ? "・\(text)" : text)
    }

    if paragraphs.isEmpty {
      // ブロック要素が取れないページ向けのフォールバック.
      let flattened = HTMLText.normalizingWhitespace(HTMLText.strippingTags(html))
      if flattened.count >= Constant.minimumBodyLength { paragraphs = [flattened] }
    }

    return (paragraphs, headings)
  }

  // MARK: - メタデータの解決

  private func parseMetaTags(from html: String) -> [String: String] {
    var meta: [String: String] = [:]
    let patterns = [
      "<meta[^>]*(?:property|name)=[\"']([^\"']+)[\"'][^>]*content=[\"']([^\"']*)[\"']",
      "<meta[^>]*content=[\"']([^\"']*)[\"'][^>]*(?:property|name)=[\"']([^\"']+)[\"']"
    ]
    for (index, pattern) in patterns.enumerated() {
      for capture in HTMLText.matches(in: html, pattern: pattern, groups: [1, 2]) {
        let key = (index == 0 ? capture[0] : capture[1]).lowercased()
        let value = HTMLText.decodingEntities(index == 0 ? capture[1] : capture[0])
        guard !key.isEmpty, !value.isEmpty, meta[key] == nil else { continue }
        meta[key] = value
      }
    }
    return meta
  }

  private func resolveTitle(meta: [String: String], html: String, fallback: String?, url: String) -> String {
    let candidates = [
      meta["og:title"],
      meta["twitter:title"],
      fallback,
      HTMLText.firstMatch(in: html, pattern: "<title[^>]*>(.*?)</title>").map { HTMLText.strippingTags($0) },
      HTMLText.firstMatch(in: html, pattern: "<h1\\b[^>]*>(.*?)</h1>").map { HTMLText.strippingTags($0) }
    ]
    for candidate in candidates {
      guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
      return HTMLText.decodingEntities(value)
    }
    return URL(string: url)?.host() ?? url
  }

  private func resolveAuthor(meta: [String: String], html: String) -> String? {
    let candidates = [
      meta["article:author"],
      meta["author"],
      meta["twitter:creator"],
      HTMLText.firstMatch(in: html, pattern: "\"author\"\\s*:\\s*\\{[^}]*\"name\"\\s*:\\s*\"([^\"]+)\""),
      HTMLText.firstMatch(in: html, pattern: "\"author\"\\s*:\\s*\"([^\"]+)\""),
      HTMLText.firstMatch(in: html, pattern: "<[^>]*\\brel=[\"']author[\"'][^>]*>(.*?)</a>").map { HTMLText.strippingTags($0) }
    ]
    for candidate in candidates {
      guard var value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
      // URL がそのまま入っている場合は著者名として扱わない.
      if value.hasPrefix("http") { continue }
      value = HTMLText.decodingEntities(value)
      return value.count > 60 ? String(value.prefix(60)) : value
    }
    return nil
  }

  /// 仕様書 EX-04 の優先順で発行日を決定する.
  private func resolvePublishedDate(meta: [String: String], html: String, bodyText: String, url: String) -> Date? {
    if let date = DateParsing.parse(meta["article:published_time"]) { return date }
    if let date = DateParsing.parse(meta["datepublished"]) { return date }
    if let raw = HTMLText.firstMatch(in: html, pattern: "\"datePublished\"\\s*:\\s*\"([^\"]+)\""),
       let date = DateParsing.parse(raw) { return date }
    if let raw = HTMLText.firstMatch(in: html, pattern: "<time[^>]*\\bdatetime=[\"']([^\"']+)[\"']"),
       let date = DateParsing.parse(raw) { return date }
    if let date = DateParsing.firstDate(inText: String(bodyText.prefix(400))) { return date }
    return DateParsing.dateFromURLPath(url)
  }

  private func resolveUpdatedDate(meta: [String: String], html: String, publishedAt: Date?) -> Date? {
    let candidates = [
      DateParsing.parse(meta["article:modified_time"]),
      DateParsing.parse(meta["datemodified"]),
      HTMLText.firstMatch(in: html, pattern: "\"dateModified\"\\s*:\\s*\"([^\"]+)\"").flatMap { DateParsing.parse($0) }
    ]
    guard let updated = candidates.compactMap({ $0 }).max() else { return nil }
    // 発行日と同じ, または古い更新日は「更新履歴あり」とみなさない.
    if let publishedAt, updated <= publishedAt { return nil }
    return updated
  }

  // MARK: - リンク解析

  private func extractLinks(from html: String, articleURL: String) -> [ExtractedArticle.Link] {
    let host = URL(string: articleURL)?.host()?.lowercased() ?? ""
    var links: [ExtractedArticle.Link] = []
    var seen = Set<String>()

    for capture in HTMLText.matches(in: html, pattern: "<a\\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", groups: [1, 2]) {
      let href = capture[0]
      guard href.hasPrefix("http"), seen.insert(href).inserted else { continue }
      let lowered = href.lowercased()
      let linkHost = URL(string: href)?.host()?.lowercased() ?? ""
      links.append(
        ExtractedArticle.Link(
          url: href,
          text: HTMLText.normalizingWhitespace(HTMLText.strippingTags(capture[1])),
          isExternal: !linkHost.isEmpty && linkHost != host,
          isAffiliate: Self.affiliateMarkers.contains { lowered.contains($0) },
          isAuthoritative: Self.authoritativeMarkers.contains { lowered.contains($0) }
        )
      )
    }
    return links
  }

  // MARK: - その他

  /// 推定読了時間（分）を返す. 仕様書 EX-03.
  private func estimateReadingMinutes(text: String) -> Int {
    guard !text.isEmpty else { return 0 }
    // CJK 文字とラテン文字で読字速度が異なるため, 文字種ごとに時間を積算する.
    var cjkCount = 0
    var latinCount = 0
    for scalar in text.unicodeScalars {
      if (0x3000...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value) {
        cjkCount += 1
      } else {
        latinCount += 1
      }
    }
    let minutes = Double(cjkCount) / Constant.japaneseCharsPerMinute
      + Double(latinCount) / Constant.latinCharsPerMinute
    return max(1, Int(minutes.rounded()))
  }

  private func unsupportedFormatName(for url: String) -> String? {
    guard let path = URL(string: url)?.path.lowercased() else { return nil }
    for ext in Self.unsupportedExtensions where path.hasSuffix(".\(ext)") {
      return ext.uppercased()
    }
    return nil
  }

  /// URL から HTML を取得する（第二候補. 仕様書 EX-01）.
  private func fetchHTML(from urlString: String) async throws -> String {
    guard let url = URL(string: urlString) else { throw ExtractionError.invalidURL }

    var request = URLRequest(url: url)
    request.timeoutInterval = Constant.fetchTimeout
    // 一般的なブラウザとして振る舞い, モバイル向け簡易ページを避ける.
    request.setValue(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await urlSession.data(for: request)
      if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
        throw ExtractionError.noContent
      }
      let truncated = data.count > Constant.maxHTMLBytes ? data.prefix(Constant.maxHTMLBytes) : data.prefix(data.count)
      guard let html = String(data: Data(truncated), encoding: .utf8)
        ?? String(data: Data(truncated), encoding: .shiftJIS)
        ?? String(data: Data(truncated), encoding: .japaneseEUC) else {
        throw ExtractionError.noContent
      }
      return html
    } catch let error as ExtractionError {
      throw error
    } catch {
      throw ExtractionError.networkFailure(underlying: error)
    }
  }
}
