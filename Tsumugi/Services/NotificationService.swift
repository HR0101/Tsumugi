//
//  NotificationService.swift
//  Tsumugi
//
//  仕様書 3.1: 診断完了時のプッシュ通知,
//  仕様書 4.5.4: 週次の陳腐化ダイジェスト通知.
//
//  サーバを持たない構成のため, いずれもローカル通知として実装する.
//

import Foundation
import UserNotifications

/// 通知の発行を担当する.
struct NotificationService {

  private enum Identifier {
    static let analysisCompletePrefix = "analysis-complete."
    static let weeklyDigest = "weekly-digest"
  }

  private let center = UNUserNotificationCenter.current()

  /// 通知の許可を求める. 既に判断済みなら現在の状態を返す.
  @discardableResult
  func requestAuthorizationIfNeeded() async -> Bool {
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    case .denied:
      return false
    case .notDetermined:
      return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    @unknown default:
      return false
    }
  }

  /// 診断完了通知を出す.
  /// 例:「診断が完了しました（信頼度 72 / 鮮度 41）」（仕様書 3.1）.
  func notifyAnalysisCompleted(itemID: UUID, title: String, credibility: Int?, freshness: Int?) async {
    guard await requestAuthorizationIfNeeded() else { return }

    let content = UNMutableNotificationContent()
    content.title = "診断が完了しました"

    var scoreParts: [String] = []
    if let credibility { scoreParts.append("信頼度 \(credibility)") }
    if let freshness { scoreParts.append("鮮度 \(freshness)") }
    content.subtitle = scoreParts.isEmpty ? title : scoreParts.joined(separator: " / ")
    content.body = title
    content.sound = .default
    // 仕様書 OT-03: カスタム URL スキームで該当 Item を開けるようにする.
    content.userInfo = ["itemID": itemID.uuidString, "deepLink": "tsumugi://item/\(itemID.uuidString)"]

    let request = UNNotificationRequest(
      identifier: Identifier.analysisCompletePrefix + itemID.uuidString,
      content: content,
      trigger: nil
    )
    try? await center.add(request)
  }

  /// 週次ダイジェストを予約する（仕様書 4.5.4）.
  /// 例:「保存済み 5 件が古い情報になった可能性があります」
  func scheduleWeeklyDigest(staleCount: Int, unreadCount: Int) async {
    guard await requestAuthorizationIfNeeded() else { return }
    center.removePendingNotificationRequests(withIdentifiers: [Identifier.weeklyDigest])
    guard staleCount > 0 || unreadCount > 0 else { return }

    let content = UNMutableNotificationContent()
    content.title = "今週のダイジェスト"
    var lines: [String] = []
    if staleCount > 0 { lines.append("保存済み \(staleCount) 件が古い情報になった可能性があります.") }
    if unreadCount > 0 { lines.append("未読が \(unreadCount) 件あります.") }
    content.body = lines.joined(separator: " ")
    content.sound = .default
    content.userInfo = ["deepLink": "tsumugi://digest"]

    // 毎週月曜 9 時に通知する.
    var components = DateComponents()
    components.weekday = 2
    components.hour = 9
    components.minute = 0

    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    let request = UNNotificationRequest(identifier: Identifier.weeklyDigest, content: content, trigger: trigger)
    try? await center.add(request)
  }

  /// 予約済みの週次ダイジェストを取り消す.
  func cancelWeeklyDigest() {
    center.removePendingNotificationRequests(withIdentifiers: [Identifier.weeklyDigest])
  }
}
