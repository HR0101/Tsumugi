//
//  HeuristicAnalysisProvider.swift
//  Tsumugi
//
//  オンデバイスのルールベース診断プロバイダ.
//
//  仕様書 4.4.1 の判定方式のうち「ルールベース + DB 参照」「辞書」に相当する部分を実装する.
//  外部照合（Web 検索が必要な項目）は原理的に判定できないため, 推測せずに
//  「判定できませんでした」として重みを再正規化する（仕様書 9.6「不明の明示」）.
//
//  API キーが未設定でもアプリが機能停止しないようにするための既定プロバイダ.
//

import Foundation

struct HeuristicAnalysisProvider: AnalysisProvider {

  let displayName = "オンデバイス診断（ルールベース）"
  let modelIdentifier = "heuristic-v1"
  let requiresNetwork = false

  private let summarizer = ExtractiveSummarizer()

  // MARK: - 要約

  func summarize(_ input: AnalysisInput) async throws -> SummaryDraft {
    summarizer.summarize(input)
  }

  // MARK: - 信頼度診断（仕様書 4.4）

  func assessCredibility(_ input: AnalysisInput) async throws -> CredibilityDraft {
    let body = input.bodyText
    let reputation = input.domainReputation ?? DomainReputationTable.reputation(for: input.host)

    var scores: [CredibilityCategory: Int] = [:]
    var rationale: [RationaleEntry] = []
    var flags: Set<CredibilityFlag> = []

    // --- 1. 発信元の評価 ---
    let sourceResult = evaluateSource(input: input, reputation: reputation)
    scores[.source] = sourceResult.score
    rationale.append(sourceResult.rationale)

    // --- 2. 透明性 ---
    let transparencyResult = evaluateTransparency(input: input, body: body)
    scores[.transparency] = transparencyResult.score
    rationale.append(transparencyResult.rationale)
    flags.formUnion(transparencyResult.flags)

    // --- 3. 論拠の質 ---
    let evidenceResult = evaluateEvidence(input: input, body: body)
    scores[.evidence] = evidenceResult.score
    rationale.append(evidenceResult.rationale)
    flags.formUnion(evidenceResult.flags)

    // --- 4. 表現の中立性 ---
    let neutralityResult = evaluateNeutrality(input: input, body: body)
    scores[.neutrality] = neutralityResult.score
    rationale.append(neutralityResult.rationale)
    flags.formUnion(neutralityResult.flags)

    // --- 5. 外部照合 ---
    // Web 検索を行わないため判定できない. 推測を避け, スコアには含めない.
    rationale.append(
      RationaleEntry(
        category: .corroboration,
        reason: "オンデバイス診断では他ソースとの照合を行わないため, この項目は判定していません. 総合スコアは残り 4 項目の重みを再正規化して算出しています.",
        quote: nil,
        isDetermined: false
      )
    )

    // --- YMYL / 風刺の判定 ---
    flags.formUnion(domainAndDomainSpecificFlags(input: input, body: body))

    let confidence = estimateConfidence(input: input, body: body)

    return CredibilityDraft(
      scores: scores,
      rationale: rationale,
      flags: Array(flags).sorted { $0.rawValue < $1.rawValue },
      corroborations: [],
      confidence: confidence
    )
  }

  // MARK: - 鮮度診断（仕様書 4.5）

  func assessFreshness(_ input: AnalysisInput) async throws -> FreshnessDraft {
    let topic = TopicClassifier.classify(title: input.title, headings: input.headings, body: input.bodyText)
    var adjustments: [FreshnessAdjustment] = []

    // 更新履歴あり: +10
    if let updatedAt = input.updatedAt {
      adjustments.append(
        FreshnessAdjustment(
          reason: .updateHistory,
          delta: FreshnessAdjustment.Reason.updateHistory.delta,
          evidence: "更新日 \(Self.dateFormatter.string(from: updatedAt)) が明記されています."
        )
      )
    }

    // 年号の陳腐化: −15
    if let staleYear = staleYearMention(input: input) {
      adjustments.append(
        FreshnessAdjustment(
          reason: .yearOutdated,
          delta: FreshnessAdjustment.Reason.yearOutdated.delta,
          evidence: "見出しに「\(staleYear)」という, 現在より 2 年以上前の年号が含まれます."
        )
      )
    }

    // バージョン言及の陳腐化: −20
    // 現行バージョンを照会できないため, 「バージョン番号への言及がある」かつ
    // 「更新の速い分野で 2 年以上経過している」場合に限って適用する.
    if let version = outdatedVersionMention(input: input, topic: topic) {
      adjustments.append(
        FreshnessAdjustment(
          reason: .versionOutdated,
          delta: FreshnessAdjustment.Reason.versionOutdated.delta,
          evidence: "「\(version)」への言及があります. 公開から 2 年以上経過しており, 前提が変わっている可能性があります."
        )
      )
    }

    return FreshnessDraft(
      topicClass: topic,
      adjustments: adjustments,
      obsoletePoints: obsoletePoints(input: input, topic: topic),
      // 後続情報の検索には Web 検索が必要なため, オンデバイス診断では提示しない.
      successors: []
    )
  }

