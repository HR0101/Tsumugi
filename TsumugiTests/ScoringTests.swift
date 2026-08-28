//
//  ScoringTests.swift
//  TsumugiTests
//
//  仕様書 9.4 / 9.5 のスコア合成が仕様どおりに動くことを検証する.
//

import Testing
import Foundation
@testable import Tsumugi

@Suite("信頼度スコアの合成（仕様書 9.4）")
struct CredibilityScoringTests {

  /// 5 項目すべてが揃い, フラグも無く, 確信度が高い場合は重み付き和がそのまま総合スコアになる.
  @Test("重み付き和が仕様どおりに計算される")
  func weightedSum() {
    let composed = CredibilityScoring.compose(
      scores: [.source: 78, .transparency: 85, .evidence: 58, .neutrality: 74, .corroboration: 66],
      flags: [],
      confidence: .high
    )

    // 78×0.25 + 85×0.20 + 58×0.25 + 74×0.15 + 66×0.15 = 71.7 → 72
    #expect(composed.total == 72)
    #expect(composed.band == .moderate)
    #expect(composed.label == "おおむね信頼できる")
    #expect(composed.evaluatedCategories.count == 5)
  }

  /// 仕様書 9.4 の `FLAG_PENALTIES` が総合スコアから引かれる.
  @Test("フラグの減点が適用される")
  func flagPenalty() {
    let base = CredibilityScoring.compose(
      scores: [.source: 80, .transparency: 80, .evidence: 80, .neutrality: 80, .corroboration: 80],
      flags: [],
      confidence: .high
    )
    let penalized = CredibilityScoring.compose(
      scores: [.source: 80, .transparency: 80, .evidence: 80, .neutrality: 80, .corroboration: 80],
      flags: [.noCitation, .sensational],
      confidence: .high
    )

    #expect(base.total == 80)
    // no_citation(6) + sensational(8) = 14
    #expect(penalized.total == 66)
    #expect(penalized.penalty == 14)
  }

  /// 同じフラグが重複しても減点は 1 回だけ.
  @Test("フラグの重複は 1 回だけ数える")
  func duplicateFlagsCountedOnce() {
    let composed = CredibilityScoring.compose(
      scores: [.source: 80, .transparency: 80, .evidence: 80, .neutrality: 80, .corroboration: 80],
      flags: [.sponsored, .sponsored, .sponsored],
      confidence: .high
    )
    #expect(composed.penalty == 8)
  }

  /// 仕様書 9.4: 確信度が低い場合は中央（50）方向へ収縮させる.
  @Test("確信度が低いとスコアが中央へ寄る")
  func confidenceShrink() {
    let scores: [CredibilityCategory: Int] = [
      .source: 90, .transparency: 90, .evidence: 90, .neutrality: 90, .corroboration: 90
    ]

    let high = CredibilityScoring.compose(scores: scores, flags: [], confidence: .high)
    let medium = CredibilityScoring.compose(scores: scores, flags: [], confidence: .medium)
    let low = CredibilityScoring.compose(scores: scores, flags: [], confidence: .low)

    #expect(high.total == 90)
    // 50 + (90 - 50) × 0.85 = 84
    #expect(medium.total == 84)
    // 50 + (90 - 50) × 0.6 = 74
    #expect(low.total == 74)
  }

  /// 仕様書 9.6「不明の明示」: 判定できない項目は除外し, 残りの重みを再正規化する.
  @Test("判定できない項目を除いて重みを再正規化する")
  func weightRenormalization() {
    // 外部照合（重み 0.15）を判定できなかったケース.
    let composed = CredibilityScoring.compose(
      scores: [.source: 80, .transparency: 60, .evidence: 40, .neutrality: 100],
      flags: [],
      confidence: .high
    )

    // (80×0.25 + 60×0.20 + 40×0.25 + 100×0.15) / 0.85 = 57 / 0.85 = 67.06 → 67
    #expect(composed.total == 67)
    #expect(composed.evaluatedCategories.count == 4)
    #expect(!composed.evaluatedCategories.contains(.corroboration))
  }

  /// 1 項目も判定できなかった場合は中央値を返し, 断定を避ける.
  @Test("判定材料がなければ中央値を返す")
  func noEvaluableCategories() {
    let composed = CredibilityScoring.compose(scores: [:], flags: [.noAuthor], confidence: .low)
    #expect(composed.total == 50)
    #expect(composed.evaluatedCategories.isEmpty)
  }

  /// 減点しすぎても 0 を下回らない.
  @Test("スコアは 0〜100 に丸められる")
  func clamping() {
    let composed = CredibilityScoring.compose(
      scores: [.source: 10, .transparency: 10, .evidence: 10, .neutrality: 10, .corroboration: 10],
      flags: [.satire, .contradicted, .affiliateHeavy],
      confidence: .high
    )
    #expect(composed.total == 0)
    #expect(composed.band == .low)
  }

  /// 「診断の厳しさ」設定が減点に反映される（仕様書 S-09）.
  @Test("厳しさ設定で減点の倍率が変わる")
  func strictnessMultiplier() {
    let scores: [CredibilityCategory: Int] = [
      .source: 80, .transparency: 80, .evidence: 80, .neutrality: 80, .corroboration: 80
    ]
    let lenient = CredibilityScoring.compose(
      scores: scores, flags: [.contradicted], confidence: .high,
      penaltyMultiplier: AnalysisStrictness.lenient.penaltyMultiplier
    )
    let strict = CredibilityScoring.compose(
      scores: scores, flags: [.contradicted], confidence: .high,
      penaltyMultiplier: AnalysisStrictness.strict.penaltyMultiplier
    )

    // contradicted は 18 点. ゆるやか: ×0.6 = 10.8, 厳しめ: ×1.4 = 25.2
    #expect(lenient.total == 69)
    #expect(strict.total == 55)
  }

