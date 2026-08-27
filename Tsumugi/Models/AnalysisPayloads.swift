//
//  AnalysisPayloads.swift
//  Tsumugi
//
//  仕様書 8.3: 診断結果の内部表現. SwiftData の @Model に埋め込む値型をまとめる.
//

import Foundation

/// 要約が抽出した「主張」. 仕様書 SM-02 / SM-06.
struct Claim: Codable, Hashable, Identifiable, Sendable {
  var id: UUID = UUID()
  /// 記事が述べている主張.
  var claim: String
  /// その主張を支える根拠として記事が挙げているもの.
  var evidence: String
  /// 原文中の文字オフセット `[start, end]`. タップで原文へジャンプするために使う.
  var sourceOffset: [Int]?
  /// 根拠の質を表す短いキーワード（例: `primary_source`, `single_vendor`, `none`）.
  var evidenceQuality: String

  private enum CodingKeys: String, CodingKey {
    case claim, evidence
    case sourceOffset = "source_offset"
    case evidenceQuality = "evidence_quality"
  }

  init(claim: String, evidence: String, sourceOffset: [Int]? = nil, evidenceQuality: String = "unknown") {
    self.claim = claim
    self.evidence = evidence
    self.sourceOffset = sourceOffset
    self.evidenceQuality = evidenceQuality
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = UUID()
    self.claim = try container.decode(String.self, forKey: .claim)
    self.evidence = try container.decodeIfPresent(String.self, forKey: .evidence) ?? ""
    self.sourceOffset = try container.decodeIfPresent([Int].self, forKey: .sourceOffset)
    self.evidenceQuality = try container.decodeIfPresent(String.self, forKey: .evidenceQuality) ?? "unknown"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(claim, forKey: .claim)
    try container.encode(evidence, forKey: .evidence)
    try container.encodeIfPresent(sourceOffset, forKey: .sourceOffset)
    try container.encode(evidenceQuality, forKey: .evidenceQuality)
  }

  /// 根拠の質を日本語で説明する.
  var evidenceQualityLabel: String {
    switch evidenceQuality {
    case "primary_source": return "一次情報"
    case "official": return "公的機関"
    case "academic": return "論文・学術"
    case "single_vendor": return "単一ベンダー由来"
    case "secondary": return "二次まとめ"
    case "none": return "出典の提示なし"
    default: return "判定できません"
    }
  }
}

/// 記事中の数値・固有名詞・日付を構造化したもの. 仕様書 SM-03.
struct Fact: Codable, Hashable, Identifiable, Sendable {
  var id: UUID = UUID()
  /// `percentage` / `amount` / `date` / `organization` / `product` など.
  var type: String
  var value: String
  var context: String

  private enum CodingKeys: String, CodingKey {
    case type, value, context
  }

  init(type: String, value: String, context: String) {
    self.type = type
    self.value = value
    self.context = context
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = UUID()
    self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "other"
    self.value = try container.decode(String.self, forKey: .value)
    self.context = try container.decodeIfPresent(String.self, forKey: .context) ?? ""
  }

  var symbolName: String {
    switch type {
    case "percentage": return "percent"
    case "amount", "money": return "yensign"
    case "date": return "calendar"
    case "organization": return "building.2"
    case "person": return "person"
    case "product": return "shippingbox"
    case "regulation": return "building.columns"
    default: return "number"
    }
  }
}

/// 信頼度診断の 5 カテゴリ. 仕様書 4.4.1.
enum CredibilityCategory: String, Codable, CaseIterable, Sendable, Identifiable {
  case source
  case transparency
  case evidence
  case neutrality
  case corroboration

  var id: String { rawValue }

  /// 仕様書 4.4.1 の重み. 合計 1.0.
  var weight: Double {
    switch self {
    case .source: return 0.25
    case .transparency: return 0.20
    case .evidence: return 0.25
    case .neutrality: return 0.15
    case .corroboration: return 0.15
    }
  }

  var displayName: String {
    switch self {
    case .source: return "発信元の評価"
    case .transparency: return "透明性"
    case .evidence: return "論拠の質"
    case .neutrality: return "表現の中立性"
    case .corroboration: return "外部照合"
    }
  }

  var shortName: String {
    switch self {
    case .source: return "発信元"
    case .transparency: return "透明性"
    case .evidence: return "論拠"
    case .neutrality: return "中立性"
    case .corroboration: return "外部照合"
    }
  }

  var criteria: String {
    switch self {
    case .source: return "ドメインの評価, 運営者情報の有無, TLD, 既知の低品質サイトリストとの照合."
    case .transparency: return "著者名の明記, 著者プロフィール, 発行日・更新日, 修正履歴, 問い合わせ先."
    case .evidence: return "出典リンクの数と質, 引用の具体性, 数値の出所が明記されているか."
    case .neutrality: return "煽動的表現, 断定過多, 感情語の密度, クリックベイト見出し, 広告密度."
    case .corroboration: return "同一の主張を扱う他ソースとの一致・矛盾・未確認の判定."
    }
  }

  var symbolName: String {
    switch self {
    case .source: return "globe"
    case .transparency: return "eye"
    case .evidence: return "text.quote"
    case .neutrality: return "scalemass"
    case .corroboration: return "arrow.triangle.2.circlepath.circle"
    }
  }
}

