//
//  SettingsStore.swift
//  Tsumugi
//
//  仕様書 S-09（設定画面）が扱う設定値の保管庫.
//  App Group の UserDefaults に保存し, Share Extension からも参照できるようにする.
//

import Foundation
import Security
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
  /// Private Cloud Compute → オンデバイス → ルールベースの順に, 使えるものを使う（既定）.
  case automatic
  /// Private Cloud Compute だけを使う. 使えなければルールベースで判定し, その旨を表示する.
  case privateCloud
  /// 端末内の Apple Intelligence だけを使い, 記事を端末の外へ送らない.
  case onDeviceModel
  /// AI を使わず, ルールベース診断だけを使う（仕様書 10.4 のオンデバイス処理モード）.
  /// 以前の「オンデバイスのみ」の設定値をそのまま引き継ぐため, rawValue は旧名のままにしている.
  case ruleBased = "onDeviceOnly"

  var displayName: String {
    switch self {
    case .automatic: return "自動（Apple Intelligence を優先）"
    case .privateCloud: return "Private Cloud Compute のみ"
    case .onDeviceModel: return "端末内の Apple Intelligence のみ"
    case .ruleBased: return "ルールベースのみ（AI を使わない）"
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
    static let hasRemovedLegacyClaudeSettings = "settings.hasRemovedLegacyClaudeSettings"
  }

  private let defaults: UserDefaults

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

  // MARK: - 初期化

  init(defaults: UserDefaults = AppGroup.defaults) {
    self.defaults = defaults

    self.outputLanguage = defaults.string(forKey: Key.outputLanguage) ?? "ja"
    self.strictness = AnalysisStrictness(rawValue: defaults.string(forKey: Key.strictness) ?? "") ?? .balanced
    // 廃止した「Claude API のみ」などの未知の値は, 既定の自動に戻す.
    self.providerMode = ProviderMode(rawValue: defaults.string(forKey: Key.providerMode) ?? "") ?? .automatic
    self.stagedAnalysisEnabled = defaults.object(forKey: Key.stagedAnalysis) as? Bool ?? true
    self.notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
    self.weeklyDigestEnabled = defaults.object(forKey: Key.weeklyDigestEnabled) as? Bool ?? true
    self.readerTheme = ReaderTheme(rawValue: defaults.string(forKey: Key.readerTheme) ?? "") ?? .system
    self.readerTypeface = ReaderTypeface(rawValue: defaults.string(forKey: Key.readerTypeface) ?? "") ?? .mincho
    self.readerFontSize = defaults.object(forKey: Key.readerFontSize) as? Double ?? 17
    self.readerLineSpacing = defaults.object(forKey: Key.readerLineSpacing) as? Double ?? 8
    self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)

    LegacyClaudeSettings.removeIfNeeded(
      defaults: defaults,
      doneKey: Key.hasRemovedLegacyClaudeSettings
    )
  }

  // MARK: - 診断プロバイダ

  /// Apple Intelligence の現在の利用可否.
  var appleIntelligenceAvailability: AppleIntelligenceAvailability {
    AppleIntelligenceAvailability.current(outputLanguage: outputLanguage)
  }

  /// Private Cloud Compute のみを選んだのに使えなかったときに, 診断結果へ表示する説明.
  static let privateCloudFallbackNotice = "Private Cloud Compute を利用できなかったため, ルールベースで判定しました."

  /// 実際に使用するプロバイダを決定する.
  /// 使えるモデルがなければ, 機能を止めずにルールベース診断へ切り替える.
  func makeProvider() -> AnalysisProvider {
    let available = appleIntelligenceAvailability.availableEngines
    switch providerMode {
    case .ruleBased:
      return HeuristicAnalysisProvider()
    case .privateCloud:
      // 黙って端末内モデルへ切り替えると品質の低下に気づけないため, ルールベースへ退避して知らせる.
      return AppleIntelligenceAnalysisProvider(
        engines: available.filter { $0 == .privateCloud },
        fallbackNotice: Self.privateCloudFallbackNotice
      )
    case .onDeviceModel:
      return makeAutomaticProvider(engines: available.filter { $0 == .onDevice })
    case .automatic:
      return makeAutomaticProvider(engines: available)
    }
  }

  /// 使えるモデルがあれば Apple Intelligence, 無ければルールベースを返す.
  private func makeAutomaticProvider(engines: [IntelligenceEngine]) -> AnalysisProvider {
    guard !engines.isEmpty else { return HeuristicAnalysisProvider() }
    return AppleIntelligenceAnalysisProvider(engines: engines)
  }

  /// 現在有効なプロバイダの表示名.
  var activeProviderName: String {
    makeProvider().displayName
  }
}

// MARK: - 旧設定の後始末

/// Claude API を使っていた頃の設定を, 1 度だけ削除する.
/// API キーは Keychain に残り続けると漏洩の危険だけが残るため, 確実に消す.
private enum LegacyClaudeSettings {

  /// 旧版が Keychain に保存していた API キーの所在.
  private static let keychainService = "jp.tsumugi.keychain"
  private static let keychainAccount = "jp.tsumugi.analysis.apiKey"

  /// 旧版が UserDefaults に保存していた値.
  private static let defaultsKeys = [
    "settings.model.small",
    "settings.model.medium",
    "settings.model.large",
    "settings.monthlyAnalysisCount",
    "settings.monthlyAnalysisPeriod"
  ]

  static func removeIfNeeded(defaults: UserDefaults, doneKey: String) {
    guard !defaults.bool(forKey: doneKey) else { return }
    defaultsKeys.forEach(defaults.removeObject(forKey:))
    // 削除に失敗した場合は印を付けず, 次回の起動で再試行する.
    guard deleteKeychainItem() else { return }
    defaults.set(true, forKey: doneKey)
  }

  /// Keychain の API キーを削除する. 元から無い場合も成功とみなす.
  private static func deleteKeychainItem() -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
