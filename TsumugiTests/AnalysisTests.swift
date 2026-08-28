//
//  AnalysisTests.swift
//  TsumugiTests
//
//  仕様書 4.4 / 4.5 / 9.6: ルールベース診断とハルシネーション対策を検証する.
//

import Testing
import Foundation
@testable import Tsumugi

/// テスト用の入力を組み立てる補助.
private func makeInput(
  url: String = "https://qiita.com/items/abc123",
  title: String = "TypeScript の型定義を整理する方法",
  author: String? = "山田太郎",
  publishedAt: Date? = Date(timeIntervalSince1970: 1_700_000_000),
  updatedAt: Date? = nil,
  body: String,
  headings: [String] = [],
  outboundLinks: [ExtractedArticle.Link] = [],
  affiliateLinkCount: Int = 0,
  authoritativeLinkCount: Int = 0,
  now: Date = Date(timeIntervalSince1970: 1_780_000_000)
) -> AnalysisInput {
  AnalysisInput(
    url: url,
    canonicalURL: url,
    title: title,
    author: author,
    siteName: nil,
    publishedAt: publishedAt,
    updatedAt: updatedAt,
    language: "ja",
    bodyText: body,
    headings: headings,
    outboundLinks: outboundLinks,
    affiliateLinkCount: affiliateLinkCount,
    authoritativeLinkCount: authoritativeLinkCount,
    selection: nil,
    outputLanguage: "ja",
    domainReputation: nil,
    now: now
  )
}

private func makeLink(_ url: String, authoritative: Bool = false) -> ExtractedArticle.Link {
  ExtractedArticle.Link(url: url, text: "リンク", isExternal: true, isAffiliate: false, isAuthoritative: authoritative)
}

/// 十分な長さの本文（要約スキップ判定を避けるため 500 字以上にする）.
private let longBody = String(
  repeating: "この記事ではTypeScriptの型定義について整理します。まず型エイリアスとインターフェースの違いを説明し、実装での使い分けを示します。",
  count: 6
)

@Suite("ルールベース診断（仕様書 4.4）")
struct HeuristicCredibilityTests {

  private let provider = HeuristicAnalysisProvider()

  @Test("外部照合は判定せず, 推測もしない（仕様書 9.6）")
  func corroborationNotDetermined() async throws {
    let draft = try await provider.assessCredibility(makeInput(body: longBody))

    #expect(draft.scores[.corroboration] == nil)
    let entry = draft.rationale.first { $0.category == .corroboration }
    #expect(entry != nil)
    #expect(entry?.isDetermined == false)
  }

  @Test("著者と発行日が無ければフラグが立つ（仕様書 4.4.3）")
  func missingMetadataFlags() async throws {
    let draft = try await provider.assessCredibility(
      makeInput(author: nil, publishedAt: nil, body: longBody)
    )
    #expect(draft.flags.contains(.noAuthor))
    #expect(draft.flags.contains(.noDate))
    // 判断材料が乏しいので確信度は低くなる.
    #expect(draft.confidence == .low)
  }

  @Test("著者と発行日があれば透明性スコアが上がる")
  func transparencyImproves() async throws {
    let withMeta = try await provider.assessCredibility(makeInput(body: longBody))
    let withoutMeta = try await provider.assessCredibility(
      makeInput(author: nil, publishedAt: nil, body: longBody)
    )

    let withScore = try #require(withMeta.scores[.transparency])
    let withoutScore = try #require(withoutMeta.scores[.transparency])
    #expect(withScore > withoutScore)
    #expect(!withMeta.flags.contains(.noAuthor))
  }

  @Test("出典リンクが無ければ no_citation が立つ")
  func noCitationFlag() async throws {
    let draft = try await provider.assessCredibility(makeInput(body: longBody))
    #expect(draft.flags.contains(.noCitation))
  }

  @Test("一次情報へのリンクがあると論拠スコアが上がる")
  func authoritativeLinksRaiseEvidence() async throws {
    let poor = try await provider.assessCredibility(makeInput(body: longBody))
    let rich = try await provider.assessCredibility(
      makeInput(
        body: longBody + "出典: 公的機関の報告書によると、この傾向が確認されています。",
        outboundLinks: [
          makeLink("https://www.mhlw.go.jp/report", authoritative: true),
          makeLink("https://example.org/a"),
          makeLink("https://example.net/b")
        ],
        authoritativeLinkCount: 1
      )
    )

    let poorScore = try #require(poor.scores[.evidence])
    let richScore = try #require(rich.scores[.evidence])
    #expect(richScore > poorScore)
    #expect(!rich.flags.contains(.noCitation))
  }