  // MARK: - タグ提案（仕様書 LB-07）

  func suggestTags(_ input: AnalysisInput) async throws -> [String] {
    let topic = TopicClassifier.classify(title: input.title, headings: input.headings, body: input.bodyText)
    let keywords = TextAnalysis.keywordFrequencies(in: input.title + "\n" + input.bodyText, limit: 12)

    var tags: [String] = [topic.displayName]
    for keyword in keywords where tags.count < 5 {
      // 1 文字の語と, トピック名と重複する語は除く.
      guard keyword.word.count >= 2, keyword.count >= 2, !tags.contains(keyword.word) else { continue }
      tags.append(keyword.word)
    }
    return tags
  }

  // MARK: - カテゴリ別の評価

  private struct CategoryResult {
    var score: Int
    var rationale: RationaleEntry
    var flags: Set<CredibilityFlag> = []
  }

  /// 1. 発信元の評価（重み 0.25）.
  private func evaluateSource(input: AnalysisInput, reputation: DomainReputation) -> CategoryResult {
    var score = Double(reputation.baseScore)
    var notes: [String] = ["\(reputation.category.displayName)として評価しました."]

    if reputation.hasEditorialPolicy {
      score += 4
      notes.append("編集方針・運営者情報の公開が確認されています.")
    }

    // 数字とハイフンが多い機械生成的なホスト名は減点する.
    let host = input.host
    let digitCount = host.filter(\.isNumber).count
    let hyphenCount = host.filter { $0 == "-" }.count
    if digitCount >= 3 || hyphenCount >= 3 {
      score -= 8
      notes.append("機械的に生成されたようなホスト名です.")
    }

    notes.append(reputation.notes)

    return CategoryResult(
      score: CredibilityScoring.clampToScore(score),
      rationale: RationaleEntry(
        category: .source,
        reason: truncate(notes.joined(separator: " "), to: 200),
        quote: host.isEmpty ? nil : host
      )
    )
  }

  /// 2. 透明性（重み 0.20）.
  private func evaluateTransparency(input: AnalysisInput, body: String) -> CategoryResult {
    let base = 35.0
    var score = base
    var notes: [String] = []
    var flags: Set<CredibilityFlag> = []

    if let author = input.author, !author.isEmpty {
      score += 25
      notes.append("著者「\(author)」が明記されています.")
    } else {
      flags.insert(.noAuthor)
      notes.append("著者名が確認できません.")
    }

    if let publishedAt = input.publishedAt {
      score += 20
      notes.append("発行日 \(Self.dateFormatter.string(from: publishedAt)) が明記されています.")
    } else {
      flags.insert(.noDate)
      notes.append("発行日を特定できませんでした.")
    }

    if input.updatedAt != nil {
      score += 10
      notes.append("更新日も併記されています.")
    }

    let transparencyHits = TextAnalysis.occurrences(of: HeuristicSignals.transparencyTerms, in: body)
    if !transparencyHits.isEmpty {
      score += 10
      notes.append("運営者情報や問い合わせ先への言及があります.")
    }

    return CategoryResult(
      score: CredibilityScoring.clampToScore(score),
      rationale: RationaleEntry(
        category: .transparency,
        reason: truncate(notes.joined(separator: " "), to: 200),
        quote: findQuote(for: HeuristicSignals.transparencyTerms, in: body)
      ),
      flags: flags
    )
  }

