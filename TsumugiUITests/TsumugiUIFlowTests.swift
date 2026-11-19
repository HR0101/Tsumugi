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

  func testDesignPreviewDetail() throws {
    app.terminate()
    app.launchArguments = ["--design-preview"]
    app.launch()
    let card = app.staticTexts["知らないと損をするAIツールの真実"]
    XCTAssertTrue(card.waitForExistence(timeout: 10))
    capture("design-preview-library")
    card.tap()
    XCTAssertTrue(app.buttons["診断"].waitForExistence(timeout: 10))
    capture("design-preview-detail")
    app.tabBars.buttons["検索"].tap()
    capture("design-preview-search")
    app.tabBars.buttons["ダイジェスト"].tap()
    capture("design-preview-digest")
    app.tabBars.buttons["設定"].tap()
    capture("design-preview-settings")
  }

  func testElasticMotionInteractions() throws {
    app.terminate()
    app.launchArguments = ["--design-preview"]
    app.launch()
    dismissOnboardingIfNeeded()

    XCTAssertTrue(app.navigationBars["ライブラリ"].waitForExistence(timeout: 10), "ライブラリが表示されない")
    capture("elastic-01-library")

    // Pattern 5: フィルタ札タップ
    let unreadChip = app.buttons["未読"]
    XCTAssertTrue(unreadChip.waitForExistence(timeout: 5))
    unreadChip.tap()
    unreadChip.tap()

    // Pattern 1 + 2 + 3 + 4: 弾性アーチ URL シート
    let addButton = app.buttons["URL から保存"]
    XCTAssertTrue(addButton.waitForExistence(timeout: 5))
    addButton.tap()

    XCTAssertTrue(app.staticTexts["URL から紡ぐ"].waitForExistence(timeout: 5))
    let urlEditor = app.textViews["記事の URL"]
    XCTAssertTrue(urlEditor.waitForExistence(timeout: 5))
    urlEditor.tap()
    urlEditor.typeText("https://example.com/ai-guide")

    let detectedHostPill = app.buttons["example.com"]
    XCTAssertTrue(detectedHostPill.waitForExistence(timeout: 4), "URL 検出ピルが表示されない")

    let sendButton = app.buttons["保存"]
    XCTAssertTrue(sendButton.exists && sendButton.isEnabled, "送信ボタンが活性化していない")
    capture("elastic-02-url-detected")

    // Pattern 4: Liquid Glass 2段階リキッドキャンセル展開
    let closeButton = app.buttons["閉じる"]
    XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
    closeButton.tap()

    let discardButton = app.buttons["破棄"]
    let saveDraftButton = app.buttons["下書きに保存"]
    XCTAssertTrue(discardButton.waitForExistence(timeout: 3), "1段目「破棄」が表示されない")
    XCTAssertTrue(saveDraftButton.waitForExistence(timeout: 3), "2段目「下書きに保存」が表示されない")
    XCTAssertFalse(discardButton.frame.intersects(saveDraftButton.frame), "リキッドキャンセルボタン同士が重なっている")
    capture("elastic-03-liquid-cancel")

    saveDraftButton.tap()
    XCTAssertTrue(app.staticTexts["下書きを保存しました"].waitForExistence(timeout: 3), "下書き保存トーストが表示されない")
    capture("elastic-04-draft-toast")

    // 詳細画面: Pattern 6 (ゼリーセグメント) & Pattern 8 (スパークル) & Pattern 3 (メモ内タグ飛翔)
    let card = app.staticTexts["知らないと損をするAIツールの真実"]
    XCTAssertTrue(card.waitForExistence(timeout: 5))
    card.tap()

    XCTAssertTrue(app.buttons["診断"].waitForExistence(timeout: 10))

    let favoriteButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'お気に入り'")).firstMatch
    XCTAssertTrue(favoriteButton.waitForExistence(timeout: 5))
    favoriteButton.tap()
    capture("elastic-05-detail-sparkle")

    app.buttons["診断"].tap()
    let notesTab = app.buttons["メモ"]
    XCTAssertTrue(notesTab.waitForExistence(timeout: 5))
    notesTab.tap()

    let noteEditor = app.textViews["メモ"]
    XCTAssertTrue(noteEditor.waitForExistence(timeout: 5))
    noteEditor.tap()
    noteEditor.typeText("#AI ")

    let detectedTagPill = app.buttons["#AI をタグに追加"]
    XCTAssertTrue(detectedTagPill.waitForExistence(timeout: 4), "メモ内の #AI 検出ピルが表示されない")
    capture("elastic-06-note-detected")

    if !detectedTagPill.isHittable {
      app.swipeUp()
    }
    detectedTagPill.tap()
    XCTAssertTrue(app.staticTexts["AI"].waitForExistence(timeout: 4), "検出ピルからタグが追加されない")
    capture("elastic-07-note-tag-added")
  }
}
