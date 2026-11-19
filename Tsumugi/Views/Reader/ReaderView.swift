//
//  ReaderView.swift
//  Tsumugi
//
//  仕様書 S-06 / LB-06: リーダービュー.
//  フォント・行間・背景色・ダークモードに対応し, ハイライトとメモを付けられる.
//  仕様書 11.1 に従い WKWebView は使わず, ネイティブ描画で表示する.
//

import SwiftUI
import SwiftData
import AVFoundation
import Translation

struct ReaderView: View {

  let item: Item
  /// 開いた直後にジャンプする本文中の文字オフセット（仕様書 SM-06）.
  var initialOffset: Int?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(SettingsStore.self) private var settings

  @State private var isShowingDisplaySettings = false
  @State private var selectedParagraph: Paragraph?
  @State private var speech = SpeechController()
  @State private var isShowingTranslation = false
  @State private var translationConfiguration: TranslationSession.Configuration?
  @State private var isTranslating = false
  @State private var translatedCount = 0
  @State private var translationError: String?
  @State private var toastMessage: String?
  @State private var toastTask: Task<Void, Never>?

  /// 本文の 1 段落.
  struct Paragraph: Identifiable, Hashable {
    let id: Int
    let text: String
    /// 本文中の開始オフセット.
    let start: Int
    let end: Int
    var isHeading: Bool { text.hasPrefix("#") }
    /// 見出し記号を取り除いた表示用テキスト.
    var displayText: String {
      guard isHeading else { return text }
      return text.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
    }
    var headingLevel: Int {
      text.prefix { $0 == "#" }.count
    }
  }

  private var paragraphs: [Paragraph] {
    guard let bodyText = item.bodyText else { return [] }
    var result: [Paragraph] = []
    var cursor = 0
    for chunk in bodyText.components(separatedBy: "\n\n") {
      let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
      let start = cursor
      cursor += chunk.count + 2
      guard !trimmed.isEmpty else { continue }
      result.append(Paragraph(id: result.count, text: trimmed, start: start, end: start + chunk.count))
    }
    return result
  }

  private var currentBodyHash: String? {
    guard let bodyText = item.bodyText else { return nil }
    return URLNormalizer.sha256(bodyText)
  }

  private var hasCurrentTranslation: Bool {
    item.translatedBodyText != nil
      && item.translatedSourceHash == currentBodyHash
      && translatedParagraphs.count == paragraphs.count
  }

  private var translatedParagraphs: [String] {
    item.translatedBodyText?.components(separatedBy: "\n\n") ?? []
  }

