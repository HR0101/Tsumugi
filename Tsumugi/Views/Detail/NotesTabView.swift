//
//  NotesTabView.swift
//  Tsumugi
//
//  仕様書 5.2 / LB-07: 詳細画面の「メモ」タブ.
//  ユーザーのメモとタグを編集する.
//

import SwiftUI
import SwiftData
import UIKit

struct NotesTabView: View {
  @Bindable var item: Item

  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(AppOverlayState.self) private var overlay: AppOverlayState?
  @State private var newTagName = ""
  @State private var flight = DetectionFlightController()

  private let noteSpaceName = "noteComposerSpace"

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      noteSection
      tagSection
      if let selection = item.selectionText, !selection.isEmpty {
        selectionSection(selection)
      }
    }
  }

  private var noteSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text("メモ").sectionTitleStyle()

      ZStack(alignment: .topLeading) {
        DetectingTextView(
          text: $item.userNote,
          mode: .noteTokens,
          isURLInput: false,
          accessibilityLabel: "メモ"
        ) { match in
          flight.handleMatchChange(match, reduceMotion: reduceMotion)
        }
        .frame(height: 140)
        .onGeometryChange(for: CGRect.self) { proxy in
          proxy.frame(in: .named(noteSpaceName))
        } action: { rect in
          flight.textViewFrame = rect
        }

        if item.userNote.isEmpty {
          Text("この記事について気づいたことを書き留めておけます.\n#タグ や URL を書くと候補がピルへ飛びます.")
            .font(.callout)
            .foregroundStyle(Palette.inkMuted.opacity(0.72))
            .padding(.top, 10)
            .padding(.leading, 12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .onChange(of: item.userNote) { _, _ in
        try? modelContext.save()
      }

      HStack(spacing: Spacing.sm) {
        DetectedActionPill(
          phase: flight.phase,
          match: flight.activeMatch,
          idleSymbol: "sparkles",
          coordinateSpaceName: noteSpaceName,
          onCenterChange: { flight.pillCenter = $0 },
          action: handleDetectedAction
        )
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
    .coordinateSpace(name: noteSpaceName)
    // 重要ガードレール: DetectionFlightLayer は ZStack 兄弟ではなく安定高 VStack の overlay に配置する.
    .overlay {
      DetectionFlightLayer(controller: flight)
    }
    .onDisappear {
      flight.cancel()
    }
  }

  private var tagSection: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text("タグ").sectionTitleStyle()

      if item.tags.isEmpty {
        Text("タグはまだありません.")
          .font(.caption)
          .foregroundStyle(Palette.inkMuted.opacity(0.72))
      } else {
        FlowLayout(spacing: Spacing.sm) {
          ForEach(item.tags.sorted { $0.name < $1.name }) { tag in
            HStack(spacing: Spacing.xs) {
              if tag.source == .ai {
                Image(systemName: "sparkles").font(.caption2)
              }
              Text(tag.name).font(.caption)
              Button {
                remove(tag)
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.caption2)
                  .foregroundStyle(Palette.inkMuted.opacity(0.72))
              }
              .buttonStyle(SquishyPillButtonStyle(pressScaleX: 1.15, pressScaleY: 0.85))
              .accessibilityLabel("タグ \(tag.name) を外す")
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Palette.rule.opacity(0.35), in: Capsule())
            .transition(.scale(scale: 0.8).combined(with: .opacity))
          }
        }
      }

      HStack(spacing: Spacing.sm) {
        TextField("タグを追加", text: $newTagName)
          .textFieldStyle(.roundedBorder)
          .autocorrectionDisabled()
          .onSubmit(addTag)

        ElasticSendButton(
          isEnabled: !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          symbolName: "plus",
          accessibilityLabelText: "タグを追加",
          size: 34
        ) {
          addTag()
        }
      }

      Label("「\(Image(systemName: "sparkles"))」が付いたタグは AI が自動提案したものです.", systemImage: "info.circle")
        .font(.caption2)
        .foregroundStyle(Palette.inkMuted.opacity(0.72))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
  }

  private func selectionSection(_ selection: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text("共有時に選択していた箇所").sectionTitleStyle()
      QuoteBlock(quote: selection)
      Button {
        saveSelectionAsHighlight(selection)
      } label: {
        Label("ハイライトとして保存", systemImage: "highlighter")
          .font(.caption)
      }
      .buttonStyle(SquishyPillButtonStyle())
      .disabled(item.highlights.contains { $0.quote == selection })
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
  }

  // MARK: - 操作

  private func addTag() {
    let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard addTag(named: name) else { return }
    newTagName = ""
    overlay?.showToast("タグ「\(name)」を追加しました", icon: "tag.fill")
  }

  @discardableResult
  private func addTag(named rawName: String) -> Bool {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !item.tags.contains(where: { $0.name == name }) else { return false }

    var descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == name })
    descriptor.fetchLimit = 1

    let tag: Tag
    if let existing = try? modelContext.fetch(descriptor).first {
      tag = existing
    } else {
      tag = Tag(name: name, source: .user)
      modelContext.insert(tag)
    }
    withAnimation(ElasticMotion.jellyPop) {
      item.tags.append(tag)
    }
    try? modelContext.save()
    return true
  }

  private func handleDetectedAction() {
    guard let match = flight.activeMatch else { return }
    switch match.kind {
    case .hashtag(let tagName):
      if addTag(named: tagName) {
        overlay?.showToast("タグ「\(tagName)」を追加しました", icon: "tag.fill")
      } else {
        overlay?.showToast("タグ「\(tagName)」は登録済みです", icon: "tag")
      }
    case .url(let urlString):
      UIPasteboard.general.string = urlString
      overlay?.showToast("リンクをコピーしました", icon: "link")
    case .date(let date):
      overlay?.showToast("日付 \(DateStyle.short.string(from: date)) を確認しました", icon: "calendar")
    }
  }

  private func remove(_ tag: Tag) {
    withAnimation(ElasticMotion.liquidClose) {
      item.tags.removeAll { $0.name == tag.name }
    }
    try? modelContext.save()
  }

  private func saveSelectionAsHighlight(_ selection: String) {
    let highlight = Highlight(quote: selection)
    highlight.item = item
    modelContext.insert(highlight)
    item.highlights.append(highlight)
    try? modelContext.save()
    overlay?.showToast("ハイライトを保存しました", icon: "highlighter")
  }
}

/// タグを折り返して並べる簡易レイアウト.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var lineHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if currentX + size.width > maxWidth, currentX > 0 {
        currentX = 0
        currentY += lineHeight + spacing
        lineHeight = 0
      }
      currentX += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
    return CGSize(width: maxWidth == .infinity ? currentX : maxWidth, height: currentY + lineHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var currentX = bounds.minX
    var currentY = bounds.minY
    var lineHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if currentX + size.width > bounds.maxX, currentX > bounds.minX {
        currentX = bounds.minX
        currentY += lineHeight + spacing
        lineHeight = 0
      }
      subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
      currentX += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
  }
}