  @Test("扇動的表現が多いと中立性スコアが下がり sensational が立つ")
  func sensationalFlag() async throws {
    let calm = try await provider.assessCredibility(makeInput(body: longBody))
    let loud = try await provider.assessCredibility(
      makeInput(
        title: "【衝撃】知らないと損する驚愕の真実",
        body: "衝撃の事実です。絶対に知らないと損する内容で、ヤバいほど驚愕の結果になりました。信じられない話です。" + longBody
      )
    )

    let calmScore = try #require(calm.scores[.neutrality])
    let loudScore = try #require(loud.scores[.neutrality])
    #expect(loudScore < calmScore)
    #expect(loud.flags.contains(.sensational))
  }

  @Test("PR 表記があると sponsored が立つ")
  func sponsoredFlag() async throws {
    let draft = try await provider.assessCredibility(
      makeInput(body: "【PR】本記事はプロモーションを含みます。" + longBody)
    )
    #expect(draft.flags.contains(.sponsored))
  }

  @Test("アフィリエイトリンクが多いと affiliate_heavy が立つ")
  func affiliateFlag() async throws {
    let draft = try await provider.assessCredibility(
      makeInput(body: longBody, affiliateLinkCount: 4)
    )
    #expect(draft.flags.contains(.affiliateHeavy))
  }

  @Test("医療分野は medical_ymyl が立つ（仕様書 10.6）")
  func medicalYMYLFlag() async throws {
    let draft = try await provider.assessCredibility(
      makeInput(
        title: "この症状に効く治療法",
        body: "症状が続く場合は治療が必要です。処方される医薬品には副作用があり、服用前に医師へ相談してください。" + longBody
      )
    )
    #expect(draft.flags.contains(.medicalYMYL))
  }

  @Test("金融分野は financial_ymyl が立つ")
  func financialYMYLFlag() async throws {
    let draft = try await provider.assessCredibility(
      makeInput(
        title: "NISA での資産運用入門",
        body: "投資の基本は分散です。NISA を使った資産運用では利回りと元本割れのリスクを理解しておく必要があります。" + longBody
      )
    )
    #expect(draft.flags.contains(.financialYMYL))
  }

  @Test("公的機関ドメインは発信元スコアが高い（仕様書 4.4.1 #1）")
  func governmentDomainScoresHigh() async throws {
    let government = try await provider.assessCredibility(
      makeInput(url: "https://www.mhlw.go.jp/stf/topic.html", body: longBody)
    )
    let community = try await provider.assessCredibility(
      makeInput(url: "https://note.com/user/n/abc", body: longBody)
    )

    let governmentScore = try #require(government.scores[.source])
    let communityScore = try #require(community.scores[.source])
    #expect(governmentScore > communityScore)
    #expect(governmentScore >= 90)
  }

  @Test("根拠は必ずすべてのカテゴリに付く（仕様書 4.4.4）")
  func rationaleAlwaysPresent() async throws {
    let draft = try await provider.assessCredibility(makeInput(body: longBody))
    for category in CredibilityCategory.allCases {
      #expect(draft.rationale.contains { $0.category == category })
    }
  }
}

@Suite("ルールベース鮮度診断（仕様書 4.5）")
struct HeuristicFreshnessTests {

  private let provider = HeuristicAnalysisProvider()
  private let now = Date(timeIntervalSince1970: 1_780_000_000)

  @Test("更新日があれば update_history 補正が付く")
  func updateHistoryAdjustment() async throws {
    let draft = try await provider.assessFreshness(
      makeInput(
        updatedAt: Date(timeIntervalSince1970: 1_770_000_000),
        body: longBody,
        now: now
      )
    )
    #expect(draft.adjustments.contains { $0.reason == .updateHistory && $0.delta == 10 })
  }

  @Test("見出しの古い年号で year_outdated 補正が付く")
  func yearOutdatedAdjustment() async throws {
    // 2026 年基準で 2023 年は 3 年前.
    let draft = try await provider.assessFreshness(
      makeInput(title: "2023年最新のAI事情まとめ", body: longBody, now: now)
    )
    #expect(draft.adjustments.contains { $0.reason == .yearOutdated && $0.delta == -15 })
  }