  private var highlightedQuotes: Set<String> {
    Set(item.highlights.map(\.quote))
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: Spacing.lg) {
            let visibleTranslations = isShowingTranslation && hasCurrentTranslation
              ? translatedParagraphs : []
            headerBlock

            if isTranslating {
              ProgressView("和訳中（\(translatedCount) / \(paragraphs.count) 段落）")
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let translationError {
              Label(translationError, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.red)
            }

            ForEach(paragraphs) { paragraph in
              paragraphView(paragraph, translation: visibleTranslations.isEmpty
                ? nil : visibleTranslations[paragraph.id])
                .id(paragraph.id)
            }

            footerBlock
          }
          .padding(.horizontal, Spacing.xl)
          .padding(.vertical, Spacing.lg)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(backgroundColor)
        .onAppear {
          guard let initialOffset else { return }
          // 対象オフセットを含む段落までスクロールする.
          guard let target = paragraphs.first(where: { initialOffset >= $0.start && initialOffset <= $0.end })
            ?? paragraphs.first else { return }
          withAnimation { proxy.scrollTo(target.id, anchor: .top) }
        }
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { toolbarContent }
      .sheet(isPresented: $isShowingDisplaySettings) {
        ReaderDisplaySettings()
          .presentationDetents([.height(320)])
      }
      .sheet(item: $selectedParagraph) { paragraph in
        HighlightSheet(item: item, paragraph: paragraph) { message in
          showToast(message)
        }
        .presentationDetents([.medium])
      }
      .overlay(alignment: .top) {
        JellyToastPill(message: toastMessage, icon: "highlighter")
          .padding(.top, 8)
          .allowsHitTesting(false)
      }
      .onDisappear {
        toastTask?.cancel()
        speech.stop()
      }
      .translationTask(translationConfiguration) { session in
        await translateArticle(using: session)
      }
    }
    .preferredColorScheme(preferredColorScheme)
  }

  private func showToast(_ message: String) {
    toastTask?.cancel()
    toastMessage = message
    toastTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(2.0))
      guard !Task.isCancelled else { return }
      toastMessage = nil
    }
  }

  // MARK: - 本文

  private var headerBlock: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(item.title)
        .font(settings.readerTypeface.headingFont(size: settings.readerFontSize + 8))
        .foregroundStyle(textColor)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)

      Text(metaLine)
        .font(.footnote)
        .foregroundStyle(Palette.inkMuted)

      Divider().padding(.top, Spacing.sm)
    }
  }

  private var metaLine: String {
    var parts = [item.displayHost]
    if let author = item.author { parts.append(author) }
    if let published = item.publishedAt { parts.append(DateStyle.long.string(from: published)) }
    if item.readingMinutes > 0 { parts.append("約 \(item.readingMinutes) 分") }
    return parts.joined(separator: " · ")
  }

  @ViewBuilder
  private func paragraphView(_ paragraph: Paragraph, translation: String?) -> some View {
    let isHighlighted = translation == nil && highlightedQuotes.contains(paragraph.text)
    let displayedText = translation ?? paragraph.text

    if paragraph.isHeading {
      Text(translation ?? paragraph.displayText)
        .font(settings.readerTypeface.headingFont(size: settings.readerFontSize + (paragraph.headingLevel <= 2 ? 5 : 2)))
        .foregroundStyle(textColor)
        .padding(.top, Spacing.md)
        .fixedSize(horizontal: false, vertical: true)
    } else {
      Text(displayedText)
        .font(settings.readerTypeface.font(size: settings.readerFontSize))
        .lineSpacing(settings.readerLineSpacing)
        .foregroundStyle(textColor)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, isHighlighted ? Spacing.sm : 0)
        .padding(.vertical, isHighlighted ? Spacing.xs : 0)
        .background(
          isHighlighted ? Color.yellow.opacity(0.25) : Color.clear,
          in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
          if translation == nil { selectedParagraph = paragraph }
        }
        .accessibilityAddTraits(translation == nil ? .isButton : [])
        .accessibilityHint(translation == nil ? "ハイライトやメモを追加します" : "")
    }
  }

  private var footerBlock: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Divider()
      Text(isShowingTranslation ? "ハイライトとメモは原文表示で追加できます。" : "段落をタップするとハイライトとメモを追加できます.")
        .font(.caption)
        .foregroundStyle(Palette.inkMuted)
      Text("この本文は私的複製の範囲でこの端末にのみ保存されています.")
        .font(.caption2)
        .foregroundStyle(Palette.inkMuted.opacity(0.72))
    }
    .padding(.top, Spacing.lg)
  }

  // MARK: - ツールバー

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Button("閉じる") { dismiss() }
    }

    ToolbarItem(placement: .topBarTrailing) {
      Button {
        if isShowingTranslation {
          isShowingTranslation = false
        } else if hasCurrentTranslation {
          isShowingTranslation = true
        } else {
          translationError = nil
          translationConfiguration = TranslationSession.Configuration(
            source: nil, target: Locale.Language(identifier: "ja")
          )
        }
      } label: {
        Label(isShowingTranslation ? "原文を表示" : "日本語に翻訳", systemImage: "character.book.closed")
      }
      .disabled(isTranslating || paragraphs.isEmpty)
    }

    ToolbarItem(placement: .topBarTrailing) {
      // 仕様書 LB-09: 読み上げ.
      Button {
        if speech.isSpeaking {
          speech.stop()
        } else {
          speech.speak(text: isShowingTranslation && hasCurrentTranslation
            ? (item.translatedBodyText ?? item.title)
            : (item.bodyText ?? item.summary?.tldr ?? item.title),
            language: isShowingTranslation ? "ja-JP" : (item.language ?? "ja-JP"))
        }
      } label: {
        Label(
          speech.isSpeaking ? "読み上げを止める" : "読み上げる",
          systemImage: speech.isSpeaking ? "stop.circle" : "speaker.wave.2"
        )
      }
    }

    ToolbarItem(placement: .topBarTrailing) {
      Button {
        isShowingDisplaySettings = true
      } label: {
        Label("表示設定", systemImage: "textformat.size")
      }
    }
  }

  @MainActor
  private func translateArticle(using session: TranslationSession) async {
    guard let sourceHash = currentBodyHash, !paragraphs.isEmpty else { return }
    isTranslating = true
    translatedCount = 0
    translationError = nil
    defer {
      isTranslating = false
      translationConfiguration = nil
    }

    let sourceParagraphs = paragraphs
    var translated = Array(repeating: "", count: sourceParagraphs.count)
    do {
      for batchStart in stride(from: 0, to: sourceParagraphs.count, by: 10) {
        try Task.checkCancellation()
        let batch = sourceParagraphs[batchStart..<min(batchStart + 10, sourceParagraphs.count)]
        let requests = batch.map {
          TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.id))
        }
        let responses = try await session.translations(from: requests)
        for response in responses {
          guard let identifier = response.clientIdentifier,
                let index = Int(identifier), translated.indices.contains(index) else { continue }
          translated[index] = response.targetText.replacingOccurrences(of: "\n\n", with: "\n")
        }
        translatedCount += batch.count
      }
      guard translated.allSatisfy({ !$0.isEmpty }), currentBodyHash == sourceHash else {
        throw TranslationError.internalError
      }
      item.translatedBodyText = translated.joined(separator: "\n\n")
      item.translatedSourceHash = sourceHash
      try modelContext.save()
      isShowingTranslation = true
    } catch is CancellationError {
      // 画面を閉じた場合は保存しない。
    } catch {
      translationError = "和訳できませんでした。\(error.localizedDescription)"
    }
  }

  // MARK: - 配色

  private var backgroundColor: Color {
    switch settings.readerTheme {
    case .system: return Color(uiColor: .systemBackground)
    case .light: return .white
    case .sepia: return Color(red: 0.937, green: 0.910, blue: 0.851)
    case .dark: return Color(red: 0.086, green: 0.082, blue: 0.075)
    }
  }

  private var textColor: Color {
    switch settings.readerTheme {
    case .system: return .primary
    case .light: return Color(red: 0.122, green: 0.106, blue: 0.086)
    case .sepia: return Color(red: 0.208, green: 0.184, blue: 0.145)
    case .dark: return Color(red: 0.937, green: 0.914, blue: 0.871)
    }
  }

  private var preferredColorScheme: ColorScheme? {
    switch settings.readerTheme {
    case .system: return nil
    case .light, .sepia: return .light
    case .dark: return .dark
    }
  }
}

