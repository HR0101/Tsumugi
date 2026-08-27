//
//  ItemStatus.swift
//  Tsumugi
//
//  仕様書 7.2 / 7.3: Item の状態遷移を表す列挙型.
//

import Foundation

/// Item の処理状態. 仕様書 7.2 の状態遷移図に対応する.
///
/// ```
/// pending → extracting → analyzing → completed
///                     ↘ extractionFailed
///                     ↘ partial
///                     ↘ unsupportedFormat
/// completed → reanalyzing → completed
/// ```
enum ItemStatus: String, Codable, CaseIterable, Sendable {
  /// ローカル保存済み. 抽出待ち.
  case pending
  /// 本文抽出中.
  case extracting
  /// AI 診断中.
  case analyzing
  /// 全処理完了.
  case completed
  /// 一部の診断のみ完了（タイムアウト等）.
  case partial
  /// 本文抽出に失敗. 原文リンクのみ保持.
  case extractionFailed
  /// PDF / 動画など v1.0 では未対応の形式.
  case unsupportedFormat
  /// 再診断中.
  case reanalyzing

  /// 画面表示用の日本語ラベル.
  var displayName: String {
    switch self {
    case .pending: return "保存済み"
    case .extracting: return "本文を抽出中"
    case .analyzing: return "診断中"
    case .completed: return "診断完了"
    case .partial: return "一部のみ診断"
    case .extractionFailed: return "本文抽出に失敗"
    case .unsupportedFormat: return "未対応の形式"
    case .reanalyzing: return "再診断中"
    }
  }

  /// 処理が進行中かどうか. 進行中はライブラリでスピナーを表示する.
  var isInFlight: Bool {
    switch self {
    case .pending, .extracting, .analyzing, .reanalyzing: return true
    case .completed, .partial, .extractionFailed, .unsupportedFormat: return false
    }
  }

  /// 本文の閲覧が可能かどうか.
  var hasReadableBody: Bool {
    switch self {
    case .completed, .partial, .reanalyzing: return true
    case .pending, .extracting, .analyzing, .extractionFailed, .unsupportedFormat: return false
    }
  }

  /// ステータスを示す SF Symbols 名.
  var symbolName: String {
    switch self {
    case .pending: return "clock"
    case .extracting, .analyzing, .reanalyzing: return "arrow.triangle.2.circlepath"
    case .completed: return "checkmark.circle"
    case .partial: return "circle.lefthalf.filled"
    case .extractionFailed: return "exclamationmark.triangle"
    case .unsupportedFormat: return "questionmark.square.dashed"
    }
  }
}
