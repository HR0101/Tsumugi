//
//  KeychainStore.swift
//  Tsumugi
//
//  仕様書 10.3: トークン・API キーは Keychain に保管する.
//  `kSecAttrAccessibleAfterFirstUnlock` を指定し, バックグラウンド処理からも読めるようにする.
//

import Foundation
import Security

/// Keychain の読み書きで発生するエラー.
enum KeychainError: LocalizedError {
  case unexpectedStatus(OSStatus)
  case encodingFailed

  var errorDescription: String? {
    switch self {
    case .unexpectedStatus(let status):
      return "キーチェーンの操作に失敗しました（コード \(status)）."
    case .encodingFailed:
      return "保存する値を変換できませんでした."
    }
  }
}

/// Keychain に文字列を保管する薄いラッパー.
struct KeychainStore {

  /// 保管するキーの一覧.
  enum Key: String {
    /// AI プロバイダの API キー.
    case analysisAPIKey = "jp.tsumugi.analysis.apiKey"
  }

  private let service: String

  init(service: String = "jp.tsumugi.keychain") {
    self.service = service
  }

  /// 値を保存する. 既存の値があれば上書きする.
  func save(_ value: String, for key: Key) throws {
    guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailed }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue
    ]

    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return }

    guard updateStatus == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(updateStatus)
    }

    var insertQuery = query
    insertQuery.merge(attributes) { current, _ in current }
    let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KeychainError.unexpectedStatus(addStatus)
    }
  }

  /// 値を読み出す. 未保存なら `nil`.
  func read(_ key: Key) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// 値を削除する.
  func delete(_ key: Key) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
}
