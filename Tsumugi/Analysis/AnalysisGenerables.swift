//
//  AnalysisGenerables.swift
//  Tsumugi
//
//  仕様書 9.3: 診断出力の形式.
//  Apple Intelligence の Guided Generation（@Generable）で, モデルの出力をこの型に強制する.
//  仕様書 9.1「すべての診断出力は Structured Output で強制」に対応する.
//
//  列挙値は文字列のまま受け取り（.anyOf で候補を限定する）, アプリ側の列挙型へは
//  rawValue で変換する. 既存の CredibilityFlag などと値をそろえるため.
//
//  プロパティは「根拠 → 判断」の順に並べている. モデルは宣言順に生成するので,
//  先に理由を書かせてから点数を書かせた方が, 理由と点数が食い違いにくい.
//

import Foundation
import FoundationModels

// MARK: - 要約（仕様書 4.3）

@Generable(description: "記事の要約")
struct GeneratedSummary {
  @Guide(description: "記事全体の要点. 1〜2 文")
  var tldr: String

  @Guide(description: "記事の要点. それぞれ 1 文", .count(3...7))
  var keyPoints: [String]

  @Guide(description: "記事の詳しい要約")
  var detailed: String

  @Guide(description: "記事が述べている主張と, それを支える根拠", .maximumCount(5))
  var claims: [GeneratedClaim]

  @Guide(description: "本文に出てくる数値・固有名詞・日付", .maximumCount(12))
  var facts: [GeneratedFact]
}

@Generable(description: "記事の主張 1 件")
struct GeneratedClaim {
  @Guide(description: "記事が述べている主張. 200 字以内")
  var claim: String

  @Guide(description: "その主張の根拠として記事が挙げているもの. 200 字以内")
  var evidence: String

  @Guide(
    description: "根拠の質",
    .anyOf(["primary_source", "official", "academic", "single_vendor", "secondary", "none"])
  )
  var evidenceQuality: String
}

@Generable(description: "本文中の事実 1 件")
struct GeneratedFact {
  @Guide(
    description: "事実の種類",
    .anyOf(["percentage", "amount", "count", "date", "version", "duration", "organization", "person", "place", "regulation", "other"])
  )
  var type: String

  @Guide(description: "本文の表記どおりの値. 80 字以内")
  var value: String

  @Guide(description: "その値が出てくる文脈. 120 字以内")
  var context: String
}

// MARK: - 信頼度診断（仕様書 4.4 / 9.3）

@Generable(description: "記事の情報提示の作法についての診断")
struct GeneratedCredibility {
  @Guide(description: "カテゴリごとの判断理由. 各カテゴリにつき 1 件", .count(4...5))
  var rationale: [GeneratedRationale]

  @Guide(description: "発信元の評価", .range(0...100))
  var source: Int

  @Guide(description: "透明性の評価", .range(0...100))
  var transparency: Int

  @Guide(description: "論拠の質の評価", .range(0...100))
  var evidence: Int

  @Guide(description: "中立性の評価", .range(0...100))
  var neutrality: Int

  @Guide(description: "外部照合の評価. 照合できない場合も数値は入れ, 判断理由の determined を false にする", .range(0...100))
  var corroboration: Int

  @Guide(
    description: "記事に当てはまる警告. 当てはまらなければ空",
    .element(.anyOf(CredibilityFlag.allCases.map(\.rawValue)))
  )
  var flags: [String]

  @Guide(description: "この診断全体の確信度", .anyOf(AnalysisConfidence.allCases.map(\.rawValue)))
  var confidence: String
}

@Generable(description: "1 カテゴリの判断理由")
struct GeneratedRationale {
  @Guide(description: "評価したカテゴリ", .anyOf(CredibilityCategory.allCases.map(\.rawValue)))
  var category: String

  @Guide(description: "判断理由. 200 字以内")
  var reason: String

  @Guide(description: "本文から一字一句そのまま引用した根拠. 120 字以内. 引用できなければ空文字")
  var quote: String

  @Guide(description: "本文から判断できたか. 推測が必要なら false")
  var determined: Bool
}

// MARK: - 鮮度診断（仕様書 4.5.3）

@Generable(description: "記事の情報の古さについての判定材料")
struct GeneratedFreshness {
  @Guide(description: "記事のトピックの分類", .anyOf(TopicClass.allCases.map(\.rawValue)))
  var topicClass: String

  @Guide(description: "本文から根拠を引用できる補正だけ", .maximumCount(5))
  var adjustments: [GeneratedAdjustment]

  @Guide(description: "いま読むと誤解を生みうる記述", .maximumCount(3))
  var obsoletePoints: [GeneratedObsoletePoint]
}

@Generable(description: "鮮度の補正 1 件")
struct GeneratedAdjustment {
  @Guide(
    description: "補正の種類",
    .anyOf(["update_history", "version_outdated", "year_outdated", "deprecated", "successor_exists"])
  )
  var reason: String

