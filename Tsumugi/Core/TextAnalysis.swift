//
//  TextAnalysis.swift
//  Tsumugi
//
//  日本語を含む本文を扱うための言語処理ユーティリティ.
//  仕様書 LB-04「日本語形態素対応」を NaturalLanguage フレームワークで満たす.
//

import Foundation
import NaturalLanguage

enum TextAnalysis {

  /// 語として数えない一般語（日本語 / 英語）.
  private static let stopWords: Set<String> = [
    "こと", "もの", "これ", "それ", "あれ", "ため", "よう", "そう", "など", "また", "さらに",
    "しかし", "ただし", "つまり", "および", "または", "です", "ます", "する", "される", "した",
    "いる", "ある", "なる", "できる", "この", "その", "あの", "どの", "とき", "場合", "ところ",
    "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "for", "with", "is", "are",
    "was", "were", "be", "been", "it", "this", "that", "as", "at", "by", "from", "we", "you"
  ]

  /// 本文を文単位に分割する.
  static func sentences(in text: String) -> [String] {
    guard !text.isEmpty else { return [] }
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    var result: [String] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
      if !sentence.isEmpty { result.append(sentence) }
      return true
    }
    return result
  }

  /// 文とその原文中の文字オフセットを返す. 仕様書 SM-06（原文ジャンプ）に使う.
  static func sentencesWithOffsets(in text: String) -> [(sentence: String, range: Range<Int>)] {
    guard !text.isEmpty else { return [] }
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    var result: [(String, Range<Int>)] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !sentence.isEmpty else { return true }
      let start = text.distance(from: text.startIndex, to: range.lowerBound)
      let end = text.distance(from: text.startIndex, to: range.upperBound)
      result.append((sentence, start..<end))
      return true
    }
    return result
  }

  /// 単語に分割する. 日本語は形態素境界で切られる.
  static func words(in text: String) -> [String] {
    guard !text.isEmpty else { return [] }
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    var result: [String] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      let word = String(text[range])
      if !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(word) }
      return true
    }
    return result
  }

  /// 内容語（名詞・固有名詞など）の出現頻度を数える.
  static func keywordFrequencies(in text: String, limit: Int = 40) -> [(word: String, count: Int)] {
    guard !text.isEmpty else { return [] }
    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = text

    var counts: [String: Int] = [:]
    let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]
    tagger.enumerateTags(
      in: text.startIndex..<text.endIndex,
      unit: .word,
      scheme: .lexicalClass,
      options: options
    ) { tag, range in
      guard let tag else { return true }
      // 名詞と固有名詞のみを対象にし, 助詞や動詞語尾を除く.
      guard tag == .noun || tag == .otherWord else { return true }
      let word = String(text[range])
      guard word.count >= 2, !stopWords.contains(word.lowercased()), !word.allSatisfy(\.isNumber) else { return true }
      counts[word, default: 0] += 1
      return true
    }

    return counts
      .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
      .prefix(limit)
      .map { (word: $0.key, count: $0.value) }
  }

  /// 主要言語を判定する.
  static func dominantLanguage(of text: String) -> String? {
    guard !text.isEmpty else { return nil }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(String(text.prefix(2_000)))
    return recognizer.dominantLanguage?.rawValue
  }

  /// テキストに含まれる語のうち, 指定した辞書に一致した語を数える.
  static func occurrences(of dictionary: [String], in text: String) -> [String: Int] {
    var found: [String: Int] = [:]
    let lowered = text.lowercased()
    for term in dictionary {
      let count = lowered.components(separatedBy: term.lowercased()).count - 1
      if count > 0 { found[term] = count }
    }
    return found
  }

  /// 引用が本文に実在するか検証する（仕様書 9.6「引用強制」）.
  /// 記号や空白の揺れを吸収するため, 正規化した文字列同士で照合する.
  static func quoteExists(_ quote: String, in body: String) -> Bool {
    let normalizedQuote = normalizeForMatching(quote)
    guard normalizedQuote.count >= 6 else { return false }
    return normalizeForMatching(body).contains(normalizedQuote)
  }

  /// 照合用に空白・記号を落として正規化する.
  static func normalizeForMatching(_ text: String) -> String {
    let allowed = text.unicodeScalars.filter { scalar in
      CharacterSet.alphanumerics.contains(scalar)
        || (0x3040...0x30FF).contains(scalar.value)
        || (0x4E00...0x9FFF).contains(scalar.value)
    }
    return String(String.UnicodeScalarView(allowed)).lowercased()
  }
}
