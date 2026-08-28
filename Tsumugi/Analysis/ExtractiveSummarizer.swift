//
//  ExtractiveSummarizer.swift
//  Tsumugi
//
//  仕様書 4.3: 3 段階の要約を, オンデバイスの抽出型要約で生成する.
//
//  原文に無い記述を作らない（＝ハルシネーションが原理的に起きない）ことを優先し,
//  本文中の文をそのまま選び出す方式を採る. 仕様書 9.6「Grounding 検証」の要求を
//  構造的に満たすアプローチ.
//

import Foundation

struct ExtractiveSummarizer: Sendable {

  private enum Constant {
    /// TL;DR に採用する最大文数.
    static let tldrSentenceCount = 2
    /// キーポイントの上限（仕様書 SM-01 は 3〜7 項目）.
    static let maxKeyPoints = 7
    static let minKeyPoints = 3
    /// 詳細要約の目標文字数（仕様書 SM-01 は 400〜800 字）.
    static let detailedTargetLength = 600
    static let detailedMaxLength = 800
    /// キーポイント 1 項目の最大長.
    static let keyPointMaxLength = 90
    /// 短すぎる文はノイズとして除外する.
    static let minSentenceLength = 15
    /// 長すぎる文はリスト連結の可能性が高いので除外する.
    static let maxSentenceLength = 220
    /// 抽出する主張の最大数.
    static let maxClaims = 5
    /// 抽出する事実の最大数.
    static let maxFacts = 12
  }

  /// 文とそのスコア.
  private struct ScoredSentence {
    var text: String
    var range: Range<Int>
    var score: Double
    var order: Int
  }

  /// 本文から 3 段階の要約を作る.
  func summarize(_ input: AnalysisInput) -> SummaryDraft {
    let body = input.bodyText

    // 仕様書 12.2: 短文記事は要約せず全文表示に委ねる.
    guard !input.isTooShortToSummarize else {
      return SummaryDraft(
        tldr: previewText(of: body, limit: 120),
        keyPoints: [],
        detailed: nil,
        claims: [],
        facts: FactExtractor.extract(from: body, limit: Constant.maxFacts),
        highlightFocused: nil,
        wasSkipped: true
      )
    }

    let scored = scoreSentences(in: body, title: input.title, headings: input.headings)
    guard !scored.isEmpty else {
      return SummaryDraft(
        tldr: previewText(of: body, limit: 120),
        keyPoints: [],
        detailed: nil,
        claims: [],
        facts: [],
        highlightFocused: nil
      )
    }

    let ranked = scored.sorted { $0.score > $1.score }

    return SummaryDraft(
      tldr: buildTLDR(from: ranked),
      keyPoints: buildKeyPoints(from: ranked),
      detailed: buildDetailed(from: ranked),
      claims: buildClaims(from: ranked, all: scored, input: input),
      facts: FactExtractor.extract(from: body, limit: Constant.maxFacts),
      highlightFocused: buildHighlightFocused(selection: input.selection, scored: scored)
    )
  }

  // MARK: - 文のスコアリング

  private func scoreSentences(in body: String, title: String, headings: [String]) -> [ScoredSentence] {
    let keywords = TextAnalysis.keywordFrequencies(in: body, limit: 30)
    let maxCount = Double(keywords.first?.count ?? 1)
    let keywordWeights = Dictionary(uniqueKeysWithValues: keywords.map { ($0.word, Double($0.count) / maxCount) })

    let titleWords = Set(TextAnalysis.words(in: title + " " + headings.joined(separator: " ")).filter { $0.count >= 2 })

    let sentences = TextAnalysis.sentencesWithOffsets(in: body)
    let total = max(sentences.count, 1)

    return sentences.enumerated().compactMap { index, element in
      let text = element.sentence
      // 見出し行（Markdown 風の印を付けた行）は要約対象から外す.
      guard !text.hasPrefix("#") else { return nil }
      let plain = text.hasPrefix("・") ? String(text.dropFirst()) : text
      guard plain.count >= Constant.minSentenceLength, plain.count <= Constant.maxSentenceLength else { return nil }

      var score = 0.0

      // 1. 内容語の重要度の合計.
      for word in TextAnalysis.words(in: plain) {
        score += keywordWeights[word] ?? 0
      }

      // 2. タイトル・見出しと語を共有する文を優遇する.
      let shared = TextAnalysis.words(in: plain).filter { titleWords.contains($0) }.count
      score += Double(shared) * 0.6

      // 3. 冒頭の文はリード文である可能性が高い.
      let positionRatio = Double(index) / Double(total)
      if positionRatio < 0.15 { score += 1.6 } else if positionRatio > 0.9 { score += 0.4 }

      // 4. 数値を含む文は具体的な情報を持つ.
      if plain.rangeOfCharacter(from: .decimalDigits) != nil { score += 0.8 }

      // 5. 極端に短い / 長い文はわずかに減点する.
      let lengthPenalty = abs(Double(plain.count) - 60.0) / 200.0
      score -= lengthPenalty

      return ScoredSentence(text: plain, range: element.range, score: score, order: index)
    }
  }

  // MARK: - 各粒度の組み立て

