//
//  Tag.swift
//  Tsumugi
//
//  仕様書 7.1 `tags` / `item_tags`: タグと付与元.
//

import Foundation
import SwiftData

/// タグの付与元. AI 自動提案か手動かを区別する（仕様書 LB-07）.
enum TagSource: String, Codable, Sendable {
  case ai
  case user
}

@Model
final class Tag {
  @Attribute(.unique) var name: String
  private var sourceRaw: String
  var createdAt: Date

  var items: [Item]

  init(name: String, source: TagSource = .user) {
    self.name = name
    self.sourceRaw = source.rawValue
    self.createdAt = .now
    self.items = []
  }

  var source: TagSource {
    get { TagSource(rawValue: sourceRaw) ?? .user }
    set { sourceRaw = newValue.rawValue }
  }

  /// このタグが付いた記事数.
  var itemCount: Int { items.count }
}
