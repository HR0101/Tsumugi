//
//  Highlight.swift
//  Tsumugi
//
//  仕様書 7.1 `highlights`: 本文中のハイライトとメモ.
//

import Foundation
import SwiftData

@Model
final class Highlight {
  @Attribute(.unique) var id: UUID
  /// ハイライトした本文の引用.
  var quote: String
  /// 本文中の開始文字オフセット.
  var startOffset: Int?
  /// 本文中の終了文字オフセット.
  var endOffset: Int?
  /// ハイライトに紐づくユーザーメモ.
  var note: String
  var createdAt: Date

  var item: Item?

  init(quote: String, startOffset: Int? = nil, endOffset: Int? = nil, note: String = "") {
    self.id = UUID()
    self.quote = quote
    self.startOffset = startOffset
    self.endOffset = endOffset
    self.note = note
    self.createdAt = .now
  }
}
