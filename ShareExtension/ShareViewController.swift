//
//  ShareViewController.swift
//  ShareExtension
//
//  仕様書 4.1 / S-01: 共有シートから起動される Share Extension.
//
//  性能要件（仕様書 10.1）:
//  - 起動から UI 表示まで 300ms 以内 → viewDidLoad で即座に UI を出し, ペイロードは非同期に読む.
//  - 保存タップからシート消滅まで 800ms 以内 → 保存はローカルのキューに書くだけにする.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

  private enum Constant {
    /// 保存完了トーストを表示してから閉じるまでの時間（仕様書 SE-06）.
    static let dismissDelay: TimeInterval = 0.8
  }

  private let store = SharedItemStore()
  private let model = ShareSheetModel()
  private var hostingController: UIHostingController<ShareSheetView>?

  override func viewDidLoad() {
    super.viewDidLoad()
    installSheet()
    loadSharedPayload()
  }

  // MARK: - UI の組み立て

  private func installSheet() {
    let view = ShareSheetView(
      model: model,
      onSave: { [weak self] in self?.save() },
      onCancel: { [weak self] in self?.cancelRequest() }
    )
    let controller = UIHostingController(rootView: view)
    hostingController = controller

    addChild(controller)
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    self.view.addSubview(controller.view)
    NSLayoutConstraint.activate([
      controller.view.topAnchor.constraint(equalTo: self.view.topAnchor),
      controller.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
      controller.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
    ])
    controller.didMove(toParent: self)
  }

  // MARK: - ペイロードの受け取り（仕様書 4.1）

  private func loadSharedPayload() {
    guard
      let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
      let attachments = extensionItem.attachments,
      !attachments.isEmpty
    else {
      model.state = .failed("共有された内容を読み取れませんでした.")
      return
    }

    let propertyListType = UTType.propertyList.identifier

    // 1) JavaScript Preprocessing の結果（Safari で表示中のページ）を最優先で使う.
    if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(propertyListType) }) {
      provider.loadItem(forTypeIdentifier: propertyListType) { [weak self] item, error in
        guard
          let dictionary = item as? NSDictionary,
          let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any],
          let payload = SharedPayload(javaScriptResults: results)
        else {
          // DOM が取れなくても URL だけで保存できるようにフォールバックする.
          self?.loadURL(from: attachments, fallbackError: error)
          return
        }
        self?.apply(payload)
      }
      return
    }

    // 2) 他アプリからの URL 共有（仕様書 SE-07）.
    loadURL(from: attachments, fallbackError: nil)
  }

  private func loadURL(from attachments: [NSItemProvider], fallbackError: Error?) {
    let urlType = UTType.url.identifier
    let textType = UTType.plainText.identifier

    if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
      provider.loadItem(forTypeIdentifier: urlType) { [weak self] item, error in
        guard let url = item as? URL else {
          self?.reportLoadFailure(error ?? fallbackError)
          return
        }
        self?.apply(SharedPayload(url: url.absoluteString))
      }
      return
    }

    // 3) テキスト共有の中に URL が含まれている場合を拾う.
    if let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
      provider.loadItem(forTypeIdentifier: textType) { [weak self] item, error in
        guard let text = item as? String, let url = Self.firstURL(in: text) else {
          self?.reportLoadFailure(error ?? fallbackError)
          return
        }
        self?.apply(SharedPayload(url: url))
      }
      return
    }

    reportLoadFailure(fallbackError)
  }

  /// テキストから最初の URL を取り出す.
  private static func firstURL(in text: String) -> String? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
      return nil
    }
    let range = NSRange(location: 0, length: (text as NSString).length)
    return detector.firstMatch(in: text, range: range)?.url?.absoluteString
  }

  private func apply(_ payload: SharedPayload) {
    // 仕様書 3.2: 正規化 URL で重複を照合し「既に保存済み」と伝える.
    let normalized = URLNormalizer.normalize(payload.url, canonicalHint: payload.page.meta["canonical"])
    let isDuplicate = normalized.map { store.isAlreadySaved(urlHash: $0.urlHash) } ?? false

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.model.payload = payload
      self.model.isDuplicate = isDuplicate
      self.model.state = .ready
    }
  }

  private func reportLoadFailure(_ error: Error?) {
    DispatchQueue.main.async { [weak self] in
      self?.model.state = .failed(
        error?.localizedDescription ?? "この共有内容には保存できる URL が含まれていませんでした."
      )
    }
  }

  // MARK: - 保存

  private func save() {
    guard var payload = model.payload else { return }
    payload.userTags = model.tags
    payload.userNote = model.note.trimmingCharacters(in: .whitespacesAndNewlines)
    payload.sourceApp = Bundle.main.object(forInfoDictionaryKey: "NSExtensionHostBundleID") as? String

    do {
      try store.enqueue(payload)
      model.state = .saved
      DispatchQueue.main.asyncAfter(deadline: .now() + Constant.dismissDelay) { [weak self] in
        self?.completeRequest()
      }
    } catch {
      model.state = .failed(error.localizedDescription)
    }
  }

  private func completeRequest() {
    extensionContext?.completeRequest(returningItems: nil)
  }

  private func cancelRequest() {
    extensionContext?.cancelRequest(withError: NSError(domain: "jp.tsumugi.share", code: NSUserCancelledError))
  }
}