/// 各カテゴリの根拠. 仕様書 9.3 の `rationale` に対応する.
struct RationaleEntry: Codable, Hashable, Identifiable, Sendable {
  var id: String { category.rawValue }
  var category: CredibilityCategory
  /// 判断理由（200 字以内）.
  var reason: String
  /// 本文からの引用（120 字以内）. 仕様書 10.6 により引用は必要最小限に制限する.
  var quote: String?
  /// 判定不能な項目は `false` とし, スコア計算から除外して重みを再正規化する（仕様書 9.6）.
  var isDetermined: Bool = true
}

/// 外部照合の結果 1 件. 仕様書 8.3 `corroborations`.
struct Corroboration: Codable, Hashable, Identifiable, Sendable {
  enum Verdict: String, Codable, Sendable {
    case supports
    case contradicts
    case unverified

    var displayName: String {
      switch self {
      case .supports: return "同傾向"
      case .contradicts: return "食い違い"
      case .unverified: return "未確認"
      }
    }

    var symbolName: String {
      switch self {
      case .supports: return "equal.circle.fill"
      case .contradicts: return "not.equal.circle.fill"
      case .unverified: return "questionmark.circle.fill"
      }
    }
  }

  var id: UUID = UUID()
  var title: String
  var url: String
  var publishedAt: Date?
  var verdict: Verdict
  var note: String

  private enum CodingKeys: String, CodingKey {
    case title, url, verdict, note
    case publishedAt = "published_at"
  }

  init(title: String, url: String, publishedAt: Date?, verdict: Verdict, note: String) {
    self.title = title
    self.url = url
    self.publishedAt = publishedAt
    self.verdict = verdict
    self.note = note
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = UUID()
    self.title = try container.decode(String.self, forKey: .title)
    self.url = try container.decode(String.self, forKey: .url)
    self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    self.verdict = try container.decodeIfPresent(Verdict.self, forKey: .verdict) ?? .unverified
    if let raw = try container.decodeIfPresent(String.self, forKey: .publishedAt) {
      self.publishedAt = DateParsing.parse(raw)
    } else {
      self.publishedAt = nil
    }
  }
}

/// 鮮度スコアの補正項. 仕様書 4.5.2.
struct FreshnessAdjustment: Codable, Hashable, Identifiable, Sendable {
  enum Reason: String, Codable, Sendable {
    case updateHistory = "update_history"
    case versionOutdated = "version_outdated"
    case yearOutdated = "year_outdated"
    case deprecated = "deprecated"
    case successorExists = "successor_exists"

    /// 仕様書 4.5.2 の補正値.
    var delta: Int {
      switch self {
      case .updateHistory: return 10
      case .versionOutdated: return -20
      case .yearOutdated: return -15
      case .deprecated: return -30
      case .successorExists: return -10
      }
    }

    var displayName: String {
      switch self {
      case .updateHistory: return "更新履歴あり"
      case .versionOutdated: return "バージョン言及の陳腐化"
      case .yearOutdated: return "年号の陳腐化"
      case .deprecated: return "廃止・非推奨の検出"
      case .successorExists: return "後続情報の存在"
      }
    }
  }

  var id: String { reason.rawValue }
  var reason: Reason
  var delta: Int
  /// 補正の根拠となった記述.
  var evidence: String?
}

/// 陳腐化している可能性のある具体的記述. 仕様書 4.5.3 `obsolete_points`.
struct ObsoletePoint: Codable, Hashable, Identifiable, Sendable {
  var id: UUID = UUID()
  var quote: String
  var reason: String

  private enum CodingKeys: String, CodingKey {
    case quote, reason
  }

  init(quote: String, reason: String) {
    self.quote = quote
    self.reason = reason
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = UUID()
    self.quote = try container.decode(String.self, forKey: .quote)
    self.reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
  }
}

/// 後続情報の候補. 仕様書 4.5.3 `successors`.
struct Successor: Codable, Hashable, Identifiable, Sendable {
  var id: UUID = UUID()
  var title: String
  var url: String
  var publishedAt: Date?
  var diffSummary: String

  private enum CodingKeys: String, CodingKey {
    case title, url
    case publishedAt = "published_at"
    case diffSummary = "diff_summary"
  }

  init(title: String, url: String, publishedAt: Date?, diffSummary: String) {
    self.title = title
    self.url = url
    self.publishedAt = publishedAt
    self.diffSummary = diffSummary
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = UUID()
    self.title = try container.decode(String.self, forKey: .title)
    self.url = try container.decode(String.self, forKey: .url)
    self.diffSummary = try container.decodeIfPresent(String.self, forKey: .diffSummary) ?? ""
    if let raw = try container.decodeIfPresent(String.self, forKey: .publishedAt) {
      self.publishedAt = DateParsing.parse(raw)
    } else {
      self.publishedAt = nil
    }
  }
}

/// AI の確信度. 仕様書 9.3 `confidence`.
enum AnalysisConfidence: String, Codable, CaseIterable, Sendable {
  case high
  case medium
  case low

  /// 仕様書 9.4 の収縮係数. 確信度が低いほどスコアを中央（50）へ寄せて断定を避ける.
  var shrinkFactor: Double {
    switch self {
    case .high: return 1.0
    case .medium: return 0.85
    case .low: return 0.6
    }
  }

  var displayName: String {
    switch self {
    case .high: return "確信度: 高"
    case .medium: return "確信度: 中"
    case .low: return "確信度: 低"
    }
  }
}