  @Test("半減期を超えていない記事には陳腐化ポイントを立てない")
  func noObsoletePointsWhenFresh() async throws {
    let draft = try await provider.assessFreshness(
      makeInput(
        publishedAt: now.addingTimeInterval(-86_400 * 10),
        body: "現時点で最も安価な API は 1000 トークンあたり 0.5 円です。" + longBody,
        now: now
      )
    )
    #expect(draft.obsoletePoints.isEmpty)
  }

  @Test("半減期を大きく超えると陳腐化ポイントを抽出する（仕様書 4.5.3）")
  func obsoletePointsExtracted() async throws {
    let draft = try await provider.assessFreshness(
      makeInput(
        title: "AI推論コストの比較",
        publishedAt: now.addingTimeInterval(-86_400 * 900),
        body: "生成AIのモデル比較です。現時点で最も安価なAPIは1000トークンあたり0.5円です。LLMの推論コストは下がり続けています。" + longBody,
        now: now
      )
    )
    #expect(!draft.obsoletePoints.isEmpty)
    // 仕様書 10.6: 引用は 120 字以内.
    for point in draft.obsoletePoints {
      #expect(point.quote.count <= 120)
    }
  }

  @Test("外部検索が要るため後続情報は提示しない")
  func noSuccessorsOffline() async throws {
    let draft = try await provider.assessFreshness(makeInput(body: longBody, now: now))
    #expect(draft.successors.isEmpty)
  }
}

@Suite("トピック分類（仕様書 4.5.1）")
struct TopicClassifierTests {

  @Test("AI 記事を ai に分類する")
  func classifiesAI() {
    let topic = TopicClassifier.classify(
      title: "生成AIの推論コストとLLMの比較",
      headings: ["大規模言語モデルの現在"],
      body: "生成AIの分野ではLLMの推論コストが下がり、プロンプト設計の重要性が増しています。"
    )
    #expect(topic == .ai)
  }

  @Test("法令記事を regulation に分類する")
  func classifiesRegulation() {
    let topic = TopicClassifier.classify(
      title: "改正法の施行と補助金の申請手続き",
      headings: ["税制と控除の変更点"],
      body: "改正された法律が施行され、補助金の申請要件と税率の控除が変わりました。省令も併せて公布されています。"
    )
    #expect(topic == .regulation)
  }

  @Test("歴史記事を timeless に分類する")
  func classifiesTimeless() {
    let topic = TopicClassifier.classify(
      title: "古代ローマの歴史と中世への変遷",
      headings: ["古典期の哲学"],
      body: "古代ローマの歴史を、中世の成立と古典哲学の流れから概観します。語源や由来にも触れます。"
    )
    #expect(topic == .timeless)
    #expect(topic.halfLifeDays == nil)
  }

  @Test("手がかりが乏しい場合は software（既定 240 日）にする")
  func fallsBackToSoftware() {
    let topic = TopicClassifier.classify(title: "雑記", headings: [], body: "今日はいい天気でした。")
    #expect(topic == .software)
    #expect(topic.halfLifeDays == 240)
  }
}

@Suite("ハルシネーション対策（仕様書 9.6）")
struct GroundingValidatorTests {

  private let body = "推論コストは前年比で約80%低下したと報告されています。オープンウェイトモデルの採用も進みました。"

  @Test("原文に無い引用は破棄する")
  func invalidQuoteRejected() {
    let entries = [
      RationaleEntry(category: .evidence, reason: "根拠あり", quote: "推論コストは前年比で約80%低下した"),
      RationaleEntry(category: .neutrality, reason: "根拠なし", quote: "この記事は完全な嘘である")
    ]
    let result = GroundingValidator.validate(rationale: entries, against: body)

    #expect(result.entries[0].quote != nil)
    #expect(result.entries[1].quote == nil)
    #expect(result.entries[1].reason.contains("原文と一致しなかった"))
    #expect(result.report.rejectedQuotes == 1)
  }

  @Test("原文に無い数値は要約から除く")
  func ungroundedFactsRemoved() {
    let facts = [
      Fact(type: "percentage", value: "80%", context: "推論コスト低下率"),
      Fact(type: "percentage", value: "250%", context: "存在しない数値")
    ]
    let result = GroundingValidator.validate(facts: facts, against: body)

    #expect(result.facts.count == 1)
    #expect(result.facts.first?.value == "80%")
    #expect(result.report.rejectedFacts == 1)
  }

