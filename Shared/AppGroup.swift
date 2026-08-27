//
//  AppGroup.swift
//  Tsumugi / ShareExtension 共通
//
//  仕様書 SE-05: App Group 共有コンテナの識別子と配置を定義する.
//

import Foundation

/// 本体アプリと Share Extension が共有するコンテナの設定.
enum AppGroup {
  /// App Group 識別子. Xcode の Signing & Capabilities で同じ値を両ターゲットに設定する.
  static let identifier = "group.com.HR.Tsumugi"

  /// 共有 UserDefaults. App Group が未設定の環境では標準の UserDefaults にフォールバックする.
  static var defaults: UserDefaults {
    UserDefaults(suiteName: identifier) ?? .standard
  }

  /// 共有コンテナのルート URL.
  ///
  /// App Group が有効でない場合（Capability 未設定, プロビジョニング未整備など）は
  /// アプリ自身の Application Support 配下にフォールバックし, 機能を停止させない.
  static var containerURL: URL {
    if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
      return shared
    }
    let fallback = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? URL.temporaryDirectory
    return fallback.appendingPathComponent("TsumugiFallback", isDirectory: true)
  }

  /// App Group が実際に利用できているか. 設定画面での診断表示に使う.
  static var isSharedContainerAvailable: Bool {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
  }

  /// 未処理の共有ペイロードを置くキューディレクトリ.
  static var queueDirectory: URL {
    containerURL.appendingPathComponent("ShareQueue", isDirectory: true)
  }

  /// 本体アプリが書き出す「保存済み URL ハッシュ」の索引ファイル.
  /// Share Extension が重複判定（仕様書 3.2）に使う.
  static var savedIndexURL: URL {
    containerURL.appendingPathComponent("saved-url-hashes.json", isDirectory: false)
  }
}
