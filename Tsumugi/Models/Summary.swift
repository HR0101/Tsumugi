//
//  Summary.swift
//  Tsumugi
//
//  仕様書 4.3 / 7.1 `summaries`: 3 段階の要約.
//

import Foundation
import SwiftData

@Model
final class Summary {
  /// TL;DR（1〜2 文）.
  var tldr: String
  /// キーポイント（3〜7 項目）.
  var keyPoints: [String]
  /// 詳細要約（400〜800 字）.
  var detailed: String?
  /// 主張と根拠の対（仕様書 SM-02）.
  var claims: [Claim]
  /// 数値・固有名詞・日付の構造化抽出（仕様書 SM-03）.
  var facts: [Fact]
  /// ハイライト部分を重点化した要約（仕様書 SM-07）.
  var highlightFocused: String?
  /// 生成に使用したモデル名. 仕様書 14「モデル更新による非互換」への対策として記録する.
  var model: String
  /// 出力言語（仕様書 SM-04）.
  var language: String
  /// 原文が短すぎて要約をスキップした場合に `true`（仕様書 12.2）.
  var wasSkipped: Bool
  var createdAt: Date

  var item: Item?

  init(
    tldr: String,
    keyPoints: [String],
    detailed: String? = nil,
    claims: [Claim] = [],
    facts: [Fact] = [],
    highlightFocused: String? = nil,
    model: String,
    language: String,
    wasSkipped: Bool = false
  ) {
    self.tldr = tldr
    self.keyPoints = keyPoints
    self.detailed = detailed
    self.claims = claims
    self.facts = facts
    self.highlightFocused = highlightFocused
    self.model = model
    self.language = language
    self.wasSkipped = wasSkipped
    self.createdAt = .now
  }
}
