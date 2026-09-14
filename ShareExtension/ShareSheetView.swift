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
      .scrollContentBackground(.hidden)
      .background(WashiBackground())
      .navigationTitle("Tsumugi に紡ぐ")
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
    VStack(spacing: Spacing.md) {
      ProgressView()
      Text("共有された内容を読み込んでいます…")
        .font(.footnote)
        .foregroundStyle(Palette.inkMuted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WashiBackground())
  }

  private var form: some View {
    Form {
      Section {
        HStack(alignment: .top, spacing: 12) {
          thumbnail
          VStack(alignment: .leading, spacing: 4) {
            Text(model.payload?.displayTitle ?? "")
              .font(WaFont.subheading)
              .foregroundStyle(Palette.ink)
              .lineSpacing(2)
              .lineLimit(3)
            if let host = model.payload.flatMap({ URL(string: $0.url)?.host() }) {
              Text(host)
                .font(.caption)
                .foregroundStyle(Palette.inkMuted)
            }
          }
        }

        if model.isDuplicate {
          Label("この記事はすでに保存されています. 保存するとタグとメモだけが追記されます.", systemImage: "checkmark.circle")
            .font(.caption)
            .foregroundStyle(Palette.inkMuted)
        }

        if let selection = model.payload?.page.selection, !selection.isEmpty {
          Label("選択したテキストをハイライトとして保存します", systemImage: "highlighter")
            .font(.caption)
            .foregroundStyle(Palette.inkMuted)
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
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .overlay {
                  RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(Palette.rule, lineWidth: Radius.hairline)
                }
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
          .foregroundStyle(Palette.inkMuted)
      }
    }
  }

  private var savedToast: some View {
    VStack(spacing: Spacing.md) {
      // 経糸が一本増えた, という見立て.
      WeaveMark()
        .frame(width: 72, height: 40)
      Text("紡ぎました")
        .font(WaFont.heading)
        .foregroundStyle(Palette.ink)
      Text("アプリを開くと診断が始まります.")
        .font(.footnote)
        .foregroundStyle(Palette.inkMuted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WashiBackground())
    .accessibilityElement(children: .combine)
    .accessibilityLabel("紡ぎました. アプリを開くと診断が始まります.")
  }

  private func failureView(_ message: String) -> some View {
    VStack(spacing: Spacing.md) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 32))
        .foregroundStyle(Palette.asagi)
      Text("保存できませんでした")
        .font(WaFont.heading)
        .foregroundStyle(Palette.ink)
      Text(message)
        .font(.footnote)
        .foregroundStyle(Palette.inkMuted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.xl)
      Button("閉じる", action: onCancel)
        .buttonStyle(WaButtonStyle(isProminent: false))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WashiBackground())
  }

  @ViewBuilder
  private var thumbnail: some View {
    if let urlString = model.payload?.heroImageURL, let url = URL(string: urlString) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().aspectRatio(contentMode: .fill)
        default:
          Rectangle().fill(Palette.rule.opacity(0.35))
        }
      }
      .frame(width: 56, height: 56)
      .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
          .strokeBorder(Palette.rule, lineWidth: Radius.hairline)
      }
    } else {
      RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        .fill(Palette.rule.opacity(0.25))
        .frame(width: 56, height: 56)
        .overlay {
          Image(systemName: "doc.text")
            .foregroundStyle(Palette.inkMuted)
        }
        .overlay {
          RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
            .strokeBorder(Palette.rule, lineWidth: Radius.hairline)
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

/// 保存できたことを示す小さな織り. 経糸に緯糸が一本通った形.
struct WeaveMark: View {
  var body: some View {
    Canvas { context, size in
      var generator = SeededGenerator(seed: 0x54_73_75_6D_75_67_69_00)
      let warpCount = 9
      let pitch = size.width / Double(warpCount)

      // 経糸.
      for index in 0..<warpCount {
        let x = (Double(index) + 0.5) * pitch
        let thickness = pitch * generator.next(in: 0.24...0.44)
        context.fill(
          Path(CGRect(x: x - thickness / 2, y: 0, width: thickness, height: size.height)),
          with: .color(Palette.rule)
        )
      }

      // 通したばかりの緯糸を藍で 1 本.
      let y = size.height / 2
      let weftThickness = size.height * 0.16
      context.fill(
        Path(CGRect(x: 0, y: y - weftThickness / 2, width: size.width, height: weftThickness)),
        with: .color(Palette.indigo)
      )
    }
    .accessibilityHidden(true)
  }
}
