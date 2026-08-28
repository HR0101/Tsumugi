//
//  URLNormalizerTests.swift
//  TsumugiTests
//
//  仕様書 16.2「URL 正規化ルール」の 8 項目を検証する.
//

import Testing
import Foundation
@testable import Tsumugi

@Suite("URL 正規化（仕様書 16.2）")
struct URLNormalizerTests {

  private func canonical(_ url: String, hint: String? = nil) -> String? {
    URLNormalizer.normalize(url, canonicalHint: hint)?.canonicalURL
  }

  @Test("手順 1: スキームを https に統一する")
  func schemeUnified() {
    #expect(canonical("http://example.com/a") == "https://example.com/a")
  }

  @Test("手順 2: ホストを小文字化し www. を除去する")
  func hostNormalized() {
    #expect(canonical("https://WWW.Example.COM/Path") == "https://example.com/Path")
  }

  @Test("手順 3: トラッキングパラメータを除去する")
  func trackingParametersRemoved() {
    let result = canonical(
      "https://example.com/a?utm_source=twitter&utm_medium=social&id=42&fbclid=abc&gclid=xyz&ref=nav"
    )
    #expect(result == "https://example.com/a?id=42")
  }

  @Test("手順 3: すべてがトラッキングパラメータならクエリごと消える")
  func allParametersRemoved() {
    #expect(canonical("https://example.com/a?utm_source=x&fbclid=y") == "https://example.com/a")
  }

  @Test("手順 4: 通常のフラグメントは除去する")
  func fragmentRemoved() {
    #expect(canonical("https://example.com/a#section-3") == "https://example.com/a")
  }

  @Test("手順 4: SPA のハッシュルーティングは保持する")
  func spaFragmentKept() {
    #expect(canonical("https://example.com/app#/dashboard") == "https://example.com/app#/dashboard")
    #expect(canonical("https://example.com/app#!/users/1") == "https://example.com/app#!/users/1")
  }

  @Test("手順 5: 末尾スラッシュを除去する")
  func trailingSlashRemoved() {
    #expect(canonical("https://example.com/articles/") == "https://example.com/articles")
  }

  @Test("手順 5: ルートパスのスラッシュは残す")
  func rootSlashKept() {
    let result = canonical("https://example.com/")
    #expect(result == "https://example.com/")
  }

  @Test("手順 6: canonical が指定されていればそちらを優先する")
  func canonicalHintWins() {
    let result = canonical(
      "https://example.com/a?utm_source=x",
      hint: "https://example.com/canonical-path"
    )
    #expect(result == "https://example.com/canonical-path")
  }

  @Test("手順 6: 相対パスの canonical は元 URL を基準に解決する")
  func relativeCanonicalHint() {
    let result = canonical("https://example.com/articles/old", hint: "/articles/new")
    #expect(result == "https://example.com/articles/new")
  }

  @Test("手順 7: AMP URL を正規版へ変換する")
  func ampNormalized() {
    #expect(canonical("https://example.com/news/amp") == "https://example.com/news")
    #expect(canonical("https://example.com/news/amp/") == "https://example.com/news")
    #expect(canonical("https://example.com/amp/news/item") == "https://example.com/news/item")
    #expect(canonical("https://example.com/news?amp=1") == "https://example.com/news")
  }

  @Test("手順 8: 同じ内容の URL は同じハッシュになる")
  func hashMatchesForEquivalentURLs() {
    let first = URLNormalizer.normalize("http://WWW.Example.com/a/?utm_source=x#top")
    let second = URLNormalizer.normalize("https://example.com/a")
    #expect(first?.urlHash == second?.urlHash)
    #expect(first?.urlHash.count == 64)
  }

  @Test("異なる URL は異なるハッシュになる")
  func hashDiffersForDifferentURLs() {
    let first = URLNormalizer.normalize("https://example.com/a")
    let second = URLNormalizer.normalize("https://example.com/b")
    #expect(first?.urlHash != second?.urlHash)
  }

  @Test("URL として解釈できない文字列は nil を返す")
  func invalidURLReturnsNil() {
    #expect(URLNormalizer.normalize("これはURLではありません") == nil)
    #expect(URLNormalizer.normalize("") == nil)
  }

  @Test("既定ポートは除去する")
  func defaultPortRemoved() {
    #expect(canonical("https://example.com:443/a") == "https://example.com/a")
  }
}
