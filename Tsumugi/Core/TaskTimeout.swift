//
//  TaskTimeout.swift
//  Tsumugi
//
//  仕様書 6.2 / 3.2:「診断タイムアウトは 60 秒で打ち切り, 部分結果を保存する」ための補助.
//

import Foundation

/// 指定秒数で打ち切るタイムアウトエラー.
struct TimeoutError: LocalizedError {
  let seconds: TimeInterval
  var errorDescription: String? {
    "処理が \(Int(seconds)) 秒以内に完了しませんでした."
  }
}

/// 処理にタイムアウトを設ける.
///
/// - Parameters:
///   - seconds: 制限時間（秒）.
///   - operation: 実行する処理.
/// - Throws: 制限時間を超えた場合は `TimeoutError`.
func withTimeout<T: Sendable>(
  seconds: TimeInterval,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      throw TimeoutError(seconds: seconds)
    }

    guard let result = try await group.next() else {
      throw TimeoutError(seconds: seconds)
    }
    group.cancelAll()
    return result
  }
}
