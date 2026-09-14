//
//  TagManagerView.swift
//  Tsumugi
//
//  仕様書 S-08: タグ管理.
//  タグ一覧 / 件数 / 統合・リネーム.
//

import SwiftUI
import SwiftData

struct TagManagerView: View {

  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Tag.name) private var tags: [Tag]

  @State private var renameTarget: Tag?
  @State private var renameText = ""
  @State private var mergeSource: Tag?
  @State private var mergeDestinationName = ""

  private var sortedTags: [Tag] {
    tags.sorted { ($0.itemCount, $1.name) > ($1.itemCount, $0.name) }
  }

  var body: some View {
    Group {
      if tags.isEmpty {
        EmptyStateView(
          symbolName: "number",
          title: "タグがありません",
          message: "記事を保存すると AI がタグを提案します. 詳細画面の「メモ」タブから手動で追加することもできます."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          Section {
            ForEach(sortedTags) { tag in
              HStack {
                Image(systemName: tag.source == .ai ? "sparkles" : "number")
                  .font(.caption)
                  .foregroundStyle(tag.source == .ai ? Color.accentColor : .secondary)
                  .frame(width: 20)
                Text(tag.name)
                Spacer()
                Text("\(tag.itemCount)")
                  .font(.caption.weight(.semibold))
                  .monospacedDigit()
                  .foregroundStyle(Palette.inkMuted)
              }
              .accessibilityElement(children: .combine)
              .accessibilityLabel("\(tag.name), \(tag.itemCount) 件")
              .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                  delete(tag)
                } label: {
                  Label("削除", systemImage: "trash")
                }
                Button {
                  renameTarget = tag
                  renameText = tag.name
                } label: {
                  Label("名前を変更", systemImage: "pencil")
                }
                .tint(.blue)
                Button {
                  mergeSource = tag
                  mergeDestinationName = ""
                } label: {
                  Label("統合", systemImage: "arrow.triangle.merge")
                }
                .tint(.orange)
              }
            }
          } header: {
            Text("\(tags.count) 個のタグ")
          } footer: {
            Text("「\(Image(systemName: "sparkles"))」は AI が自動提案したタグです. 左スワイプで名前の変更・統合・削除ができます.")
          }
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(WashiBackground())
    .navigationTitle("タグ管理")
    .navigationBarTitleDisplayMode(.inline)
    .alert("タグの名前を変更", isPresented: Binding(
      get: { renameTarget != nil },
      set: { if !$0 { renameTarget = nil } }
    )) {
      TextField("新しい名前", text: $renameText)
      Button("キャンセル", role: .cancel) { renameTarget = nil }
      Button("変更") { rename() }
    }
    .alert("タグを統合", isPresented: Binding(
      get: { mergeSource != nil },
      set: { if !$0 { mergeSource = nil } }
    )) {
      TextField("統合先のタグ名", text: $mergeDestinationName)
      Button("キャンセル", role: .cancel) { mergeSource = nil }
      Button("統合") { merge() }
    } message: {
      Text("「\(mergeSource?.name ?? "")」が付いた記事を統合先のタグに付け替え, このタグを削除します.")
    }
  }

  // MARK: - 操作

  private func delete(_ tag: Tag) {
    // 記事側の参照を外してからタグを消す.
    for item in tag.items {
      item.tags.removeAll { $0.name == tag.name }
    }
    modelContext.delete(tag)
    try? modelContext.save()
  }

  private func rename() {
    guard let target = renameTarget else { return }
    let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !newName.isEmpty, newName != target.name else {
      renameTarget = nil
      return
    }

    // 同名タグが既にある場合は統合として扱う.
    if let existing = tags.first(where: { $0.name == newName }) {
      moveItems(from: target, to: existing)
      modelContext.delete(target)
    } else {
      target.name = newName
      // 手動で名前を付け直したタグは, 以後ユーザー由来として扱う.
      target.source = .user
    }
    try? modelContext.save()
    renameTarget = nil
  }

  private func merge() {
    guard let source = mergeSource else { return }
    let destinationName = mergeDestinationName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !destinationName.isEmpty, destinationName != source.name else {
      mergeSource = nil
      return
    }

    let destination: Tag
    if let existing = tags.first(where: { $0.name == destinationName }) {
      destination = existing
    } else {
      destination = Tag(name: destinationName, source: .user)
      modelContext.insert(destination)
    }

    moveItems(from: source, to: destination)
    modelContext.delete(source)
    try? modelContext.save()
    mergeSource = nil
  }

  private func moveItems(from source: Tag, to destination: Tag) {
    for item in source.items {
      item.tags.removeAll { $0.name == source.name }
      if !item.tags.contains(where: { $0.name == destination.name }) {
        item.tags.append(destination)
      }
    }
  }
}