/// リーダービューの表示設定（仕様書 LB-06）.
struct ReaderDisplaySettings: View {
  @Environment(SettingsStore.self) private var settings
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    @Bindable var settings = settings

    NavigationStack {
      Form {
        Section("文字サイズ") {
          HStack {
            Text("あ").font(.caption)
            Slider(value: $settings.readerFontSize, in: 13...28, step: 1)
            Text("あ").font(.title2)
          }
          Text("\(Int(settings.readerFontSize)) pt")
            .font(.caption)
            .foregroundStyle(Palette.inkMuted)
        }

        Section("行間") {
          Slider(value: $settings.readerLineSpacing, in: 2...16, step: 1)
          Text("\(Int(settings.readerLineSpacing)) pt")
            .font(.caption)
            .foregroundStyle(Palette.inkMuted)
        }

        Section("書体") {
          ElasticSegmentedBar(
            options: ReaderTypeface.allCases.map { ($0, $0.displayName) },
            selection: $settings.readerTypeface
          )
          .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

          Text("長い日本語の文章は明朝体のほうが読み進めやすいことが多いため, 既定を明朝にしています.")
            .font(.caption)
            .foregroundStyle(Palette.inkMuted)
        }

        Section("紙の色") {
          ElasticSegmentedBar(
            options: ReaderTheme.allCases.map { ($0, $0.displayName) },
            selection: $settings.readerTheme
          )
          .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
      }
      .scrollContentBackground(.hidden)
      .background(WashiBackground())
      .navigationTitle("表示設定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
    }
  }
}

/// 段落をハイライトしてメモを付けるシート（仕様書 LB-07）.
struct HighlightSheet: View {
  let item: Item
  let paragraph: ReaderView.Paragraph
  var onComplete: (String) -> Void = { _ in }

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var note = ""
  @State private var initialNote = ""
  @State private var isCancelExpanded = false