  private func buildTLDR(from ranked: [ScoredSentence]) -> String {
    let selected = Array(ranked.prefix(Constant.tldrSentenceCount)).sorted { $0.order < $1.order }
    let joined = selected.map(\.text).joined(separator: " ")
    return joined.isEmpty ? "要約を生成できませんでした." : joined
  }

  private func buildKeyPoints(from ranked: [ScoredSentence]) -> [String] {
    var selected: [ScoredSentence] = []
    var usedSignatures = Set<String>()

    for sentence in ranked {
      guard selected.count < Constant.maxKeyPoints else { break }
      // 似た内容の文を弾くため, 正規化した先頭 20 文字を署名として使う.
      let signature = String(TextAnalysis.normalizeForMatching(sentence.text).prefix(20))
      guard !signature.isEmpty, usedSignatures.insert(signature).inserted else { continue }
      selected.append(sentence)
    }

    guard selected.count >= Constant.minKeyPoints || !selected.isEmpty else { return [] }

    return selected
      .sorted { $0.order < $1.order }
      .map { truncate($0.text, to: Constant.keyPointMaxLength) }
  }

  private func buildDetailed(from ranked: [ScoredSentence]) -> String? {
    var selected: [ScoredSentence] = []
    var length = 0
    for sentence in ranked {
      guard length < Constant.detailedTargetLength else { break }
      guard length + sentence.text.count <= Constant.detailedMaxLength else { continue }
      selected.append(sentence)
      length += sentence.text.count
    }
    guard !selected.isEmpty else { return nil }
    return selected.sorted { $0.order < $1.order }.map(\.text).joined(separator: "")
  }

  /// 仕様書 SM-07: ハイライト（共有時の選択テキスト）を重点化した要約.
  private func buildHighlightFocused(selection: String?, scored: [ScoredSentence]) -> String? {
    guard let selection, selection.count >= 10 else { return nil }
    let normalizedSelection = TextAnalysis.normalizeForMatching(selection)

    // 選択テキストと語を共有する文を本文から集める.
    let related = scored
      .filter { sentence in
        let normalized = TextAnalysis.normalizeForMatching(sentence.text)
        return normalized.contains(String(normalizedSelection.prefix(12)))
          || normalizedSelection.contains(String(normalized.prefix(12)))
      }
      .sorted { $0.order < $1.order }
      .prefix(3)

    guard !related.isEmpty else { return nil }
    return "選択箇所の周辺: " + related.map(\.text).joined(separator: " ")
  }

  /// 仕様書 SM-02 / SM-06: 主張と根拠を分離し, 原文オフセットを紐付ける.
  private func buildClaims(from ranked: [ScoredSentence], all: [ScoredSentence], input: AnalysisInput) -> [Claim] {
    let byOrder = Dictionary(grouping: all, by: \.order).compactMapValues(\.first)

    // 数値または断定表現を含む文を主張の候補とする.
    let candidates = ranked.filter { sentence in
      sentence.text.rangeOfCharacter(from: .decimalDigits) != nil || containsAssertion(sentence.text)
    }

    let quality = evidenceQuality(for: input)

    return candidates.prefix(Constant.maxClaims).map { sentence in
      let evidence = findEvidence(after: sentence, in: byOrder) ?? "記事内に, この主張を裏付ける明示的な出典は見つかりませんでした."
      return Claim(
        claim: truncate(sentence.text, to: 120),
        evidence: truncate(evidence, to: 120),
        sourceOffset: [sentence.range.lowerBound, sentence.range.upperBound],
        evidenceQuality: quality
      )
    }
  }

  /// 主張の直後の文が出典を示していれば根拠として採用する.
  private func findEvidence(after sentence: ScoredSentence, in byOrder: [Int: ScoredSentence]) -> String? {
    for offset in 1...2 {
      guard let next = byOrder[sentence.order + offset] else { continue }
      let hits = TextAnalysis.occurrences(of: HeuristicSignals.citationTerms, in: next.text)
      if !hits.isEmpty { return next.text }
    }
    // 同じ文の中に出典表現があるケース.
    if !TextAnalysis.occurrences(of: HeuristicSignals.citationTerms, in: sentence.text).isEmpty {
      return sentence.text
    }
    return nil
  }

  private func evidenceQuality(for input: AnalysisInput) -> String {
    if input.authoritativeLinkCount > 0 { return "primary_source" }
    if input.outboundLinks.count >= 3 { return "secondary" }
    if input.outboundLinks.isEmpty { return "none" }
    return "single_vendor"
  }

  private func containsAssertion(_ text: String) -> Bool {
    let endings = ["である", "だ。", "した。", "する。", "となる", "と主張", "とされる", "と述べた", "だろう"]
    return endings.contains { text.contains($0) }
  }

  private func truncate(_ text: String, to limit: Int) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(limit - 1)) + "…"
  }

  /// 要約を作れなかった場合に本文の冒頭を見せる.
  /// 本文には Markdown 風の見出し記号が入っているため, 見出し行は除いてから切り出す.
  private func previewText(of body: String, limit: Int) -> String {
    let paragraphs = body
      .components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    let joined = paragraphs.joined(separator: " ")
    return joined.isEmpty ? truncate(body, to: limit) : truncate(joined, to: limit)
  }
}
