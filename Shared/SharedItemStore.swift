//
//  SharedItemStore.swift
//  Tsumugi / ShareExtension 共通
//
//  仕様書 SE-05 / 6.1: App Group 共有コンテナ上のアップロードキュー.
//
//  Share Extension は本体アプリの SwiftData ストアに直接書き込まず,
//  JSON ファイルとしてキューに積むだけにする.
//  これにより Extension のメモリ上限（約 120MB, 仕様書 SE-04）を守りつつ,
//  保存操作は常にローカルで成功する（仕様書 10.2）.
//

import Foundation

/// 共有キューの読み書きで発生しうるエラー.
enum SharedItemStoreError: LocalizedError {
  case containerUnavailable
  case encodingFailed(underlying: Error)
  case writeFailed(underlying: Error)

  var errorDescription: String? {
    switch self {
    case .containerUnavailable:
      return "共有コンテナにアクセスできませんでした. App Group の設定をご確認ください."
    case .encodingFailed:
      return "共有内容の変換に失敗しました."
    case .writeFailed:
      return "共有内容の保存に失敗しました. 空き容量をご確認ください."
    }
  }

  var failureReason: String? {
    switch self {
    case .containerUnavailable: return nil
    case .encodingFailed(let error), .writeFailed(let error): return error.localizedDescription
    }
  }
}

/// App Group 上の共有キューを操作するストア.
struct SharedItemStore {

  /// キューファイルの拡張子.
  private static let fileExtension = "json"

  private let fileManager = FileManager.default

  init() {}

  // MARK: - 書き込み（Share Extension 側）

  /// ペイロードをキューに積む.
  ///
  /// 一時ファイルへ書いてから `replaceItemAt` で置き換えることで,
  /// 本体アプリが読み取り中の中途半端なファイルを見ないようにする.
  func enqueue(_ payload: SharedPayload) throws {
    try ensureQueueDirectoryExists()

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.withoutEscapingSlashes]

    let data: Data
    do {
      data = try encoder.encode(payload)
    } catch {
      throw SharedItemStoreError.encodingFailed(underlying: error)
    }

    let destination = AppGroup.queueDirectory
      .appendingPathComponent("\(payload.sharedAt.timeIntervalSince1970)-\(payload.id.uuidString)")
      .appendingPathExtension(Self.fileExtension)

    do {
      try data.write(to: destination, options: [.atomic])
    } catch {
      throw SharedItemStoreError.writeFailed(underlying: error)
    }
  }

  // MARK: - 読み出し（本体アプリ側）

  /// キューに積まれたペイロードを共有された順に取り出す.
  /// 壊れたファイルは読み飛ばしたうえで削除し, キューが詰まらないようにする.
  func dequeueAll() -> [SharedPayload] {
    guard let urls = try? fileManager.contentsOfDirectory(
      at: AppGroup.queueDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var payloads: [SharedPayload] = []
    for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
    where url.pathExtension == Self.fileExtension {
      guard
        let data = try? Data(contentsOf: url),
        let payload = try? decoder.decode(SharedPayload.self, from: data)
      else {
        try? fileManager.removeItem(at: url)
        continue
      }
      payloads.append(payload)
      try? fileManager.removeItem(at: url)
    }
    return payloads
  }

  /// キューに残っている件数. バッジ表示に使う.
  var pendingCount: Int {
    let urls = (try? fileManager.contentsOfDirectory(
      at: AppGroup.queueDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )) ?? []
    return urls.filter { $0.pathExtension == Self.fileExtension }.count
  }

  // MARK: - 重複判定用の索引（仕様書 3.2）

  /// 本体アプリが保存済み URL ハッシュの索引を書き出す.
  func writeSavedIndex(_ hashes: Set<String>) {
    guard let data = try? JSONEncoder().encode(Array(hashes)) else { return }
    try? ensureContainerExists()
    try? data.write(to: AppGroup.savedIndexURL, options: [.atomic])
  }

  /// Share Extension が索引を読み, 既に保存済みかどうかを判定する.
  func isAlreadySaved(urlHash: String) -> Bool {
    guard
      let data = try? Data(contentsOf: AppGroup.savedIndexURL),
      let hashes = try? JSONDecoder().decode([String].self, from: data)
    else {
      return false
    }
    return hashes.contains(urlHash)
  }

  // MARK: - 内部処理

  private func ensureContainerExists() throws {
    let container = AppGroup.containerURL
    if !fileManager.fileExists(atPath: container.path) {
      try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
    }
  }

  private func ensureQueueDirectoryExists() throws {
    do {
      try ensureContainerExists()
      let directory = AppGroup.queueDirectory
      if !fileManager.fileExists(atPath: directory.path) {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      }
    } catch {
      throw SharedItemStoreError.containerUnavailable
    }
  }
}
