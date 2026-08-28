//
//  IngestService.swift
//  Tsumugi
//
//  仕様書 6.2 の取り込みパイプラインを, SwiftData への永続化まで含めて実行する.
//
//  ingest → normalize_url → dedupe_check → extract → 診断 → persist → notification
//

import Foundation
import SwiftData
import Observation

/// 取り込み結果.
enum IngestResult: Sendable {
  /// 新規に保存した.
  case saved(itemID: UUID)
  /// 既に保存済みだった（仕様書 3.2）.
  case duplicate(itemID: UUID)
  /// URL として解釈できなかった.
  case invalidURL
}

/// 共有キューの取り込みと診断の実行を担当する.
@MainActor
@Observable
final class IngestService {

  /// 進行中の Item ID. 画面でスピナーを出すために使う.
  private(set) var inFlightItemIDs: Set<UUID> = []
  /// 直近に発生したエラーメッセージ.
  var lastErrorMessage: String?

  private let modelContext: ModelContext
  private let settings: SettingsStore
  private let extractor: ArticleExtractor
  private let sharedStore = SharedItemStore()
  private let notifications = NotificationService()

  init(modelContext: ModelContext, settings: SettingsStore, extractor: ArticleExtractor = ArticleExtractor()) {
    self.modelContext = modelContext
    self.settings = settings
    self.extractor = extractor
  }

  // MARK: - 共有キューの取り込み

  /// App Group のキューに溜まった共有ペイロードをすべて取り込む.
  /// アプリ起動時・フォアグラウンド復帰時に呼ぶ.
  @discardableResult
  func drainSharedQueue() async -> Int {
    let payloads = sharedStore.dequeueAll()
    guard !payloads.isEmpty else {
      refreshSavedIndex()
      return 0
    }

    var savedCount = 0
    for payload in payloads {
      let result = await ingest(payload)
      if case .saved = result { savedCount += 1 }
    }
    refreshSavedIndex()
    return savedCount
  }

  /// アプリ内から URL を直接保存する（共有シートを使わない経路）.
  @discardableResult
  func ingestURL(_ urlString: String, tags: [String] = [], note: String = "") async -> IngestResult {
    let payload = SharedPayload(url: urlString, userTags: tags, userNote: note)
    let result = await ingest(payload)
    refreshSavedIndex()
    return result
  }

  // MARK: - 取り込み本体

  /// 共有ペイロード 1 件を取り込む. 共有キューの処理とテストから使う.
  @discardableResult
  func ingest(_ payload: SharedPayload) async -> IngestResult {
    // 1. normalize_url（仕様書 16.2）.
    let canonicalHint = payload.page.meta["canonical"]
    guard let normalized = URLNormalizer.normalize(payload.url, canonicalHint: canonicalHint) else {
      lastErrorMessage = ExtractionError.invalidURL.localizedDescription
      return .invalidURL
    }

    // 2. dedupe_check（仕様書 3.2）.
    if let existing = findItem(urlHash: normalized.urlHash) {
      // 既存 Item にタグ・メモだけ追記して, 重複保存はしない.
      applyUserInput(payload, to: existing)
      try? modelContext.save()
      return .duplicate(itemID: existing.id)
    }

    // 3. ローカルへ即時保存する（仕様書 10.2: サーバ障害でも保存は失敗しない）.
    let item = Item(
      id: payload.id,
      originalURL: payload.url,
      canonicalURL: normalized.canonicalURL,
      urlHash: normalized.urlHash,
      title: payload.displayTitle,
      savedAt: payload.sharedAt
    )
    item.sourceApp = payload.sourceApp
    item.heroImageURL = payload.heroImageURL
    item.selectionText = payload.page.selection
    applyUserInput(payload, to: item)
    modelContext.insert(item)
    try? modelContext.save()

    // 4. 抽出と診断はバックグラウンドで進める.
    await process(item: item, payload: payload)
    return .saved(itemID: item.id)
  }

  /// 抽出 → 診断 → 永続化.
  private func process(item: Item, payload: SharedPayload) async {
    inFlightItemIDs.insert(item.id)
    defer { inFlightItemIDs.remove(item.id) }

    // --- extract ---
    item.status = .extracting
    try? modelContext.save()

    let article: ExtractedArticle
    do {
      article = try await extractor.extract(from: payload)
    } catch let error as ExtractionError {
      apply(extractor.minimalArticle(for: payload), to: item)
      switch error {
      case .unsupportedFormat:
        item.status = .unsupportedFormat
      default:
        item.status = .extractionFailed
      }
      item.failureReason = error.localizedDescription
      try? modelContext.save()
      return
    } catch {
      apply(extractor.minimalArticle(for: payload), to: item)
      item.status = .extractionFailed
      item.failureReason = error.localizedDescription
      try? modelContext.save()
      return
    }

    apply(article, to: item)

    // --- 要約（仕様書 12.2: 段階的診断の第 1 段） ---
    item.status = .analyzing
    try? modelContext.save()

    let pipeline = AnalysisPipeline(provider: settings.makeProvider())
    let input = makeInput(item: item, article: article)

    let summaryOutcome = await pipeline.runSummaryStage(input)
    applySummary(summaryOutcome, to: item, model: pipeline.modelIdentifier)

    if settings.stagedAnalysisEnabled {
      // 詳細診断は Item を開いた時に実行する.
      item.status = summaryOutcome.summary == nil ? .partial : .partial
      item.failureReason = summaryOutcome.partialFailures.first
      try? modelContext.save()
      return
    }

    // --- 信頼度・鮮度（第 2 段） ---
    let diagnosisOutcome = await pipeline.runDiagnosisStage(input)
    applyDiagnosis(diagnosisOutcome, to: item, article: article, model: pipeline.modelIdentifier)
    finalize(item: item, outcome: diagnosisOutcome)
  }

