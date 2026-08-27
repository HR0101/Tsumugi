//
//  SharedPayload.swift
//  Tsumugi / ShareExtension 共通
//
//  仕様書 SE-02 / 8.2: 共有シートから受け取る内容を表す DTO.
//

import Foundation

/// Share Extension が受け取り, 本体アプリへ引き渡す 1 件分のペイロード.
///
/// 仕様書 8.2 の `POST /v1/items` リクエスト本文と同じ構造を持たせ,
/// 将来サーバ同期を有効にしたときにそのまま送信できるようにしている.
struct SharedPayload: Codable, Identifiable, Sendable {

  /// ページ本体の情報（JavaScript Preprocessing の戻り値に対応）.
  struct Page: Codable, Sendable {
    var title: String?
    /// `document.documentElement.outerHTML`. 仕様書 SE-04 により 2MB で切り詰め済み.
    var html: String?
    /// `og:*` などの meta タグ. キーは `property` または `name` 属性.
    var meta: [String: String]
    /// 共有時に選択されていたテキスト（仕様書 SE-03）.
    var selection: String?

    init(title: String? = nil, html: String? = nil, meta: [String: String] = [:], selection: String? = nil) {
      self.title = title
      self.html = html
      self.meta = meta
      self.selection = selection
    }
  }

  /// 端末側で採番する ID. 本体アプリの `Item.id` にそのまま引き継ぐ.
  var id: UUID
  var url: String
  var sharedAt: Date
  /// 共有元アプリのバンドル ID.
  var sourceApp: String?
  var page: Page
  var userTags: [String]
  var userNote: String

  private enum CodingKeys: String, CodingKey {
    case id = "client_item_id"
    case url
    case sharedAt = "shared_at"
    case sourceApp = "source_app"
    case page
    case userTags = "user_tags"
    case userNote = "user_note"
  }

  init(
    id: UUID = UUID(),
    url: String,
    sharedAt: Date = .now,
    sourceApp: String? = nil,
    page: Page = Page(),
    userTags: [String] = [],
    userNote: String = ""
  ) {
    self.id = id
    self.url = url
    self.sharedAt = sharedAt
    self.sourceApp = sourceApp
    self.page = page
    self.userTags = userTags
    self.userNote = userNote
  }

  /// JavaScript Preprocessing の結果辞書からペイロードを組み立てる.
  init?(javaScriptResults results: [String: Any], sourceApp: String? = nil) {
    guard let url = results["url"] as? String, !url.isEmpty else { return nil }
    let meta = (results["meta"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
    self.init(
      url: url,
      sourceApp: sourceApp,
      page: Page(
        title: results["title"] as? String,
        html: results["html"] as? String,
        meta: meta,
        selection: (results["selection"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    )
  }

  /// 表示用のタイトル. 取得できていなければホスト名を使う.
  var displayTitle: String {
    if let title = page.meta["og:title"], !title.isEmpty { return title }
    if let title = page.title, !title.isEmpty { return title }
    return URL(string: url)?.host() ?? url
  }

  /// サムネイル候補の URL.
  var heroImageURL: String? {
    page.meta["og:image"] ?? page.meta["twitter:image"]
  }
}
