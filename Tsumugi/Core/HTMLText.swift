//
//  HTMLText.swift
//  Tsumugi
//
//  HTML 文字列を扱うための小さなユーティリティ群.
//  仕様書 11.1 の方針（WKWebView を使わずネイティブ描画）に従い, 自前で処理する.
//

import Foundation

enum HTMLText {

  /// 正規表現をキャッシュして使い回す. 大きな HTML で毎回コンパイルするコストを避ける.
  private static var regexCache: [String: NSRegularExpression] = [:]
  private static let cacheLock = NSLock()

  static func regex(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]) -> NSRegularExpression? {
    let key = "\(pattern)|\(options.rawValue)"
    cacheLock.lock()
    defer { cacheLock.unlock() }
    if let cached = regexCache[key] { return cached }
    guard let created = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
    regexCache[key] = created
    return created
  }

  /// パターンに一致する部分をすべて置換する.
  static func replacingMatches(in text: String, pattern: String, with template: String) -> String {
    guard let regex = regex(pattern) else { return text }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
  }

  /// パターンに一致した箇所のキャプチャグループを列挙する.
  static func matches(in text: String, pattern: String, groups: [Int]) -> [[String]] {
    guard let regex = regex(pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).map { match in
      groups.map { index -> String in
        guard index < match.numberOfRanges, let subRange = Range(match.range(at: index), in: text) else { return "" }
        return String(text[subRange])
      }
    }
  }

  /// 最初に一致した箇所の指定グループを返す.
  static func firstMatch(in text: String, pattern: String, group: Int = 1) -> String? {
    matches(in: text, pattern: pattern, groups: [group]).first?.first
  }

  /// `<script>` `<style>` などの非表示要素とコメントを取り除く.
  static func removingNoiseElements(from html: String) -> String {
    var result = html
    let noiseTags = ["script", "style", "noscript", "svg", "iframe", "template", "form", "figure"]
    for tag in noiseTags {
      result = replacingMatches(in: result, pattern: "<\(tag)\\b[^>]*>.*?</\(tag)>", with: "")
      result = replacingMatches(in: result, pattern: "<\(tag)\\b[^>]*/>", with: "")
    }
    result = replacingMatches(in: result, pattern: "<!--.*?-->", with: "")
    return result
  }

  /// ナビゲーションやフッターなど本文以外の領域を取り除く.
  static func removingChromeElements(from html: String) -> String {
    var result = html
    for tag in ["nav", "header", "footer", "aside"] {
      result = replacingMatches(in: result, pattern: "<\(tag)\\b[^>]*>.*?</\(tag)>", with: "")
    }
    return result
  }

  /// すべてのタグを除去してプレーンテキストにする.
  static func strippingTags(_ html: String) -> String {
    let withoutTags = replacingMatches(in: html, pattern: "<[^>]+>", with: " ")
    return decodingEntities(withoutTags)
  }

  /// 主要な HTML エンティティをデコードする.
  static func decodingEntities(_ text: String) -> String {
    var result = text
    let namedEntities: [String: String] = [
      "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
      "&apos;": "'", "&nbsp;": " ", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–",
      "&laquo;": "«", "&raquo;": "»", "&ldquo;": "“", "&rdquo;": "”",
      "&lsquo;": "‘", "&rsquo;": "’", "&yen;": "¥", "&copy;": "©", "&reg;": "®"
    ]
    for (entity, replacement) in namedEntities {
      result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
    }
    // 数値文字参照（10 進 / 16 進）.
    result = replacingNumericEntities(in: result)
    return result
  }

  private static func replacingNumericEntities(in text: String) -> String {
    guard let regex = regex("&#(x?)([0-9a-fA-F]+);", options: []) else { return text }
    let nsText = text as NSString
    var result = ""
    var lastLocation = 0
    for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
      result += nsText.substring(with: NSRange(location: lastLocation, length: match.range.location - lastLocation))
      let isHex = nsText.substring(with: match.range(at: 1)).lowercased() == "x"
      let digits = nsText.substring(with: match.range(at: 2))
      if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
        result.append(Character(scalar))
      }
      lastLocation = match.range.location + match.range.length
    }
    result += nsText.substring(from: lastLocation)
    return result
  }

  /// 連続する空白・改行を整理する.
  static func normalizingWhitespace(_ text: String) -> String {
    var result = replacingMatches(in: text, pattern: "[ \\t\\u{3000}]+", with: " ")
    result = replacingMatches(in: result, pattern: "\\n{3,}", with: "\n\n")
    return result
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
