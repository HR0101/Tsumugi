//
//  SettingsStore.swift
//  Tsumugi
//
//  仕様書 S-09（設定画面）が扱う設定値の保管庫.
//  App Group の UserDefaults に保存し, Share Extension からも参照できるようにする.
//

import Foundation
import SwiftUI
import Observation

/// リーダービューの配色（仕様書 LB-06）. 名前は染めと紙の色から取っている.
enum ReaderTheme: String, Codable, CaseIterable, Sendable {
  case system
  case light
  case sepia
  case dark

  var displayName: String {
    switch self {
    case .system: return "端末に従う"
    case .light: return "白練"
    case .sepia: return "生成り"
    case .dark: return "墨"
    }
  }
}

/// リーダービューの本文書体（仕様書 LB-06）.
/// 長い日本語の文章は明朝体のほうが読み進めやすいため, 既定を明朝にしている.
enum ReaderTypeface: String, Codable, CaseIterable, Sendable {
  case mincho
  case gothic

  var displayName: String {
    switch self {
    case .mincho: return "明朝"
    case .gothic: return "ゴシック"
    }
  }

  /// 指定の大きさで本文用のフォントを返す.
  func font(size: CGFloat) -> Font {
    switch self {
    case .mincho: return .custom("HiraMinProN-W3", size: size, relativeTo: .body)
    case .gothic: return .system(size: size)
    }
  }

  /// 見出し用のフォント.
  func headingFont(size: CGFloat) -> Font {
    switch self {
    case .mincho: return .custom("HiraMinProN-W6", size: size, relativeTo: .title3)
    case .gothic: return .system(size: size, weight: .semibold)
    }
  }
}

/// 診断の厳しさ（仕様書 S-09）.
/// 仕様書 9.4 の収縮係数と同じ考え方で, 保守的にするほどスコアを中央へ寄せる.
enum AnalysisStrictness: String, Codable, CaseIterable, Sendable {
  case lenient
  case balanced
  case strict

  var displayName: String {
    switch self {
    case .lenient: return "ゆるやか"
    case .balanced: return "標準"
    case .strict: return "厳しめ"
    }
  }

  var detail: String {
    switch self {
    case .lenient: return "警告フラグによる減点を控えめにします."
    case .balanced: return "仕様どおりの重みで評価します."
    case .strict: return "出典不足や宣伝性をより強く減点します."
    }
  }

  /// フラグ減点に掛ける係数.
  var penaltyMultiplier: Double {
    switch self {
    case .lenient: return 0.6
    case .balanced: return 1.0
    case .strict: return 1.4
    }
  }
}

/// 使用する診断プロバイダ.
enum ProviderMode: String, Codable, CaseIterable, Sendable {
  /// API キーがあれば Claude API, 無ければオンデバイス（既定）.
  case automatic
  /// 常にオンデバイスのルールベース（仕様書 10.4 のオンデバイス処理モード）.
  case onDeviceOnly
  /// 常に Claude API.
  case claudeOnly

  var displayName: String {
    switch self {
    case .automatic: return "自動（キーがあれば Claude API）"
    case .onDeviceOnly: return "オンデバイスのみ"
    case .claudeOnly: return "Claude API のみ"
    }
  }
}

/// 設定値の保管庫.
@Observable
final class SettingsStore {

  /// UserDefaults のキー.
  private enum Key {
    static let outputLanguage = "settings.outputLanguage"
    static let strictness = "settings.strictness"
    static let providerMode = "settings.providerMode"
    static let stagedAnalysis = "settings.stagedAnalysis"
    static let notificationsEnabled = "settings.notificationsEnabled"
    static let weeklyDigestEnabled = "settings.weeklyDigestEnabled"
    static let readerTheme = "settings.readerTheme"
    static let readerTypeface = "settings.readerTypeface"
    static let readerFontSize = "settings.readerFontSize"
    static let readerLineSpacing = "settings.readerLineSpacing"
    static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
    static let monthlyAnalysisCount = "settings.monthlyAnalysisCount"
    static let monthlyAnalysisPeriod = "settings.monthlyAnalysisPeriod"
    static let modelPrefix = "settings.model."
  }

  /// 仕様書 12.3 の Free プランにおける月間 AI 診断上限.
  static let freeMonthlyAnalysisLimit = 10

  private let defaults: UserDefaults
  private let keychain: KeychainStore

  // MARK: - 設定値

  /// 要約の出力言語（仕様書 SM-04. 既定は日本語）.
  var outputLanguage: String {
    didSet { defaults.set(outputLanguage, forKey: Key.outputLanguage) }
  }

  var strictness: AnalysisStrictness {
    didSet { defaults.set(strictness.rawValue, forKey: Key.strictness) }
  }

  var providerMode: ProviderMode {
    didSet { defaults.set(providerMode.rawValue, forKey: Key.providerMode) }
  }

  /// 仕様書 12.2「段階的診断」: 保存時は抽出＋要約のみ, 詳細診断は初回閲覧時に行う.
  var stagedAnalysisEnabled: Bool {
    didSet { defaults.set(stagedAnalysisEnabled, forKey: Key.stagedAnalysis) }
  }

  var notificationsEnabled: Bool {
    didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
  }

  /// 仕様書 4.5.4: 週次の陳腐化ダイジェスト.
  var weeklyDigestEnabled: Bool {
    didSet { defaults.set(weeklyDigestEnabled, forKey: Key.weeklyDigestEnabled) }
  }