  // MARK: - 詳細診断（Item を開いた時に呼ぶ）

  /// 仕様書 12.2: 未読記事への課金を避けるため, 詳細診断は初回閲覧時に実行する.
  func runDeepAnalysisIfNeeded(for item: Item) async {
    guard item.credibility == nil || item.freshness == nil else { return }
    guard item.status.hasReadableBody || item.status == .partial else { return }
    guard !inFlightItemIDs.contains(item.id) else { return }
    guard let bodyText = item.bodyText, !bodyText.isEmpty else { return }

    // 仕様書 12.3: 無料枠を超えた場合は要約のみへフォールバックし, 機能を完全停止しない.
    guard !settings.hasExceededFreeQuota else {
      item.failureReason = "今月の AI 診断の無料枠（\(SettingsStore.freeMonthlyAnalysisLimit) 件）に達したため, 要約のみ表示しています."
      try? modelContext.save()
      return
    }

    inFlightItemIDs.insert(item.id)
    defer { inFlightItemIDs.remove(item.id) }

    item.status = .analyzing
    try? modelContext.save()

    let pipeline = AnalysisPipeline(provider: settings.makeProvider())
    let outcome = await pipeline.runDiagnosisStage(makeInput(item: item))
    applyDiagnosis(outcome, to: item, article: nil, model: pipeline.modelIdentifier)
    settings.recordAnalysis()
    finalize(item: item, outcome: outcome)
  }

  /// 仕様書 OT-06: 手動での再診断.
  func reanalyze(_ item: Item) async {
    guard let bodyText = item.bodyText, !bodyText.isEmpty else { return }
    inFlightItemIDs.insert(item.id)
    defer { inFlightItemIDs.remove(item.id) }

    item.status = .reanalyzing
    try? modelContext.save()

    let pipeline = AnalysisPipeline(provider: settings.makeProvider())
    let input = makeInput(item: item)
    let outcome = await pipeline.runFullPipeline(input)

    applySummary(outcome, to: item, model: pipeline.modelIdentifier)
    applyDiagnosis(outcome, to: item, article: nil, model: pipeline.modelIdentifier)
    settings.recordAnalysis()
    finalize(item: item, outcome: outcome)
  }

  // MARK: - 週次バッチ（仕様書 4.5.4）

  /// 保存済み Item の鮮度を再評価し, 陳腐化した件数を返す.
  /// 鮮度は時間の経過だけで変化するため, LLM を呼ばずに再計算できる.
  @discardableResult
  func refreshStalenessBatch() async -> Int {
    let descriptor = FetchDescriptor<Item>()
    guard let items = try? modelContext.fetch(descriptor) else { return 0 }

    var newlyStaleCount = 0
    for item in items {
      guard let report = item.freshness else { continue }
      let previousLabel = report.stalenessLabel

      let composed = FreshnessScoring.compute(
        topicClass: report.topicClass,
        publishedAt: item.publishedAt,
        updatedAt: item.updatedAtSource,
        adjustments: report.adjustments
      )
      report.freshnessScore = composed.score
      report.stalenessLabel = composed.label
      report.elapsedDays = composed.elapsedDays
      report.decayedScore = composed.decayedScore
      report.evaluatedAt = .now

      // stale → obsolete へ遷移した Item を数える.
      if previousLabel == .stale && composed.label == .obsolete { newlyStaleCount += 1 }
    }
    try? modelContext.save()

    if settings.weeklyDigestEnabled {
      let unreadCount = items.filter { !$0.isRead }.count
      await notifications.scheduleWeeklyDigest(staleCount: newlyStaleCount, unreadCount: unreadCount)
    }
    return newlyStaleCount
  }

  // MARK: - 永続化の補助

