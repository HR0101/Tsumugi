//
//  FreshnessReport.swift
//  Tsumugi
//
//  仕様書 4.5 / 7.1 `freshness_reports`: 情報の新しさ診断の結果.
//

import Foundation
import SwiftData

@Model
final class FreshnessReport {
  /// 鮮度スコア 0〜100.
  var freshnessScore: Int
  private var stalenessLabelRaw: String
  private var topicClassRaw: String
  /// 適用された半減期（日）. 減衰しないトピックでは `nil`.
  var halfLifeDays: Int?
  /// 基準日からの経過日数. 日付不明の場合は `nil`.
  var elapsedDays: Int?
  /// 時間減衰のみのスコア（補正前）. 半減期グラフの描画に使う.
  var decayedScore: Int
  var adjustments: [FreshnessAdjustment]
  var obsoletePoints: [ObsoletePoint]
  var successors: [Successor]
  var evaluatedAt: Date
  /// ユーザーがこの診断を「不正確」と報告したか.
  var userDisputed: Bool

  var item: Item?

  init(
    freshnessScore: Int,
    stalenessLabel: StalenessLabel,
    topicClass: TopicClass,
    halfLifeDays: Int?,
    elapsedDays: Int?,
    decayedScore: Int,
    adjustments: [FreshnessAdjustment],
    obsoletePoints: [ObsoletePoint] = [],
    successors: [Successor] = []
  ) {
    self.freshnessScore = freshnessScore
    self.stalenessLabelRaw = stalenessLabel.rawValue
    self.topicClassRaw = topicClass.rawValue
    self.halfLifeDays = halfLifeDays
    self.elapsedDays = elapsedDays
    self.decayedScore = decayedScore
    self.adjustments = adjustments
    self.obsoletePoints = obsoletePoints
    self.successors = successors
    self.evaluatedAt = .now
    self.userDisputed = false
  }

  var stalenessLabel: StalenessLabel {
    get { StalenessLabel(rawValue: stalenessLabelRaw) ?? .unknown }
    set { stalenessLabelRaw = newValue.rawValue }
  }

  var topicClass: TopicClass {
    get { TopicClass(rawValue: topicClassRaw) ?? .software }
    set { topicClassRaw = newValue.rawValue }
  }

  /// 補正の合計値.
  var totalAdjustment: Int { adjustments.reduce(0) { $0 + $1.delta } }

  /// VoiceOver 用の読み上げ文（仕様書 10.5）.
  var accessibilityLabel: String {
    "鮮度 \(freshnessScore) 点, \(stalenessLabel.displayName)"
  }
}
