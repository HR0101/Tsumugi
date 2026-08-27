//
//  DateParsing.swift
//  Tsumugi
//
//  仕様書 EX-04: 発行日の抽出で扱う多様な日付表現をパースする.
//

import Foundation

/// 記事メタデータや本文に現れる日付文字列を `Date` に変換するユーティリティ.
enum DateParsing {
  /// ISO 8601（秒の小数部あり / なし）用のフォーマッタ.
  private static let isoFormatters: [ISO8601DateFormatter] = {
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    let dateOnly = ISO8601DateFormatter()
    dateOnly.formatOptions = [.withFullDate]
    return [withFractional, plain, dateOnly]
  }()

  /// 固定フォーマットの候補. 上から順に試す.
  private static let fixedFormats = [
    "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
    "yyyy-MM-dd'T'HH:mm:ss",
    "yyyy-MM-dd HH:mm:ss",
    "yyyy-MM-dd",
    "yyyy/MM/dd HH:mm",
    "yyyy/MM/dd",
    "yyyy年M月d日 HH:mm",
    "yyyy年M月d日",
    "EEE, dd MMM yyyy HH:mm:ss zzz",
    "MMMM d, yyyy",
    "MMM d, yyyy"
  ]

  private static let fixedFormatters: [DateFormatter] = {
    fixedFormats.map { format in
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = format
      return formatter
    }
  }()

  /// 日本語の日付表現用（`yyyy年M月d日` のロケール依存を避けるため別途用意）.
  private static let japaneseFormatters: [DateFormatter] = {
    ["yyyy年M月d日 H時m分", "yyyy年M月d日"].map { format in
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "ja_JP_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
      formatter.dateFormat = format
      return formatter
    }
  }()

  /// 任意の日付文字列を `Date` に変換する. 解釈できない場合は `nil`.
  static func parse(_ raw: String?) -> Date? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    for formatter in isoFormatters {
      if let date = formatter.date(from: trimmed) { return date }
    }
    for formatter in fixedFormatters {
      if let date = formatter.date(from: trimmed) { return date }
    }
    for formatter in japaneseFormatters {
      if let date = formatter.date(from: trimmed) { return date }
    }
    return nil
  }

  /// 本文中から `2024年3月12日` `2024-03-12` `2024/03/12` 形式の日付を最初に 1 件だけ拾う.
  /// 仕様書 EX-04 の「本文中の日付表現」に相当する.
  static func firstDate(inText text: String) -> Date? {
    let patterns = [
      #"(\d{4})[年/-](\d{1,2})[月/-](\d{1,2})日?"#
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(text.startIndex..<text.endIndex, in: text)
      guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 4 else { continue }
      let components = (1...3).compactMap { index -> Int? in
        guard let subRange = Range(match.range(at: index), in: text) else { return nil }
        return Int(text[subRange])
      }
      guard components.count == 3 else { continue }
      return makeDate(year: components[0], month: components[1], day: components[2])
    }
    return nil
  }

  /// URL パスに埋め込まれた `/2024/03/12/` 形式の日付を拾う（仕様書 EX-04）.
  static func dateFromURLPath(_ urlString: String) -> Date? {
    guard let regex = try? NSRegularExpression(pattern: #"/(20\d{2})/(\d{1,2})(?:/(\d{1,2}))?/"#) else { return nil }
    let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
    guard let match = regex.firstMatch(in: urlString, range: range) else { return nil }

    func intValue(at index: Int) -> Int? {
      guard index < match.numberOfRanges, let subRange = Range(match.range(at: index), in: urlString) else { return nil }
      return Int(urlString[subRange])
    }

    guard let year = intValue(at: 1), let month = intValue(at: 2) else { return nil }
    return makeDate(year: year, month: month, day: intValue(at: 3) ?? 1)
  }

  private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
    guard (1...12).contains(month), (1...31).contains(day) else { return nil }
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
    return calendar.date(from: components)
  }

  /// 2 つの日付の差を日数で返す.
  static func daysBetween(_ from: Date, and to: Date) -> Int {
    let seconds = to.timeIntervalSince(from)
    return Int(floor(seconds / 86_400))
  }
}
