//
//  ExtractedArticle.swift
//  Tsumugi
//
//  仕様書 EX-03: 本文抽出が返すメタデータの集合.
//

import Foundation

/// 本文抽出の結果.
struct ExtractedArticle: Sendable {

  /// 記事中のリンク 1 件.
  struct Link: Sendable, Hashable {
    var url: String
    var text: String
    /// 記事のドメインと異なる外部リンクか.
    var isExternal: Bool
    /// アフィリエイト・広告リンクと推定されるか.
    var isAffiliate: Bool
    /// 一次情報・公的機関・学術ドメインか.
    var isAuthoritative: Bool
  }

  var title: String
  var author: String?
  var publishedAt: Date?
  var updatedAt: Date?
  var siteName: String?
  var language: String?
  var heroImageURL: String?
  var canonicalHint: String?
  /// 抽出した本文（段落は改行 2 つ区切り）.
  var bodyText: String
  /// 本文中の見出し.
  var headings: [String]
  var charCount: Int
  var readingMinutes: Int
  /// 本文の SHA-256（仕様書 EX-06）.
  var contentHash: String
  var links: [Link]
  /// `<meta name="robots">` に `noarchive` が含まれるか（仕様書 EX-07 / 10.6）.
  var isNoArchive: Bool
  /// 本文が十分に取れたか. `false` なら `extractionFailed` として扱う.
  var isSuccessful: Bool

  var outboundLinks: [Link] { links.filter(\.isExternal) }
  var affiliateLinkCount: Int { links.filter(\.isAffiliate).count }
  var authoritativeLinkCount: Int { links.filter(\.isAuthoritative).count }

  /// 発行日・更新日のうち新しい方（鮮度診断の基準日）.
  var effectiveDate: Date? { updatedAt ?? publishedAt }
}
