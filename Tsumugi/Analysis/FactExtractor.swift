//
//  FactExtractor.swift
//  Tsumugi
//
//  仕様書 SM-03: 記事内で言及された数値・固有名詞・日付を構造化抽出する.
//  仕様書 9.6「Grounding 検証」に従い, 抽出は必ず原文からの機械的な切り出しに限定する.
//

import Foundation
import NaturalLanguage

enum FactExtractor {

  /// 抽出パターンと種別の対応.
  private static let patterns: [(type: String, pattern: String)] = [
    ("percentage", #"\d+(?:\.\d+)?\s*(?:%|パーセント|割)"#),
    ("amount", #"(?:約)?\d+(?:,\d{3})*(?:\.\d+)?\s*(?:兆|億|万)?円"#),
    ("amount", #"\$\s?\d+(?:,\d{3})*(?:\.\d+)?"#),
    ("count", #"\d+(?:,\d{3})*\s*(?:件|人|社|台|回|本|万人|億人)"#),
    ("date", #"20\d{2}\s*年\s*\d{1,2}\s*月(?:\s*\d{1,2}\s*日)?"#),
    ("date", #"20\d{2}[-/]\d{1,2}[-/]\d{1,2}"#),
    ("version", #"(?:v|ver\.?|バージョン)\s?\d+(?:\.\d+){1,2}"#),
    ("duration", #"\d+\s*(?:年|か月|ヶ月|カ月|週間|日間|時間|分)"#)
  ]

  /// 抽出結果 1 件が持つ前後の文脈の長さ.
  private static let contextRadius = 22

  /// 本文から事実を抽出する.
  static func extract(from body: String, limit: Int) -> [Fact] {
    var facts: [Fact] = []
    var seenValues = Set<String>()

    for (type, pattern) in patterns {
      guard let regex = HTMLText.regex(pattern, options: []) else { continue }
      let nsBody = body as NSString
      let matches = regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
      for match in matches {
        guard facts.count < limit else { break }
        let value = nsBody.substring(with: match.range).trimmingCharacters(in: .whitespaces)
        guard seenValues.insert("\(type):\(value)").inserted else { continue }
        facts.append(
          Fact(type: type, value: value, context: context(around: match.range, in: nsBody))
        )
      }
    }

    // 固有名詞（組織・人名・地名）を追加する.
    facts.append(contentsOf: namedEntities(in: body, limit: max(0, limit - facts.count), excluding: seenValues))

    return Array(facts.prefix(limit))
  }

  /// 一致箇所の前後を切り出して文脈にする.
  private static func context(around range: NSRange, in body: NSString) -> String {
    let start = max(0, range.location - contextRadius)
    let end = min(body.length, range.location + range.length + contextRadius)
    let snippet = body.substring(with: NSRange(location: start, length: end - start))
    return snippet.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
  }

  /// NaturalLanguage の固有表現抽出で組織名・人名・地名を拾う.
  private static func namedEntities(in body: String, limit: Int, excluding seen: Set<String>) -> [Fact] {
    guard limit > 0 else { return [] }
    let target = String(body.prefix(8_000))
    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = target

    var counts: [String: (type: String, count: Int, context: String)] = [:]
    let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

    tagger.enumerateTags(
      in: target.startIndex..<target.endIndex,
      unit: .word,
      scheme: .nameType,
      options: options
    ) { tag, range in
      guard let tag else { return true }
      let type: String
      switch tag {
      case .organizationName: type = "organization"
      case .personalName: type = "person"
      case .placeName: type = "place"
      default: return true
      }
      let value = String(target[range])
      guard value.count >= 2, !seen.contains("\(type):\(value)") else { return true }

      if var existing = counts[value] {
        existing.count += 1
        counts[value] = existing
      } else {
        let contextStart = target.index(range.lowerBound, offsetBy: -contextRadius, limitedBy: target.startIndex) ?? target.startIndex
        let contextEnd = target.index(range.upperBound, offsetBy: contextRadius, limitedBy: target.endIndex) ?? target.endIndex
        let snippet = String(target[contextStart..<contextEnd]).replacingOccurrences(of: "\n", with: " ")
        counts[value] = (type, 1, snippet.trimmingCharacters(in: .whitespaces))
      }
      return true
    }

    return counts
      .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
      .prefix(limit)
      .map { Fact(type: $0.value.type, value: $0.key, context: $0.value.context) }
  }
}