  /// 3. 論拠の質（重み 0.25）.
  private func evaluateEvidence(input: AnalysisInput, body: String) -> CategoryResult {
    var score = 30.0
    var notes: [String] = []
    var flags: Set<CredibilityFlag> = []

    let outboundCount = input.outboundLinks.count
    let authoritativeCount = input.authoritativeLinkCount

    // 外部リンク数（1 件 4 点, 上限 32 点）.
    score += min(Double(outboundCount), 8.0) * 4.0
    // 一次情報・公的機関・学術へのリンクは重く評価する（1 件 8 点, 上限 24 点）.
    score += min(Double(authoritativeCount), 3.0) * 8.0

    let citationHits = TextAnalysis.occurrences(of: HeuristicSignals.citationTerms, in: body)
    if !citationHits.isEmpty {
      score += 10
      notes.append("出典を示す表現が \(citationHits.values.reduce(0, +)) 箇所あります.")
    }

    if outboundCount == 0 {
      score -= 12
      flags.insert(.noCitation)
      notes.append("外部への出典リンクが 1 件も見つかりませんでした.")
    } else {
      notes.append("外部リンク \(outboundCount) 件のうち, 一次情報・公的機関・学術ドメインは \(authoritativeCount) 件です.")
      if authoritativeCount == 0 && outboundCount < 3 && citationHits.isEmpty {
        flags.insert(.noCitation)
        notes.append("主要な数値の出所が確認できません.")
      }
    }

    return CategoryResult(
      score: CredibilityScoring.clampToScore(score),
      rationale: RationaleEntry(
        category: .evidence,
        reason: truncate(notes.joined(separator: " "), to: 200),
        quote: findQuote(for: HeuristicSignals.citationTerms, in: body)
      ),
      flags: flags
    )
  }

  /// 4. 表現の中立性（重み 0.15）.
  private func evaluateNeutrality(input: AnalysisInput, body: String) -> CategoryResult {
    var score = 88.0
    var notes: [String] = []
    var flags: Set<CredibilityFlag> = []

    // 文字数あたりの扇動語密度で減点する.
    let sensationalHits = TextAnalysis.occurrences(of: HeuristicSignals.sensationalTerms, in: body)
    let sensationalCount = sensationalHits.values.reduce(0, +)
    let per1000 = Double(sensationalCount) / max(Double(body.count) / 1_000.0, 1.0)
    score -= min(per1000 * 12.0, 30.0)

    // 見出しのクリックベイト表現.
    let clickbaitHits = TextAnalysis.occurrences(of: HeuristicSignals.clickbaitPatterns, in: input.title)
    if !clickbaitHits.isEmpty {
      score -= 12
      notes.append("見出しに扇情的な表現が含まれます.")
    }

    if per1000 >= 1.0 || !clickbaitHits.isEmpty {
      flags.insert(.sensational)
      notes.append("断定的・感情に訴える語が \(sensationalCount) 箇所見つかりました.")
    } else if sensationalCount > 0 {
      notes.append("扇動的な語は \(sensationalCount) 箇所にとどまります.")
    } else {
      notes.append("扇動的な表現は見つかりませんでした.")
    }

    // 留保表現があるほど中立的と評価する.
    let hedgingCount = TextAnalysis.occurrences(of: HeuristicSignals.hedgingTerms, in: body).values.reduce(0, +)
    if hedgingCount >= 3 {
      score += 5
      notes.append("「とされる」「可能性がある」など, 断定を避ける表現が使われています.")
    }

    // 広告・PR 表記.
    let sponsoredHits = TextAnalysis.occurrences(of: HeuristicSignals.sponsoredTerms, in: body + " " + input.title)
    if !sponsoredHits.isEmpty {
      flags.insert(.sponsored)
      score -= 10
      notes.append("広告・PR である旨の表記があります.")
    }

    // アフィリエイトリンク密度.
    if input.affiliateLinkCount >= 3 {
      flags.insert(.affiliateHeavy)
      score -= 10
      notes.append("アフィリエイトと推定されるリンクが \(input.affiliateLinkCount) 件あります.")
    }

    return CategoryResult(
      score: CredibilityScoring.clampToScore(score),
      rationale: RationaleEntry(
        category: .neutrality,
        reason: truncate(notes.joined(separator: " "), to: 200),
        quote: findQuote(for: HeuristicSignals.sensationalTerms, in: body)
          ?? findQuote(for: HeuristicSignals.sponsoredTerms, in: body)
      ),
      flags: flags
    )
  }

  /// ドメイン単位・分野単位のフラグ.
  private func domainAndDomainSpecificFlags(input: AnalysisInput, body: String) -> Set<CredibilityFlag> {
    var flags: Set<CredibilityFlag> = []
    let haystack = input.title + "\n" + body

    if HeuristicSignals.satireDomains.contains(input.host) {
      flags.insert(.satire)
    }

    let medicalHits = TextAnalysis.occurrences(of: HeuristicSignals.medicalTerms, in: haystack).values.reduce(0, +)
    if medicalHits >= 3 { flags.insert(.medicalYMYL) }

    let financialHits = TextAnalysis.occurrences(of: HeuristicSignals.financialTerms, in: haystack).values.reduce(0, +)
    if financialHits >= 3 { flags.insert(.financialYMYL) }

    // AI 自動生成の疑いは誤判定の影響が大きいため, 複数の手がかりが揃った場合のみ立てる.
    let aiHints = TextAnalysis.occurrences(of: HeuristicSignals.aiGeneratedHints, in: body).count
    if aiHints >= 3 && input.author == nil && input.outboundLinks.isEmpty {
      flags.insert(.aiGeneratedSuspect)
    }

    return flags
  }