  var readerTheme: ReaderTheme {
    didSet { defaults.set(readerTheme.rawValue, forKey: Key.readerTheme) }
  }

  var readerTypeface: ReaderTypeface {
    didSet { defaults.set(readerTypeface.rawValue, forKey: Key.readerTypeface) }
  }

  var readerFontSize: Double {
    didSet { defaults.set(readerFontSize, forKey: Key.readerFontSize) }
  }

  var readerLineSpacing: Double {
    didSet { defaults.set(readerLineSpacing, forKey: Key.readerLineSpacing) }
  }

  var hasCompletedOnboarding: Bool {
    didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
  }

  /// 階層ごとのモデル ID（仕様書 9.1: 設定変更のみでモデルを差し替えられるようにする）.
  var modelIDs: [ModelTier: String] {
    didSet {
      for (tier, id) in modelIDs {
        defaults.set(id, forKey: Key.modelPrefix + tier.rawValue)
      }
    }
  }

  /// Claude API キー. Keychain に保管する（仕様書 10.3）.
  var apiKey: String? {
    didSet {
      do {
        if let apiKey, !apiKey.isEmpty {
          try keychain.save(apiKey, for: .analysisAPIKey)
        } else {
          try keychain.delete(.analysisAPIKey)
        }
        keychainError = nil
      } catch {
        keychainError = error.localizedDescription
      }
    }
  }

  /// Keychain 操作に失敗した場合のメッセージ. 設定画面に表示する.
  private(set) var keychainError: String?

  // MARK: - 初期化

  init(defaults: UserDefaults = AppGroup.defaults, keychain: KeychainStore = KeychainStore()) {
    self.defaults = defaults
    self.keychain = keychain

    self.outputLanguage = defaults.string(forKey: Key.outputLanguage) ?? "ja"
    self.strictness = AnalysisStrictness(rawValue: defaults.string(forKey: Key.strictness) ?? "") ?? .balanced
    self.providerMode = ProviderMode(rawValue: defaults.string(forKey: Key.providerMode) ?? "") ?? .automatic
    self.stagedAnalysisEnabled = defaults.object(forKey: Key.stagedAnalysis) as? Bool ?? true
    self.notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
    self.weeklyDigestEnabled = defaults.object(forKey: Key.weeklyDigestEnabled) as? Bool ?? true
    self.readerTheme = ReaderTheme(rawValue: defaults.string(forKey: Key.readerTheme) ?? "") ?? .system
    self.readerTypeface = ReaderTypeface(rawValue: defaults.string(forKey: Key.readerTypeface) ?? "") ?? .mincho
    self.readerFontSize = defaults.object(forKey: Key.readerFontSize) as? Double ?? 17
    self.readerLineSpacing = defaults.object(forKey: Key.readerLineSpacing) as? Double ?? 8
    self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)

    var models: [ModelTier: String] = [:]
    for tier in ModelTier.allCases {
      models[tier] = defaults.string(forKey: Key.modelPrefix + tier.rawValue) ?? tier.defaultModelID
    }
    self.modelIDs = models

    self.apiKey = keychain.read(.analysisAPIKey)
  }

  // MARK: - 派生値

  /// Claude API を使える状態か.
  var isClaudeConfigured: Bool {
    guard let apiKey else { return false }
    return apiKey.count >= 20
  }

  /// 実際に使用するプロバイダを決定する.
  func makeProvider(urlSession: URLSession = .shared) -> AnalysisProvider {
    switch providerMode {
    case .onDeviceOnly:
      return HeuristicAnalysisProvider()
    case .claudeOnly, .automatic:
      guard isClaudeConfigured, let apiKey else { return HeuristicAnalysisProvider() }
      return ClaudeAnalysisProvider(
        configuration: ClaudeConfiguration(apiKey: apiKey, models: modelIDs),
        urlSession: urlSession
      )
    }
  }

  /// 現在有効なプロバイダの表示名.
  var activeProviderName: String {
    makeProvider().displayName
  }

  // MARK: - 月間診断回数（仕様書 12.3）

  /// 今月の AI 診断実行回数.
  var monthlyAnalysisCount: Int {
    resetCounterIfNeeded()
    return defaults.integer(forKey: Key.monthlyAnalysisCount)
  }

  var remainingFreeAnalyses: Int {
    max(0, Self.freeMonthlyAnalysisLimit - monthlyAnalysisCount)
  }

  /// 無料枠を超えているか. 超過時は要約のみへ自動フォールバックする（仕様書 12.3）.
  var hasExceededFreeQuota: Bool {
    remainingFreeAnalyses == 0
  }

  /// 診断 1 件分を計上する.
  func recordAnalysis() {
    resetCounterIfNeeded()
    defaults.set(defaults.integer(forKey: Key.monthlyAnalysisCount) + 1, forKey: Key.monthlyAnalysisCount)
  }

  /// 月が変わっていればカウンタを 0 に戻す.
  private func resetCounterIfNeeded() {
    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents([.year, .month], from: .now)
    let period = "\(components.year ?? 0)-\(components.month ?? 0)"
    guard defaults.string(forKey: Key.monthlyAnalysisPeriod) != period else { return }
    defaults.set(period, forKey: Key.monthlyAnalysisPeriod)
    defaults.set(0, forKey: Key.monthlyAnalysisCount)
  }
}