  private func makeInput(item: Item, article: ExtractedArticle? = nil) -> AnalysisInput {
    AnalysisInput(
      url: item.originalURL,
      canonicalURL: item.canonicalURL,
      title: item.title,
      author: item.author,
      siteName: item.siteName,
      publishedAt: item.publishedAt,
      updatedAt: item.updatedAtSource,
      language: item.language,
      bodyText: item.bodyText ?? "",
      headings: article?.headings ?? [],
      outboundLinks: article?.outboundLinks ?? [],
      affiliateLinkCount: article?.affiliateLinkCount ?? 0,
      authoritativeLinkCount: article?.authoritativeLinkCount ?? 0,
      selection: item.selectionText,
      outputLanguage: settings.outputLanguage,
      // ドメイン評価は必ず URL のホスト名で引く（表示名の siteName ではない）.
      domainReputation: DomainReputationTable.reputation(for: item.host),
      now: .now
    )
  }

  private func apply(_ article: ExtractedArticle, to item: Item) {
    if !article.title.isEmpty { item.title = article.title }
    item.author = article.author ?? item.author
    item.publishedAt = article.publishedAt
    item.updatedAtSource = article.updatedAt
    item.siteName = article.siteName ?? item.siteName
    item.language = article.language
    item.heroImageURL = article.heroImageURL ?? item.heroImageURL
    item.charCount = article.charCount
    item.readingMinutes = article.readingMinutes
    item.contentHash = article.contentHash
    // 仕様書 EX-07 / 10.6: noarchive 指定のサイトでも, 私的複製の範囲としてローカルには保持する.
    item.bodyText = article.bodyText.isEmpty ? nil : article.bodyText
  }

  private func applySummary(_ outcome: AnalysisOutcome, to item: Item, model: String) {
    guard let draft = outcome.summary else { return }

    let summary = Summary(
      tldr: draft.tldr,
      keyPoints: draft.keyPoints,
      detailed: draft.detailed,
      claims: draft.claims,
      facts: draft.facts,
      highlightFocused: draft.highlightFocused,
      model: model,
      language: settings.outputLanguage,
      wasSkipped: draft.wasSkipped
    )
    if let existing = item.summary { modelContext.delete(existing) }
    item.summary = summary

    // AI 提案タグを付与する（仕様書 LB-07）.
    for name in outcome.suggestedTags {
      attachTag(named: name, to: item, source: .ai)
    }
  }

  private func applyDiagnosis(_ outcome: AnalysisOutcome, to item: Item, article: ExtractedArticle?, model: String) {
    if let draft = outcome.credibility {
      if let existing = item.credibility { modelContext.delete(existing) }
      item.credibility = AnalysisPipeline.composeCredibility(
        draft: draft,
        strictness: settings.strictness,
        model: model
      )
    }

    if let draft = outcome.freshness {
      if let existing = item.freshness { modelContext.delete(existing) }
      item.freshness = AnalysisPipeline.composeFreshness(
        draft: draft,
        publishedAt: item.publishedAt,
        updatedAt: item.updatedAtSource
      )
    }
  }

  private func finalize(item: Item, outcome: AnalysisOutcome) {
    item.analyzedAt = .now
    item.failureReason = outcome.partialFailures.first
    item.status = outcome.partialFailures.isEmpty ? .completed : .partial
    try? modelContext.save()
    refreshSavedIndex()

    guard settings.notificationsEnabled else { return }
    let credibility = item.credibilityScore
    let freshness = item.freshnessScore
    let title = item.title
    let id = item.id
    Task {
      await notifications.notifyAnalysisCompleted(
        itemID: id,
        title: title,
        credibility: credibility,
        freshness: freshness
      )
    }
  }

  private func applyUserInput(_ payload: SharedPayload, to item: Item) {
    for name in payload.userTags {
      attachTag(named: name, to: item, source: .user)
    }
    if !payload.userNote.isEmpty {
      item.userNote = item.userNote.isEmpty ? payload.userNote : item.userNote + "\n" + payload.userNote
    }
  }

  /// 名前でタグを引き当て, 無ければ作って Item に紐づける.
  private func attachTag(named name: String, to item: Item, source: TagSource) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !item.tags.contains(where: { $0.name == trimmed }) else { return }

    var descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == trimmed })
    descriptor.fetchLimit = 1

    let tag: Tag
    if let existing = try? modelContext.fetch(descriptor).first {
      tag = existing
    } else {
      tag = Tag(name: trimmed, source: source)
      modelContext.insert(tag)
    }
    item.tags.append(tag)
  }

  private func findItem(urlHash: String) -> Item? {
    var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.urlHash == urlHash })
    descriptor.fetchLimit = 1
    return try? modelContext.fetch(descriptor).first
  }

  /// Share Extension が重複判定に使う索引を更新する（仕様書 3.2）.
  private func refreshSavedIndex() {
    var descriptor = FetchDescriptor<Item>()
    descriptor.propertiesToFetch = [\.urlHash]
    guard let items = try? modelContext.fetch(descriptor) else { return }
    sharedStore.writeSavedIndex(Set(items.map(\.urlHash)))
  }
}
