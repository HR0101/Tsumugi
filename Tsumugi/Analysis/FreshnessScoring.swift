//
//  FreshnessScoring.swift
//  Tsumugi
//
//  仕様書 9.5「鮮度スコアの実装」の Swift 移植.
//
//  F_time = 100 × 0.5^(Δt / H)
//  F      = clamp(F_time + Σ c_j, 0, 100)
//

import Foundation

enum FreshnessScoring {

  /// 発行日を特定できない場合のスコア上限（仕様書 4.5.2）.
  private static let unknownDateCeiling = 50.0

  /// 鮮度計算の結果.
  struct Composed: Sendable {
    var score: Int
    var label: StalenessLabel
    var elapsedDays: Int?
    var halfLifeDays: Int?
    /// 補正を加える前の, 時間減衰のみのスコア.
    var decayedScore: Int
  }

  /// 半減期モデルで鮮度スコアを算出する.
  ///
  /// - Parameters:
  ///   - topicClass: 判定されたトピック分類.
  ///   - publishedAt: 発行日.
  ///   - updatedAt: 更新日. あれば発行日より優先する.
  ///   - adjustments: 補正項（仕様書 4.5.2）.
  ///   - now: 現在時刻. テストのため注入可能にしている.
  static func compute(
    topicClass: TopicClass,
    publishedAt: Date?,
    updatedAt: Date?,
    adjustments: [FreshnessAdjustment],
    now: Date = .now
  ) -> Composed {
    let adjustmentTotal = Double(adjustments.reduce(0) { $0 + $1.delta })

    // 減衰しないトピック（歴史・数学など）は常に 100 とする.
    guard let halfLife = topicClass.halfLifeDays else {
      return Composed(score: 100, label: .timeless, elapsedDays: nil, halfLifeDays: nil, decayedScore: 100)
    }

    // 基準日は更新日 → 発行日 の順.
    guard let baseDate = updatedAt ?? publishedAt else {
      // 日付不明: スコア上限を 50 に制限する.
      let score = clamp(min(unknownDateCeiling, unknownDateCeiling + adjustmentTotal))
      return Composed(
        score: score,
        label: .unknown,
        elapsedDays: nil,
        halfLifeDays: halfLife,
        decayedScore: Int(unknownDateCeiling)
      )
    }

    let elapsedDays = max(0, DateParsing.daysBetween(baseDate, and: now))
    let decayed = 100.0 * pow(0.5, Double(elapsedDays) / Double(halfLife))
    let score = clamp(decayed + adjustmentTotal)

    return Composed(
      score: score,
      label: StalenessLabel.from(score: score),
      elapsedDays: elapsedDays,
      halfLifeDays: halfLife,
      decayedScore: clamp(decayed)
    )
  }

  /// 任意の経過日数における減衰スコアを返す. 半減期グラフの描画に使う.
  static func decayedScore(elapsedDays: Double, halfLifeDays: Int) -> Double {
    100.0 * pow(0.5, elapsedDays / Double(halfLifeDays))
  }

  private static func clamp(_ value: Double) -> Int {
    Int(max(0, min(100, value.rounded())))
  }
}
