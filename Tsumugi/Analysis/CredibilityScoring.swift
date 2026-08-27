//
//  CredibilityScoring.swift
//  Tsumugi
//
//  仕様書 9.4「スコア合成の実装」の Swift 移植.
//  LLM を使う場合もルールベースの場合も, 最終的な総合スコアは必ずこの決定的な関数で合成する.
//  これにより, どのプロバイダを使っても採点基準が揺れないようにする.
//

import Foundation

enum CredibilityScoring {

  /// 中央値. 確信度が低いときにスコアを寄せる基準点.
  private static let neutralPoint = 50.0

  /// 合成結果.
  struct Composed: Sendable {
    var total: Int
    var band: CredibilityBand
    /// 重み再正規化に使われたカテゴリ. 判定不能な項目は含まれない（仕様書 9.6）.
    var evaluatedCategories: [CredibilityCategory]
    /// フラグによる減点の合計.
    var penalty: Int

    var label: String { band.displayName }
  }

  /// カテゴリ別スコアとフラグから総合スコアを合成する.
  ///
  /// 仕様書 9.4 の `composeCredibilityScore` に対応する.
  /// 判定不能なカテゴリ（`scores` に含まれないカテゴリ）は計算から除外し,
  /// 残ったカテゴリの重みを再正規化する（仕様書 9.6「不明の明示」）.
  ///
  /// - Parameters:
  ///   - scores: 判定できたカテゴリのスコア（0〜100）.
  ///   - flags: 立っている警告フラグ.
  ///   - confidence: AI の確信度.
  ///   - penaltyMultiplier: 「診断の厳しさ」設定による減点の倍率（仕様書 S-09）.
  static func compose(
    scores: [CredibilityCategory: Int],
    flags: [CredibilityFlag],
    confidence: AnalysisConfidence,
    penaltyMultiplier: Double = 1.0
  ) -> Composed {
    let evaluated = CredibilityCategory.allCases.filter { scores[$0] != nil }

    // 1 つも判定できなかった場合は中央値を返し, 断定を避ける.
    guard !evaluated.isEmpty else {
      return Composed(
        total: Int(neutralPoint),
        band: CredibilityBand.from(score: Int(neutralPoint)),
        evaluatedCategories: [],
        penalty: 0
      )
    }

    let weightSum = evaluated.reduce(0.0) { $0 + $1.weight }
    let weighted = evaluated.reduce(0.0) { accumulator, category in
      accumulator + Double(scores[category] ?? 0) * category.weight
    } / weightSum

    // 仕様書 9.4 `FLAG_PENALTIES`. 同じフラグが重複しても 1 回だけ数える.
    let penalty = Set(flags).reduce(0.0) { $0 + $1.penalty } * penaltyMultiplier

    // 確信度が低い場合は中央（50）方向へ収縮させ, 断定を避ける.
    let shrunk = neutralPoint + (weighted - penalty - neutralPoint) * confidence.shrinkFactor
    let total = clampToScore(shrunk)

    return Composed(
      total: total,
      band: CredibilityBand.from(score: total),
      evaluatedCategories: evaluated,
      penalty: Int(penalty.rounded())
    )
  }

  /// 0〜100 に丸める.
  static func clampToScore(_ value: Double) -> Int {
    Int(max(0, min(100, value.rounded())))
  }
}