  @Guide(description: "補正の根拠となる本文の記述. 160 字以内")
  var evidence: String
}

@Generable(description: "陳腐化した可能性のある記述 1 件")
struct GeneratedObsoletePoint {
  @Guide(description: "本文から一字一句そのまま引用した記述. 120 字以内")
  var quote: String

  @Guide(description: "いま読むと誤解を生みうる理由. 200 字以内")
  var reason: String
}

// MARK: - タグ提案（仕様書 LB-07）

@Generable(description: "記事の検索用タグ")
struct GeneratedTags {
  @Guide(description: "記事の主題を表す短いタグ. 各 20 文字以内", .count(1...5))
  var tags: [String]
}

// MARK: - アプリのモデルへの変換

/// 文字数の上限. 仕様書 9.3 / 10.6 の制限を, 生成後にも念のため適用する.
private enum TextLimit {
  static let tldr = 200
  static let keyPoint = 120
  static let detailed = 1_200
  static let claim = 200
  static let factValue = 80
  static let factContext = 120
  static let reason = 200
  static let quote = 120
  static let adjustmentEvidence = 160
  static let tag = 20
}

private extension String {
  /// 前後の空白を除き, 上限の文字数で切る.
  func clipped(to limit: Int) -> String {
    String(trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }

  /// 空文字なら nil にする.
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension GeneratedSummary {
  /// 検証前の要約の下書きに変換する. 事実の件数は予算の上限で切る.
  func makeDraft(factLimit: Int) -> SummaryDraft {
    SummaryDraft(
      tldr: tldr.clipped(to: TextLimit.tldr),
      keyPoints: keyPoints.map { $0.clipped(to: TextLimit.keyPoint) }.filter { !$0.isEmpty },
      detailed: detailed.clipped(to: TextLimit.detailed).nilIfEmpty,
      claims: claims.map { item in
        Claim(
          claim: item.claim.clipped(to: TextLimit.claim),
          evidence: item.evidence.clipped(to: TextLimit.claim),
          evidenceQuality: item.evidenceQuality
        )
      },
      facts: facts.prefix(factLimit).map { item in
        Fact(
          type: item.type,
          value: item.value.clipped(to: TextLimit.factValue),
          context: item.context.clipped(to: TextLimit.factContext)
        )
      },
      highlightFocused: nil
    )
  }
}

extension GeneratedCredibility {
  /// カテゴリ別のスコア. 0〜100 の範囲に収める.
  var categoryScores: [CredibilityCategory: Int] {
    [
      .source: clampScore(source),
      .transparency: clampScore(transparency),
      .evidence: clampScore(evidence),
      .neutrality: clampScore(neutrality),
      .corroboration: clampScore(corroboration)
    ]
  }

  /// 判断理由. 未知のカテゴリと, 同じカテゴリの重複は捨てる.
  var rationaleEntries: [RationaleEntry] {
    var seen = Set<CredibilityCategory>()
    return rationale.compactMap { item in
      guard let category = CredibilityCategory(rawValue: item.category) else { return nil }
      guard seen.insert(category).inserted else { return nil }
      return RationaleEntry(
        category: category,
        reason: item.reason.clipped(to: TextLimit.reason),
        quote: item.quote.clipped(to: TextLimit.quote).nilIfEmpty,
        isDetermined: item.determined
      )
    }
  }

  var flagValues: [CredibilityFlag] {
    Array(Set(flags.compactMap(CredibilityFlag.init(rawValue:)))).sorted { $0.rawValue < $1.rawValue }
  }

  var confidenceValue: AnalysisConfidence {
    AnalysisConfidence(rawValue: confidence) ?? .medium
  }

  private func clampScore(_ value: Int) -> Int {
    max(0, min(100, value))
  }
}

extension GeneratedFreshness {
  var topicClassValue: TopicClass {
    TopicClass(rawValue: topicClass) ?? .software
  }

  /// 補正値は仕様書 4.5.2 の固定値を使う. モデルに点数を決めさせない.
  var adjustmentValues: [FreshnessAdjustment] {
    var seen = Set<FreshnessAdjustment.Reason>()
    return adjustments.compactMap { item in
      guard let reason = FreshnessAdjustment.Reason(rawValue: item.reason) else { return nil }
      guard seen.insert(reason).inserted else { return nil }
      return FreshnessAdjustment(
        reason: reason,
        delta: reason.delta,
        evidence: item.evidence.clipped(to: TextLimit.adjustmentEvidence).nilIfEmpty
      )
    }
  }

  var obsoletePointValues: [ObsoletePoint] {
    obsoletePoints.map { item in
      ObsoletePoint(quote: item.quote.clipped(to: TextLimit.quote), reason: item.reason.clipped(to: TextLimit.reason))
    }
  }
}

extension GeneratedTags {
  /// 空のタグと重複を除いたタグ.
  var cleanedTags: [String] {
    var seen = Set<String>()
    return tags
      .map { $0.clipped(to: TextLimit.tag) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }
}
