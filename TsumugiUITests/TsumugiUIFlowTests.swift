//
//  TsumugiUIFlowTests.swift
//  TsumugiUITests
//
//  仕様書 11.1（XCUITest）: 主要画面を通しで開けることを確認し, 各画面のスクリーンショットを残す.
//

import XCTest

final class TsumugiUIFlowTests: XCTestCase {

  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launch()
  }

  /// スクリーンショットをテスト結果に添付する.
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// 通知の許可を尋ねるシステムのダイアログが出ていれば閉じる.
  /// 診断が完了した時点で表示されるため, 画面の確認前に片付けておく.
  private func dismissSystemAlertIfNeeded() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for label in ["許可しない", "Don't Allow"] {
      let button = springboard.buttons[label]
      if button.waitForExistence(timeout: 3) {
        button.tap()
        return
      }
    }
  }

  /// オンボーディングが出ていれば閉じる.
  private func dismissOnboardingIfNeeded() {
    let skip = app.buttons["スキップ"]
    if skip.waitForExistence(timeout: 5) {
      capture("00-オンボーディング")
      skip.tap()
    }
  }

  func testMainFlow() throws {
    dismissOnboardingIfNeeded()

    // --- ライブラリ（S-02） ---
    XCTAssertTrue(app.navigationBars["ライブラリ"].waitForExistence(timeout: 10), "ライブラリが表示されない")
    capture("01-ライブラリ")

    // --- Item 詳細（S-03） ---
    let firstCard = app.scrollViews.otherElements.buttons.firstMatch
    guard firstCard.waitForExistence(timeout: 10) else {
      capture("01b-記事なし")
      return
    }
    firstCard.tap()

    XCTAssertTrue(app.buttons["診断"].waitForExistence(timeout: 15), "詳細画面のタブが表示されない")
    dismissSystemAlertIfNeeded()
    capture("02-Item詳細-要約")

    // --- 診断タブ ---
    app.buttons["診断"].tap()
    capture("03-Item詳細-診断")

    // --- 信頼度診断詳細（S-04） ---
    let detailLinks = app.buttons.matching(identifier: "詳しく見る")
    let credibilityLink = detailLinks.element(boundBy: 0)
    if credibilityLink.waitForExistence(timeout: 5) {
      credibilityLink.tap()
      XCTAssertTrue(app.navigationBars["信頼度診断"].waitForExistence(timeout: 10))
      capture("04-信頼度診断詳細")
      app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // --- 鮮度診断詳細（S-05） ---
    let freshnessLink = app.buttons.matching(identifier: "詳しく見る").element(boundBy: 1)
    if freshnessLink.waitForExistence(timeout: 5) {
      freshnessLink.tap()
      XCTAssertTrue(app.navigationBars["情報の新しさ"].waitForExistence(timeout: 10))
      capture("05-鮮度診断詳細")
      app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // --- 本文タブ ---
    if app.buttons["本文"].waitForExistence(timeout: 5) {
      app.buttons["本文"].tap()
      capture("06-Item詳細-本文")
    }

    // ライブラリへ戻る.
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // --- ダイジェスト（S-11） ---
    app.tabBars.buttons["ダイジェスト"].tap()
    XCTAssertTrue(app.navigationBars["ダイジェスト"].waitForExistence(timeout: 10))
    capture("07-ダイジェスト")

    // --- 検索（S-07） ---
    app.tabBars.buttons["検索"].tap()
    XCTAssertTrue(app.navigationBars["検索"].waitForExistence(timeout: 10))
    capture("08-検索")

    // --- 設定（S-09） ---
    app.tabBars.buttons["設定"].tap()
    XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))
    capture("09-設定")
  }

  /// 仕様書 10.1: アプリ起動からライブラリ表示までの時間を計測する（目標 1.0 秒以内）.
  func testLaunchPerformance() throws {
    measure(metrics: [XCTApplicationLaunchMetric()]) {
      XCUIApplication().launch()
    }
  }
}
