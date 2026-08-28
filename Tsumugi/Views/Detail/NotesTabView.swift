//
//  NotesTabView.swift
//  Tsumugi
//
//  仕様書 5.2 / LB-07: 詳細画面の「メモ」タブ.
//  ユーザーのメモとタグを編集する.
//

import SwiftUI
import SwiftData

struct NotesTabView: View {
  @Bindable var item: Item

  @Environment(\.modelContext) private var modelContext
  @State private var newTagName = ""

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
      TextEditor(text: $item.userNote)
        .font(.callout)
        .frame(minHeight: 140)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
          if item.userNote.isEmpty {
            Text("この記事について気づいたことを書き留めておけます.")
              .font(.callout)
              .foregroundStyle(Palette.inkMuted.opacity(0.72))
              .padding(.top, 8)
              .padding(.leading, 5)
              .allowsHitTesting(false)
          }
        }
        .onChange(of: item.userNote) { _, _ in
          try? modelContext.save()
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
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
              .buttonStyle(.plain)
              .accessibilityLabel("タグ \(tag.name) を外す")
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Palette.rule.opacity(0.35), in: Capsule())
          }
        }
      }

      HStack(spacing: Spacing.sm) {
        TextField("タグを追加", text: $newTagName)
          .textFieldStyle(.roundedBorder)
          .autocorrectionDisabled()
          .onSubmit(addTag)
        Button("追加", action: addTag)
          .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
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
      .disabled(item.highlights.contains { $0.quote == selection })
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
  }

  // MARK: - 操作

  private func addTag() {
    let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !item.tags.contains(where: { $0.name == name }) else { return }

    var descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == name })
    descriptor.fetchLimit = 1

    let tag: Tag
    if let existing = try? modelContext.fetch(descriptor).first {
      tag = existing
    } else {
      tag = Tag(name: name, source: .user)
      modelContext.insert(tag)
    }
    item.tags.append(tag)
    newTagName = ""
    try? modelContext.save()
  }

  private func remove(_ tag: Tag) {
    item.tags.removeAll { $0.name == tag.name }
    try? modelContext.save()
  }

  private func saveSelectionAsHighlight(_ selection: String) {
    let highlight = Highlight(quote: selection)
    highlight.item = item
    modelContext.insert(highlight)
    item.highlights.append(highlight)
    try? modelContext.save()
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