  private var existing: Highlight? {
    item.highlights.first { $0.quote == paragraph.text }
  }

  private var hasChanges: Bool {
    note != initialNote
  }

  var body: some View {
    VStack(spacing: 0) {
      LiquidGlassCancelHeader(
        isExpanded: $isCancelExpanded,
        title: existing == nil ? "ハイライトを追加" : "ハイライトを編集",
        expandOnCloseTap: hasChanges || existing != nil,
        primaryLabel: existing != nil ? "削除" : "破棄",
        primarySymbol: "trash",
        primaryIsDestructive: true,
        secondaryLabel: "保存",
        secondarySymbol: "checkmark.circle",
        onPrimary: {
          if existing != nil {
            remove()
          } else {
            dismiss()
          }
        },
        onSecondary: save,
        onImmediateDismiss: { dismiss() }
      ) {
        ElasticSendButton(
          isEnabled: true,
          symbolName: "checkmark",
          accessibilityLabelText: "保存",
          size: 40,
          action: save
        )
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.sm)
      .background(Palette.ground.opacity(0.92))
      .overlay(alignment: .bottom) {
        Rectangle().fill(Palette.rule).frame(height: Radius.hairline)
      }

      Form {
        Section("選択した段落") {
          Text(paragraph.text)
            .font(.callout)
        }
        Section("メモ") {
          TextEditor(text: $note)
            .frame(minHeight: 80)
        }
      }
      .scrollContentBackground(.hidden)
      .background(WashiBackground())
    }
    .background(WashiBackground())
    .onAppear {
      let existingNote = existing?.note ?? ""
      note = existingNote
      initialNote = existingNote
    }
  }

  private func save() {
    if let existing {
      existing.note = note
    } else {
      let highlight = Highlight(
        quote: paragraph.text,
        startOffset: paragraph.start,
        endOffset: paragraph.end,
        note: note
      )
      highlight.item = item
      modelContext.insert(highlight)
      item.highlights.append(highlight)
    }
    try? modelContext.save()
    onComplete("ハイライトを保存しました")
    dismiss()
  }

  private func remove() {
    guard let existing else { return }
    item.highlights.removeAll { $0.id == existing.id }
    modelContext.delete(existing)
    try? modelContext.save()
    onComplete("ハイライトを削除しました")
    dismiss()
  }
}

/// 読み上げの制御（仕様書 LB-09）.
@Observable
final class SpeechController {
  private let synthesizer = AVSpeechSynthesizer()
  private(set) var isSpeaking = false

  func speak(text: String, language: String = "ja-JP") {
    guard !text.isEmpty else { return }
    stop()
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: language)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    synthesizer.speak(utterance)
    isSpeaking = true
  }

  func stop() {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    isSpeaking = false
  }
}
