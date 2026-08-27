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

  /// 表示用のホスト名（`www.` を除去済み）.
  var displayHost: String {
    if let siteName, !siteName.isEmpty { return siteName }
    guard let host = URL(string: canonicalURL)?.host() else { return canonicalURL }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
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

  /// 全文検索の対象となるテキストを 1 本に連結する（仕様書 LB-04）.
  var searchCorpus: String {
    var parts: [String] = [title, displayHost, userNote]
    if let author { parts.append(author) }
    if let summary {
      parts.append(summary.tldr)
      parts.append(contentsOf: summary.keyPoints)
      if let detailed = summary.detailed { parts.append(detailed) }
    }
    parts.append(contentsOf: tags.map(\.name))
    parts.append(contentsOf: highlights.map(\.quote))
    if let bodyText { parts.append(bodyText) }
    return parts.joined(separator: "\n")
  }
}
