//
//  Item.swift
//  Tsumugi
//
//  仕様書 7.3: クライアント側モデル（SwiftData）.
//

import Foundation
import SwiftData

/// 保存された 1 件の記事レコード.
@Model
final class Item {
  /// 端末をまたいで同一性を保つための ID. Share Extension が採番する `client_item_id` と一致する.
  @Attribute(.unique) var id: UUID

  // MARK: - URL

  /// ユーザーが共有した元の URL.
  var originalURL: String
  /// 仕様書 16.2 の規則で正規化した URL.
  var canonicalURL: String
  /// 正規化 URL の SHA-256. 重複判定に使う.
  var urlHash: String

  // MARK: - メタデータ（仕様書 EX-03）

  var title: String
  var siteName: String?
  var author: String?
  var publishedAt: Date?
  var updatedAtSource: Date?
  var language: String?
  var heroImageURL: String?
  var charCount: Int
  var readingMinutes: Int
  /// 本文の SHA-256. 再診断時の変更検知に使う（仕様書 EX-06）.
  var contentHash: String?

  // MARK: - 本文

  /// 抽出した本文（プレーンテキスト. 段落は改行 2 つで区切る）.
  var bodyText: String?
  /// ユーザーが共有時に選択していたテキスト（仕様書 SE-03）.
  var selectionText: String?

  // MARK: - 状態

  private var statusRaw: String
  var isRead: Bool
  var isFavorite: Bool
  var savedAt: Date
  var analyzedAt: Date?
  /// 共有元アプリのバンドル ID.
  var sourceApp: String?
  /// ユーザーが共有時に書いたメモ.
  var userNote: String
  /// 本文抽出や診断が失敗したときの説明. UI にそのまま表示する.
  var failureReason: String?

  // MARK: - 診断結果

  @Relationship(deleteRule: .cascade, inverse: \Summary.item)
  var summary: Summary?

  @Relationship(deleteRule: .cascade, inverse: \CredibilityReport.item)
  var credibility: CredibilityReport?

  @Relationship(deleteRule: .cascade, inverse: \FreshnessReport.item)
  var freshness: FreshnessReport?

  @Relationship(deleteRule: .cascade, inverse: \Highlight.item)
  var highlights: [Highlight]

  @Relationship(inverse: \Tag.items)
  var tags: [Tag]

  init(
    id: UUID = UUID(),
    originalURL: String,
    canonicalURL: String,
    urlHash: String,
    title: String,
    savedAt: Date = .now
  ) {
    self.id = id
    self.originalURL = originalURL
    self.canonicalURL = canonicalURL
    self.urlHash = urlHash
    self.title = title
    self.charCount = 0
    self.readingMinutes = 0
    self.statusRaw = ItemStatus.pending.rawValue
    self.isRead = false
    self.isFavorite = false
    self.savedAt = savedAt
    self.userNote = ""
    self.highlights = []
    self.tags = []
  }

  // MARK: - 派生プロパティ

  /// 処理状態. SwiftData の述語で扱えるよう内部では文字列として保持する.
  var status: ItemStatus {
    get { ItemStatus(rawValue: statusRaw) ?? .pending }
    set { statusRaw = newValue.rawValue }
  }

  /// 正規化 URL のホスト名（`www.` を除去済み）. ドメイン評価の参照に使う.
  var host: String {
    guard let host = URL(string: canonicalURL)?.host()?.lowercased() else { return "" }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  /// 表示用の出典名. サイト名があればそれを使い, 無ければホスト名を使う.
  var displayHost: String {
    if let siteName, !siteName.isEmpty { return siteName }
    let host = host
    return host.isEmpty ? canonicalURL : host
  }

  /// 信頼度スコア. 未診断なら `nil`.
  var credibilityScore: Int? { credibility?.totalScore }

  /// 鮮度スコア. 未診断なら `nil`.
  var freshnessScore: Int? { freshness?.freshnessScore }

  /// 立っている警告フラグ.
  var flags: [CredibilityFlag] { credibility?.flags ?? [] }

  /// 信頼度・鮮度の両方が揃っているか.
  var isFullyAnalyzed: Bool { credibility != nil && freshness != nil }

  /// 発行日（不明な場合は保存日）を返す. ソート用.
  var effectiveDate: Date { updatedAtSource ?? publishedAt ?? savedAt }

  /// 全文検索の判定（仕様書 LB-04）.
  ///
  /// 仕様書 10.1 は 1,000 件でも 300ms 以内の検索を求めるため,
  /// 本文を含む巨大な文字列を毎回連結せず, 軽い項目から順に短絡評価する.
  func matches(query: String) -> Bool {
    guard !query.isEmpty else { return true }

    if title.localizedCaseInsensitiveContains(query) { return true }
    if displayHost.localizedCaseInsensitiveContains(query) { return true }
    if !userNote.isEmpty, userNote.localizedCaseInsensitiveContains(query) { return true }
    if let author, author.localizedCaseInsensitiveContains(query) { return true }
    if tags.contains(where: { $0.name.localizedCaseInsensitiveContains(query) }) { return true }

    if let summary {
      if summary.tldr.localizedCaseInsensitiveContains(query) { return true }
      if summary.keyPoints.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
      if let detailed = summary.detailed, detailed.localizedCaseInsensitiveContains(query) { return true }
    }

    if highlights.contains(where: { $0.quote.localizedCaseInsensitiveContains(query) }) { return true }

    // 本文は最後に調べる（最も重いため）.
    if let bodyText, bodyText.localizedCaseInsensitiveContains(query) { return true }
    return false
  }

  /// 意味的な近さの推定に使う軽量なテキスト.
  /// 本文全体を毎回トークン化すると検索が重くなるため, 要約とタグに絞る.
  var searchHeadline: String {
    var parts: [String] = [title]
    if let summary {
      parts.append(summary.tldr)
      parts.append(contentsOf: summary.keyPoints)
    }
    parts.append(contentsOf: tags.map(\.name))
    if !userNote.isEmpty { parts.append(userNote) }
    return parts.joined(separator: "\n")
  }

  /// 検索結果の抜粋を作るためのテキスト（本文の冒頭までを含む）.
  var searchSnippetSource: String {
    var parts: [String] = [title]
    if let summary { parts.append(summary.tldr) }
    if let bodyText { parts.append(String(bodyText.prefix(2_000))) }
    if !userNote.isEmpty { parts.append(userNote) }
    return parts.joined(separator: "\n")
  }
}