  /// 仕様書 9.2 ルール 3: 判断できない項目は推測せず confidence を下げる.
  private func estimateConfidence(input: AnalysisInput, body: String) -> AnalysisConfidence {
    if body.count < 400 { return .low }
    if input.author == nil && input.publishedAt == nil { return .low }
    if input.author != nil && input.publishedAt != nil && input.outboundLinks.count >= 3 && body.count >= 1_200 {
      // 外部照合を行っていない以上, 最高の確信度は付けない.
      return .medium
    }
    return body.count >= 800 ? .medium : .low
  }

  // MARK: - 鮮度の補助判定

  /// 見出しに含まれる, 現在より 2 年以上前の年号を返す.
  private func staleYearMention(input: AnalysisInput) -> String? {
    let haystack = input.title + "\n" + input.headings.joined(separator: "\n")
    let currentYear = Calendar(identifier: .gregorian).component(.year, from: input.now)

    guard let regex = HTMLText.regex(#"(20\d{2})\s*年"#, options: []) else { return nil }
    let nsHaystack = haystack as NSString
    for match in regex.matches(in: haystack, range: NSRange(location: 0, length: nsHaystack.length)) {
      let yearText = nsHaystack.substring(with: match.range(at: 1))
      guard let year = Int(yearText), currentYear - year >= 2 else { continue }
      return nsHaystack.substring(with: match.range)
    }
    return nil
  }

  /// 陳腐化している可能性のあるバージョン言及を返す.
  private func outdatedVersionMention(input: AnalysisInput, topic: TopicClass) -> String? {
    // 更新の速い分野に限る.
    guard [TopicClass.ai, .software, .hardware].contains(topic) else { return nil }
    guard let baseDate = input.updatedAt ?? input.publishedAt else { return nil }
    guard DateParsing.daysBetween(baseDate, and: input.now) >= 730 else { return nil }

    guard let regex = HTMLText.regex(#"(?:v|ver\.?|バージョン)\s?\d+(?:\.\d+){1,2}"#, options: [.caseInsensitive]) else { return nil }
    let body = input.bodyText as NSString
    guard let match = regex.firstMatch(in: input.bodyText, range: NSRange(location: 0, length: body.length)) else { return nil }
    return body.substring(with: match.range)
  }

  /// 陳腐化している可能性のある具体的記述を抜き出す（仕様書 4.5.3）.
  private func obsoletePoints(input: AnalysisInput, topic: TopicClass) -> [ObsoletePoint] {
    guard let halfLife = topic.halfLifeDays else { return [] }
    guard let baseDate = input.updatedAt ?? input.publishedAt else { return [] }
    let elapsed = DateParsing.daysBetween(baseDate, and: input.now)
    // 半減期を超えていない記事には陳腐化ポイントを立てない.
    guard elapsed > halfLife else { return [] }

    let elapsedYears = Double(elapsed) / 365.0
    var points: [ObsoletePoint] = []

    for sentence in TextAnalysis.sentences(in: input.bodyText) {
      guard points.count < 3 else { break }
      // 執筆時点を前提にした表現と, 具体的な数値の両方を含む文だけを対象にする.
      let hasTimeRelative = !TextAnalysis.occurrences(of: HeuristicSignals.timeRelativeTerms, in: sentence).isEmpty
      let hasNumber = sentence.rangeOfCharacter(from: .decimalDigits) != nil
      guard hasTimeRelative, hasNumber, sentence.count >= 20 else { continue }

      points.append(
        ObsoletePoint(
          // 仕様書 10.6: 引用は 1 箇所 120 字以内に制限する.
          quote: truncate(sentence, to: 120),
          reason: "「執筆時点」を前提にした記述です. 公開から約 \(String(format: "%.1f", elapsedYears)) 年が経過しており, \(topic.displayName)分野の半減期 \(halfLife) 日を超えているため, 前提が変わっている可能性があります."
        )
      )
    }

    return points
  }

  // MARK: - 補助

  /// 辞書に一致した箇所を含む文を, 根拠の引用として 1 つ返す（120 字以内）.
  private func findQuote(for dictionary: [String], in body: String) -> String? {
    for sentence in TextAnalysis.sentences(in: body) {
      guard sentence.count >= 10 else { continue }
      if dictionary.contains(where: { sentence.localizedCaseInsensitiveContains($0) }) {
        return truncate(sentence, to: 120)
      }
    }
    return nil
  }

  private func truncate(_ text: String, to limit: Int) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(limit - 1)) + "…"
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yyyy/MM/dd"
    return formatter
  }()
}
