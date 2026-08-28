//
//  LibraryFilter.swift
//  Tsumugi
//
//  仕様書 LB-02 / LB-03: ライブラリのフィルタとソート.
//

import Foundation
import Observation

/// 既読状態のフィルタ.
enum ReadStateFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case unread
  case read

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .all: return "すべて"
    case .unread: return "未読"
    case .read: return "既読"
    }
  }
}

/// 保存期間のフィルタ.
enum SavedPeriodFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case today
  case week
  case month
  case year

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .all: return "全期間"
    case .today: return "今日"
    case .week: return "1 週間"
    case .month: return "1 か月"
    case .year: return "1 年"
    }
  }

  /// この期間に含まれる最も古い日時.
  var earliestDate: Date? {
    let calendar = Calendar.current
    switch self {
    case .all: return nil
    case .today: return calendar.startOfDay(for: .now)
    case .week: return calendar.date(byAdding: .day, value: -7, to: .now)
    case .month: return calendar.date(byAdding: .month, value: -1, to: .now)
    case .year: return calendar.date(byAdding: .year, value: -1, to: .now)
    }
  }
}

/// 並び順（仕様書 LB-03）.
enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
  case savedAt
  case publishedAt
  case credibility
  case freshness
  case readingMinutes

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .savedAt: return "保存日"
    case .publishedAt: return "発行日"
    case .credibility: return "信頼度"
    case .freshness: return "鮮度"
    case .readingMinutes: return "読了時間"
    }
  }

  var symbolName: String {
    switch self {
    case .savedAt: return "tray.and.arrow.down"
    case .publishedAt: return "calendar"
    case .credibility: return "checkmark.seal"
    case .freshness: return "leaf"
    case .readingMinutes: return "clock"
    }
  }
}

/// 一覧の表示形式（仕様書 LB-01）.
enum LibraryLayout: String, CaseIterable, Identifiable, Sendable {
  case card
  case list

  var id: String { rawValue }

  var symbolName: String {
    switch self {
    case .card: return "rectangle.grid.1x2"
    case .list: return "list.bullet"
    }
  }
}

/// ライブラリの絞り込み条件.
@Observable
final class LibraryFilter {
  var searchText: String = ""
  var readState: ReadStateFilter = .all
  var favoritesOnly: Bool = false
  var selectedTagNames: Set<String> = []
  /// 信頼度の帯（仕様書 4.4.2）.
  var credibilityBands: Set<CredibilityBand> = []
  /// 鮮度の帯（仕様書 4.5.3）.
  var stalenessLabels: Set<StalenessLabel> = []
  var period: SavedPeriodFilter = .all
  var sort: LibrarySort = .savedAt
  var isAscending: Bool = false
  var layout: LibraryLayout = .card

  /// 既定以外の条件が 1 つでも設定されているか.
  var isActive: Bool {
    readState != .all
      || favoritesOnly
      || !selectedTagNames.isEmpty
      || !credibilityBands.isEmpty
      || !stalenessLabels.isEmpty
      || period != .all
  }

  /// 有効なフィルタの数. チップのバッジに使う.
  var activeCount: Int {
    var count = 0
    if readState != .all { count += 1 }
    if favoritesOnly { count += 1 }
    count += selectedTagNames.count
    count += credibilityBands.count
    count += stalenessLabels.count
    if period != .all { count += 1 }
    return count
  }

  func reset() {
    readState = .all
    favoritesOnly = false
    selectedTagNames = []
    credibilityBands = []
    stalenessLabels = []
    period = .all
  }

  /// 条件に合う Item だけを残し, 指定した順に並べ替える.
  func apply(to items: [Item]) -> [Item] {
    var result = items.filter { matches($0) }
    result.sort(by: comparator)
    return result
  }

  // MARK: - 内部処理

  private func matches(_ item: Item) -> Bool {
    switch readState {
    case .all: break
    case .unread: if item.isRead { return false }
    case .read: if !item.isRead { return false }
    }

    if favoritesOnly && !item.isFavorite { return false }

    if !selectedTagNames.isEmpty {
      let names = Set(item.tags.map(\.name))
      guard !names.isDisjoint(with: selectedTagNames) else { return false }
    }

    if !credibilityBands.isEmpty {
      guard let score = item.credibilityScore,
            credibilityBands.contains(CredibilityBand.from(score: score)) else { return false }
    }

    if !stalenessLabels.isEmpty {
      guard let label = item.freshness?.stalenessLabel,
            stalenessLabels.contains(label) else { return false }
    }

    if let earliest = period.earliestDate, item.savedAt < earliest { return false }

    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
      guard item.matches(query: query) else { return false }
    }

    return true
  }

  private func comparator(_ lhs: Item, _ rhs: Item) -> Bool {
    let ascending = isAscending
    switch sort {
    case .savedAt:
      return ascending ? lhs.savedAt < rhs.savedAt : lhs.savedAt > rhs.savedAt
    case .publishedAt:
      let lhsDate = lhs.publishedAt ?? .distantPast
      let rhsDate = rhs.publishedAt ?? .distantPast
      return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
    case .credibility:
      // 未診断は常に末尾へ送る.
      let lhsScore = lhs.credibilityScore ?? (ascending ? Int.max : Int.min)
      let rhsScore = rhs.credibilityScore ?? (ascending ? Int.max : Int.min)
      return ascending ? lhsScore < rhsScore : lhsScore > rhsScore
    case .freshness:
      let lhsScore = lhs.freshnessScore ?? (ascending ? Int.max : Int.min)
      let rhsScore = rhs.freshnessScore ?? (ascending ? Int.max : Int.min)
      return ascending ? lhsScore < rhsScore : lhsScore > rhsScore
    case .readingMinutes:
      return ascending ? lhs.readingMinutes < rhs.readingMinutes : lhs.readingMinutes > rhs.readingMinutes
    }
  }
}