  /// 仕様書 4.4.2 のスコア帯が境界値で正しく切り替わる.
  @Test("スコア帯の境界値", arguments: [
    (100, CredibilityBand.high), (85, .high), (84, .moderate), (70, .moderate),
    (69, .caution), (50, .caution), (49, .doubtful), (30, .doubtful), (29, .low), (0, .low)
  ])
  func bandBoundaries(score: Int, expected: CredibilityBand) {
    #expect(CredibilityBand.from(score: score) == expected)
  }
}

@Suite("鮮度スコアの合成（仕様書 9.5）")
struct FreshnessScoringTests {

  private let referenceNow = Date(timeIntervalSince1970: 1_780_000_000)

  private func date(daysAgo: Int) -> Date {
    referenceNow.addingTimeInterval(-Double(daysAgo) * 86_400)
  }

  /// F_time = 100 × 0.5^(Δt / H)
  @Test("半減期ちょうどで 50 点になる")
  func halfLifeDecay() {
    let composed = FreshnessScoring.compute(
      topicClass: .ai,
      publishedAt: date(daysAgo: 120),
      updatedAt: nil,
      adjustments: [],
      now: referenceNow
    )

    #expect(composed.score == 50)
    #expect(composed.elapsedDays == 120)
    #expect(composed.halfLifeDays == 120)
    #expect(composed.label == .aging)
  }

  @Test("半減期 2 回分で 25 点になる")
  func twoHalfLives() {
    let composed = FreshnessScoring.compute(
      topicClass: .news,
      publishedAt: date(daysAgo: 60),
      updatedAt: nil,
      adjustments: [],
      now: referenceNow
    )
    #expect(composed.score == 25)
    #expect(composed.label == .stale)
  }

  /// 更新日があれば発行日より優先する.
  @Test("更新日を基準日として使う")
  func updatedAtTakesPrecedence() {
    let composed = FreshnessScoring.compute(
      topicClass: .software,
      publishedAt: date(daysAgo: 720),
      updatedAt: date(daysAgo: 240),
      adjustments: [],
      now: referenceNow
    )
    #expect(composed.elapsedDays == 240)
    #expect(composed.score == 50)
  }

  /// 仕様書 4.5.2 の補正項が加算される.
  @Test("補正項が加算される")
  func adjustmentsApplied() {
    let composed = FreshnessScoring.compute(
      topicClass: .ai,
      publishedAt: date(daysAgo: 120),
      updatedAt: nil,
      adjustments: [
        FreshnessAdjustment(reason: .updateHistory, delta: 10),
        FreshnessAdjustment(reason: .versionOutdated, delta: -20)
      ],
      now: referenceNow
    )
    // 50 + 10 - 20 = 40
    #expect(composed.score == 40)
    #expect(composed.decayedScore == 50)
  }

  /// 仕様書 4.5.2:「日付不明」はスコア上限を 50 に制限する.
  @Test("発行日が不明ならスコア上限は 50")
  func unknownDateCeiling() {
    let composed = FreshnessScoring.compute(
      topicClass: .ai,
      publishedAt: nil,
      updatedAt: nil,
      adjustments: [FreshnessAdjustment(reason: .updateHistory, delta: 10)],
      now: referenceNow
    )
    #expect(composed.score == 50)
    #expect(composed.label == .unknown)
    #expect(composed.elapsedDays == nil)
  }

  /// 減衰しないトピックは常に 100 点.
  @Test("普遍的知識は減衰しない")
  func timelessTopic() {
    let composed = FreshnessScoring.compute(
      topicClass: .timeless,
      publishedAt: date(daysAgo: 10_000),
      updatedAt: nil,
      adjustments: [FreshnessAdjustment(reason: .yearOutdated, delta: -15)],
      now: referenceNow
    )
    #expect(composed.score == 100)
    #expect(composed.label == .timeless)
    #expect(composed.halfLifeDays == nil)
  }

  /// 未来日付でも負の経過日数にはしない.
  @Test("未来の日付でも 100 点で頭打ちになる")
  func futureDate() {
    let composed = FreshnessScoring.compute(
      topicClass: .ai,
      publishedAt: referenceNow.addingTimeInterval(86_400 * 10),
      updatedAt: nil,
      adjustments: [],
      now: referenceNow
    )
    #expect(composed.elapsedDays == 0)
    #expect(composed.score == 100)
  }

  /// 仕様書 4.5.1 の半減期の表と一致していること.
  @Test("トピックごとの半減期", arguments: [
    (TopicClass.ai, 120), (.software, 240), (.hardware, 365), (.market, 60),
    (.regulation, 500), (.medical, 900), (.academic, 1_500), (.news, 30), (.howto, 1_200)
  ])
  func halfLifeTable(topic: TopicClass, expected: Int) {
    #expect(topic.halfLifeDays == expected)
  }

  @Test("鮮度ラベルの境界値", arguments: [
    (100, StalenessLabel.current), (75, .current), (74, .aging), (45, .aging),
    (44, .stale), (20, .stale), (19, .obsolete), (0, .obsolete)
  ])
  func stalenessBoundaries(score: Int, expected: StalenessLabel) {
    #expect(StalenessLabel.from(score: score) == expected)
  }
}
