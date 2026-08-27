//
//  GroundingValidator.swift
//  Tsumugi
//
//  仕様書 9.6: ハルシネーション対策.
//
//  | 対策 | 実装 |
//  |---|---|
//  | 引用強制 | 根拠の引用が原文に存在するか文字列照合し, 不一致なら破棄する |
//  | Grounding 検証 | 要約が挙げた数値・固有名詞が原文に存在するか機械検証する |
//  | 不明の明示 | 検証に落ちた項目は「判定できませんでした」として重みを再正規化する |
//

import Foundation

enum GroundingValidator {

  /// 検証結果の要約. 設定画面や診断画面で「何件が検証に落ちたか」を示すために使う.
  struct Report: Sendable {
    var checkedQuotes: Int = 0
    var rejectedQuotes: Int = 0
    var checkedFacts: Int = 0
    var rejectedFacts: Int = 0

    var hasRejections: Bool { rejectedQuotes > 0 || rejectedFacts > 0 }

    /// 引用の検証をどの程度通過したか（0.0〜1.0）.
    var quotePassRate: Double {
      guard checkedQuotes > 0 else { return 1.0 }
      return Double(checkedQuotes - rejectedQuotes) / Double(checkedQuotes)
    }
  }

  /// 根拠の引用を検証する. 原文に存在しない引用は取り除く.
  static func validate(rationale: [RationaleEntry], against body: String) -> (entries: [RationaleEntry], report: Report) {
    var report = Report()
    let validated = rationale.map { entry -> RationaleEntry in
      guard let quote = entry.quote, !quote.isEmpty else { return entry }
      report.checkedQuotes += 1
      if TextAnalysis.quoteExists(quote, in: body) { return entry }

      report.rejectedQuotes += 1
      var corrected = entry
      corrected.quote = nil
      corrected.reason = entry.reason + "（※ 提示された引用が原文と一致しなかったため, 引用は表示していません）"
      return corrected
    }
    return (validated, report)
  }

  /// 陳腐化ポイントの引用を検証する. 原文に存在しないものは提示しない.
  static func validate(obsoletePoints: [ObsoletePoint], against body: String) -> (points: [ObsoletePoint], report: Report) {
    var report = Report()
    let validated = obsoletePoints.filter { point in
      report.checkedQuotes += 1
      let exists = TextAnalysis.quoteExists(point.quote, in: body)
      if !exists { report.rejectedQuotes += 1 }
      return exists
    }
    return (validated, report)
  }

  /// 要約が挙げた数値・固有名詞が原文に存在するか検証する.
  static func validate(facts: [Fact], against body: String) -> (facts: [Fact], report: Report) {
    var report = Report()
    let validated = facts.filter { fact in
      report.checkedFacts += 1
      // 記号や空白の揺れを吸収して照合する.
      let exists = TextAnalysis.normalizeForMatching(body)
        .contains(TextAnalysis.normalizeForMatching(fact.value))
      if !exists { report.rejectedFacts += 1 }
      return exists
    }
    return (validated, report)
  }

  /// 主張が原文に根ざしているか検証し, 原文に対応する箇所が見つかった場合はオフセットを補う.
  /// 仕様書 SM-06（原文ジャンプ）のため.
  static func validate(claims: [Claim], against body: String) -> [Claim] {
    let sentences = TextAnalysis.sentencesWithOffsets(in: body)
    return claims.map { claim in
      guard claim.sourceOffset == nil else { return claim }
      // 主張と最も語の重なりが大きい文を探し, そのオフセットを紐付ける.
      let normalizedClaim = TextAnalysis.normalizeForMatching(claim.claim)
      guard normalizedClaim.count >= 8 else { return claim }

      let best = sentences.max { lhs, rhs in
        overlap(normalizedClaim, TextAnalysis.normalizeForMatching(lhs.sentence))
          < overlap(normalizedClaim, TextAnalysis.normalizeForMatching(rhs.sentence))
      }

      guard let best, overlap(normalizedClaim, TextAnalysis.normalizeForMatching(best.sentence)) >= 0.35 else {
        return claim
      }
      var updated = claim
      updated.sourceOffset = [best.range.lowerBound, best.range.upperBound]
      return updated
    }
  }

  /// 仕様書 9.6「二段検証」: 極端なスコアのみ再評価の対象とする.
  static func needsSecondPass(totalScore: Int) -> Bool {
    totalScore < 30 || totalScore > 90
  }

  /// 2 つの正規化文字列の文字集合の重なり率（Jaccard 係数の簡易版）.
  private static func overlap(_ lhs: String, _ rhs: String) -> Double {
    guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
    let lhsSet = Set(lhs)
    let rhsSet = Set(rhs)
    let intersection = lhsSet.intersection(rhsSet).count
    return Double(intersection) / Double(lhsSet.count)
  }
}