  @Test("原文に無い陳腐化ポイントは提示しない")
  func ungroundedObsoletePointsRemoved() {
    let points = [
      ObsoletePoint(quote: "オープンウェイトモデルの採用も進みました", reason: "実在する引用"),
      ObsoletePoint(quote: "この技術は完全に廃止されました", reason: "捏造された引用")
    ]
    let result = GroundingValidator.validate(obsoletePoints: points, against: body)
    #expect(result.points.count == 1)
  }

  @Test("主張に原文のオフセットを補える（仕様書 SM-06）")
  func claimOffsetsAttached() {
    let claims = [Claim(claim: "推論コストは前年比で約80%低下した", evidence: "報告", sourceOffset: nil)]
    let validated = GroundingValidator.validate(claims: claims, against: body)
    #expect(validated.first?.sourceOffset != nil)
  }

  @Test("極端なスコアだけ二段検証の対象にする")
  func secondPassThreshold() {
    #expect(GroundingValidator.needsSecondPass(totalScore: 25))
    #expect(GroundingValidator.needsSecondPass(totalScore: 95))
    #expect(!GroundingValidator.needsSecondPass(totalScore: 60))
  }
}

@Suite("抽出型要約（仕様書 4.3）")
struct ExtractiveSummarizerTests {

  private let summarizer = ExtractiveSummarizer()

  @Test("短い記事は要約をスキップする（仕様書 12.2）")
  func shortArticleSkipped() {
    let draft = summarizer.summarize(makeInput(body: "短い記事です。"))
    #expect(draft.wasSkipped)
    #expect(draft.keyPoints.isEmpty)
  }

  @Test("十分な長さの記事は 3 段階の要約を生成する")
  func generatesThreeLevels() {
    // 仕様書 12.2 の「短文記事は要約をスキップ」に引っかからないよう 500 字以上にする.
    let body = """
    2024年のAI業界は推論コストの急落とオープンモデルの台頭が中心となり、実運用フェーズへの移行が進みました。
    推論コストは前年比で約80%低下したと、あるベンダーの価格表を根拠に報告されています。
    規制面ではEU AI Actの段階施行が始まり、事業者には対応が求められています。
    商用利用可能なオープンウェイトモデルが増え、自社環境での運用を選ぶ企業が増加しました。
    企業の導入事例では、社内文書の検索と要約が最初のユースケースになることが多いと報告されています。
    一方で、生成結果の正確性の検証をどう組み込むかが引き続き課題として残っています。
    評価データセットの整備と、人手によるレビュー工程の設計が重要になると指摘されています。
    国内では、金融や医療といった規制の厳しい業界でも段階的な導入が始まったと伝えられています。
    small language model と呼ばれる小型モデルを端末上で動かす取り組みも各社で進められています。
    推論基盤の選定では、レイテンシとコストのどちらを優先するかで構成が大きく変わると解説されています。
    運用面では、プロンプトの版管理と出力の監査ログの整備が実務上の課題になると指摘されています。
    ベンダー各社は、企業向けにデータを学習に使わない契約オプションを用意し始めました。
    """
    let draft = summarizer.summarize(makeInput(body: body))

    #expect(!draft.wasSkipped)
    #expect(!draft.tldr.isEmpty)
    #expect(draft.keyPoints.count >= 3)
    #expect(draft.keyPoints.count <= 7)
    #expect(draft.detailed != nil)
  }

  @Test("要約は原文の文をそのまま使うため必ず原文に存在する")
  func summaryIsGrounded() {
    let body = String(
      repeating: "推論コストは前年比で約80%低下したと報告されています。オープンウェイトモデルの採用も広がっています。",
      count: 6
    )
    let draft = summarizer.summarize(makeInput(body: body))

    // 抽出型なので, キーポイントは必ず原文に含まれる（末尾の省略記号は除いて照合する）.
    for point in draft.keyPoints {
      let cleaned = point.hasSuffix("…") ? String(point.dropLast()) : point
      #expect(TextAnalysis.quoteExists(cleaned, in: body))
    }
  }

  @Test("抽出した数値は原文に存在する（仕様書 SM-03）")
  func factsAreGrounded() {
    let body = String(
      repeating: "売上は前年比で約35%増加し、導入企業は1200社に達しました。導入期間は平均3か月です。",
      count: 6
    )
    let draft = summarizer.summarize(makeInput(body: body))
    let validated = GroundingValidator.validate(facts: draft.facts, against: body)
    #expect(validated.report.rejectedFacts == 0)
  }
}
