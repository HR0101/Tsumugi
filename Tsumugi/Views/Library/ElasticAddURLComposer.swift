//
//  ElasticAddURLComposer.swift
//  Tsumugi
//
//  Patterns 1–4 を統合した URL 保存コンポーザー:
//  - ElasticSheetOverlay（弾性アーチ）内で動作
//  - LiquidGlassCancelHeader（iOS 26 2段階リキッドキャンセル）
//  - DetectingTextView + DetectionFlightLayer（下線 → オーブ飛翔 → ホストピル展開）
//  - ElasticSendButton（活性化＆発射ポップ）
//

import SwiftUI
import UIKit

struct ElasticAddURLComposer: View {
  @Binding var draftText: String
  let onSave: (String) async -> Void
  let onSaveDraft: (String) -> Void
  let onDiscard: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var flight = DetectionFlightController()
  @State private var isCancelExpanded = false
  @State private var isSaving = false

  private let coordinateSpaceName = "addURLComposerSpace"

  private var trimmedText: String {
    draftText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var resolvedURLString: String? {
    if case .url(let detected) = flight.activeMatch?.kind {
      return detected
    }
    return Self.firstValidHTTPURL(in: trimmedText)
  }

  private var isValidURL: Bool {
    resolvedURLString != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      LiquidGlassCancelHeader(
        isExpanded: $isCancelExpanded,
        title: "URL から紡ぐ",
        expandOnCloseTap: !trimmedText.isEmpty,
        primaryLabel: "破棄",
        primarySymbol: "trash",
        primaryIsDestructive: true,
        secondaryLabel: "下書きに保存",
        secondarySymbol: "tray.and.arrow.down",
        onPrimary: {
          resignKeyboard()
          flight.reset()
          onDiscard()
        },
        onSecondary: {
          resignKeyboard()
          onSaveDraft(draftText)
        },
        onImmediateDismiss: {
          resignKeyboard()
          onDiscard()
        }
      ) {
        Button {
          pasteFromClipboard()
        } label: {
          Image(systemName: "doc.on.clipboard")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .frame(width: 40, height: 40)
        .contentShape(Circle())
        .accessibilityLabel("クリップボードから貼り付け")
      }

      composerBox

      Text("保存後に本文を取得し, 要約を生成します. 共有シートから保存した場合と違い, 表示中のページの DOM は使えないため, ペイウォールのある記事は本文を取得できないことがあります.")
        .font(.caption2)
        .foregroundStyle(Palette.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.xs)
    .padding(.bottom, Spacing.lg)
    .onDisappear {
      flight.cancel()
    }
  }

  private var composerBox: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      ZStack(alignment: .topLeading) {
        DetectingTextView(
          text: $draftText,
          mode: .urlOnly,
          isURLInput: true,
          accessibilityLabel: "記事の URL"
        ) { match in
          flight.handleMatchChange(match, reduceMotion: reduceMotion)
        }
        .frame(height: 112)
        .onGeometryChange(for: CGRect.self) { proxy in
          proxy.frame(in: .named(coordinateSpaceName))
        } action: { rect in
          flight.textViewFrame = rect
        }

        if draftText.isEmpty {
          Text(verbatim: "https://example.com/article\nURL を含むメモもそのまま貼り付けられます")
            .font(.callout)
            .foregroundStyle(Palette.inkMuted.opacity(0.68))
            .padding(.top, 10)
            .padding(.leading, 12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }

      HStack(spacing: Spacing.sm) {
        DetectedActionPill(
          phase: flight.phase,
          match: flight.activeMatch,
          idleSymbol: "link",
          coordinateSpaceName: coordinateSpaceName,
          onCenterChange: { flight.pillCenter = $0 },
          action: {
            if let url = resolvedURLString {
              submit(url)
            }
          }
        )

        Spacer(minLength: Spacing.sm)

        ElasticSendButton(
          isEnabled: isValidURL,
          isLoading: isSaving,
          symbolName: "arrow.up",
          accessibilityLabelText: "保存",
          size: 38
        ) {
          if let url = resolvedURLString {
            submit(url)
          }
        }
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.bottom, Spacing.sm)
    }
    .background {
      PaperSurface(cornerRadius: Radius.panel, isRaised: false)
    }
    .coordinateSpace(name: coordinateSpaceName)
    // 重要ガードレール: DetectionFlightLayer は ZStack 兄弟ではなく安定高 VStack の overlay に配置する.
    .overlay {
      DetectionFlightLayer(controller: flight)
    }
  }

  private func submit(_ urlString: String) {
    guard !isSaving else { return }
    resignKeyboard()
    isSaving = true
    Task { @MainActor in
      await onSave(urlString)
      isSaving = false
    }
  }

  private func pasteFromClipboard() {
    guard let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
          !pasted.isEmpty else {
      return
    }
    draftText = pasted
  }

  private func resignKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }

  private static func firstValidHTTPURL(in text: String) -> String? {
    guard !text.isEmpty else { return nil }
    if let direct = URL(string: text),
       let scheme = direct.scheme?.lowercased(),
       scheme == "http" || scheme == "https",
       let host = direct.host(), !host.isEmpty {
      return direct.absoluteString
    }
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
      return nil
    }
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    for match in detector.matches(in: text, range: range) {
      if let url = match.url,
         let scheme = url.scheme?.lowercased(),
         scheme == "http" || scheme == "https",
         let host = url.host(), !host.isEmpty {
        return url.absoluteString
      }
    }
    return nil
  }
}
