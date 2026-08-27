//
//  AnalysisProvider.swift
//  Tsumugi
//
//  仕様書 9.1:「プロバイダ抽象化レイヤを設け, モデル差し替えを設定変更のみで可能にする」.
//
//  この protocol を満たす実装を差し替えることで,
//  オンデバイスのルールベース診断（HeuristicAnalysisProvider）と
//  LLM による診断（ClaudeAnalysisProvider）を同じ呼び出し口で扱える.
//

import Foundation

/// 診断に必要な入力一式.
struct AnalysisInput: Sendable {
  var url: String
  var canonicalURL: String
  var title: String
  var author: String?
  var siteName: String?
  var publishedAt: Date?
  var updatedAt: Date?
  var language: String?
  var bodyText: String
  var headings: [String]
  var outboundLinks: [ExtractedArticle.Link]
  var affiliateLinkCount: Int
  var authoritativeLinkCount: Int
  /// ユーザーが共有時に選択していたテキスト（仕様書 SM-07）.
  var selection: String?
  /// 出力言語（仕様書 SM-04）.
  var outputLanguage: String
  /// 既知のドメイン評価（仕様書 9.2 のプロンプト変数 `domain_reputation`）.
  var domainReputation: DomainReputation?
  /// 診断実行時刻. 鮮度計算の基準になる.
  var now: Date

  /// ホスト名（`www.` 除去済み）.
  var host: String {
    guard let host = URL(string: canonicalURL)?.host()?.lowercased() else { return "" }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  /// 本文が短すぎて要約を省略すべきか（仕様書 12.2）.
  var isTooShortToSummarize: Bool { bodyText.count < 500 }
}

/// 要約プロバイダが返す下書き.
struct SummaryDraft: Sendable {
  var tldr: String
  var keyPoints: [String]
  var detailed: String?
  var claims: [Claim]
  var facts: [Fact]
  var highlightFocused: String?
  var wasSkipped: Bool = false
}

/// 信頼度診断プロバイダが返す下書き.
/// 総合スコアはここでは決めず, 必ず `CredibilityScoring.compose` で合成する.
struct CredibilityDraft: Sendable {
  /// 判定できたカテゴリのスコアのみを入れる. 判定不能な項目は入れない（仕様書 9.6）.
  var scores: [CredibilityCategory: Int]
  var rationale: [RationaleEntry]
  var flags: [CredibilityFlag]
  var corroborations: [Corroboration]
  var confidence: AnalysisConfidence
}

/// 鮮度診断プロバイダが返す下書き.
/// 時間減衰の計算はここでは行わず, 必ず `FreshnessScoring.compute` で合成する.
struct FreshnessDraft: Sendable {
  var topicClass: TopicClass
  var adjustments: [FreshnessAdjustment]
  var obsoletePoints: [ObsoletePoint]
  var successors: [Successor]
}

/// 診断プロバイダの共通インターフェース.
protocol AnalysisProvider: Sendable {
  /// 設定画面に表示する名前.
  var displayName: String { get }
  /// 診断結果に記録するモデル識別子（仕様書 14: モデル更新による非互換への対策）.
  var modelIdentifier: String { get }
  /// ネットワークを必要とするか.
  var requiresNetwork: Bool { get }

  /// 要約を生成する（仕様書 4.3）.
  func summarize(_ input: AnalysisInput) async throws -> SummaryDraft
  /// 信頼度を診断する（仕様書 4.4）.
  func assessCredibility(_ input: AnalysisInput) async throws -> CredibilityDraft
  /// トピック分類と陳腐化ポイントを判定する（仕様書 4.5）.
  func assessFreshness(_ input: AnalysisInput) async throws -> FreshnessDraft
  /// タグを提案する（仕様書 LB-07）.
  func suggestTags(_ input: AnalysisInput) async throws -> [String]
}

/// 診断処理のエラー.
enum AnalysisError: LocalizedError {
  case notConfigured
  case timedOut
  case providerFailure(message: String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "AI プロバイダが設定されていません. 設定画面から API キーを登録してください."
    case .timedOut:
      return "診断が制限時間内に終わりませんでした. 部分的な結果のみ保存しています."
    case .providerFailure(let message):
      return "診断に失敗しました: \(message)"
    case .invalidResponse:
      return "診断結果を解釈できませんでした. しばらく待って再診断してください."
    }
  }
}
