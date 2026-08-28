//
//  ShareSheetView.swift
//  ShareExtension
//
//  仕様書 S-01: Share Extension のシート UI.
//  タイトル / サムネ / タグ入力 / メモ / 保存ボタン.
//

import SwiftUI
import Observation

/// シートの状態.
enum ShareSheetState: Equatable {
  /// 共有内容を読み込み中.
  case loading
  /// 保存できる状態.
  case ready
  /// 保存完了（トースト表示中）.
  case saved
  /// 失敗.
  case failed(String)
}

@Observable
final class ShareSheetModel {
  var state: ShareSheetState = .loading
  var payload: SharedPayload?
  /// 同じ URL が既に保存されているか（仕様書 3.2）.
  var isDuplicate = false
  var tags: [String] = []
  var note: String = ""
}

struct ShareSheetView: View {

  @Bindable var model: ShareSheetModel
  let onSave: () -> Void
  let onCancel: () -> Void

  @State private var tagInput = ""

  var body: some View {
    NavigationStack {
      Group {
        switch model.state {
        case .loading:
          loadingView
        case .ready:
          form
        case .saved:
          savedToast
        case .failed(let message):
          failureView(message)
        }
      }
      .navigationTitle("Tsumugi に保存")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル", action: onCancel)
            .disabled(model.state == .saved)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存", action: onSave)
            .fontWeight(.semibold)
            .disabled(model.state != .ready)
        }
      }
    }
  }

  // MARK: - 各状態

  private var loadingView: some View {
    VStack(spacing: 12) {
      ProgressView()
      Text("共有された内容を読み込んでいます…")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var form: some View {
    Form {
      Section {
        HStack(alignment: .top, spacing: 12) {
          thumbnail
          VStack(alignment: .leading, spacing: 4) {
            Text(model.payload?.displayTitle ?? "")
              .font(.subheadline.weight(.semibold))
              .lineLimit(3)
            if let host = model.payload.flatMap({ URL(string: $0.url)?.host() }) {
              Text(host)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        if model.isDuplicate {
          Label("この記事はすでに保存されています. 保存するとタグとメモだけが追記されます.", systemImage: "checkmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let selection = model.payload?.page.selection, !selection.isEmpty {
          Label("選択したテキストをハイライトとして保存します", systemImage: "highlighter")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("タグ") {
        if !model.tags.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              ForEach(model.tags, id: \.self) { tag in
                HStack(spacing: 4) {
                  Text(tag).font(.caption)
                  Button {
                    model.tags.removeAll { $0 == tag }
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                      .font(.caption2)
                      .foregroundStyle(.tertiary)
                  }
                  .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
              }
            }
          }
        }

        HStack {
          TextField("タグを追加（任意）", text: $tagInput)
            .autocorrectionDisabled()
            .onSubmit(addTag)
          Button("追加", action: addTag)
            .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }

      Section("メモ") {
        TextField("あとで思い出せるようにメモを残せます（任意）", text: $model.note, axis: .vertical)
          .lineLimit(2...5)
      }

      Section {
        Label("保存はこの端末で完結します. 本文の取得と診断はアプリを開いたときに実行されます.", systemImage: "iphone")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var savedToast: some View {
    VStack(spacing: 12) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 44))
        .foregroundStyle(.green)
      Text("保存しました")
        .font(.headline)
      Text("アプリを開くと診断が始まります.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }

  private func failureView(_ message: String) -> some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 40))
        .foregroundStyle(.orange)
      Text("保存できませんでした")
        .font(.headline)
      Text(message)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
      Button("閉じる", action: onCancel)
        .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var thumbnail: some View {
    if let urlString = model.payload?.heroImageURL, let url = URL(string: urlString) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().aspectRatio(contentMode: .fill)
        default:
          Rectangle().fill(Color.secondary.opacity(0.12))
        }
      }
      .frame(width: 56, height: 56)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    } else {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.secondary.opacity(0.12))
        .frame(width: 56, height: 56)
        .overlay {
          Image(systemName: "doc.text")
            .foregroundStyle(.secondary)
        }
    }
  }

  private func addTag() {
    let name = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !model.tags.contains(name) else { return }
    model.tags.append(name)
    tagInput = ""
  }
}
