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
  @State private var isCancelExpanded = false
  @State private var weaveProgress: CGFloat = 0

  var body: some View {
    VStack(spacing: 0) {
      if model.state != .saved {
        LiquidGlassCancelHeader(
          isExpanded: $isCancelExpanded,
          title: "Tsumugi に紡ぐ",
          expandOnCloseTap: model.state == .ready,
          primaryLabel: "閉じる",
          primarySymbol: "xmark",
          primaryIsDestructive: true,
          secondaryLabel: "このまま紡ぐ",
          secondarySymbol: "tray.and.arrow.down",
          onPrimary: onCancel,
          onSecondary: onSave,
          onImmediateDismiss: onCancel
        ) {
          ElasticSendButton(
            isEnabled: model.state == .ready,
            symbolName: "arrow.up",
            accessibilityLabelText: "保存",
            size: 40,
            action: onSave
          )
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Palette.ground.opacity(0.92))
        .overlay(alignment: .bottom) {
          Rectangle().fill(Palette.rule).frame(height: Radius.hairline)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
      }

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
    }
    .background(WashiBackground())
    .animation(ElasticMotion.toastOpen, value: model.state)
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
                    withAnimation(ElasticMotion.liquidClose) {
                      model.tags.removeAll { $0 == tag }
                    }
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                      .font(.caption2)
                      .foregroundStyle(.tertiary)
                  }
                  .buttonStyle(SquishyPillButtonStyle(pressScaleX: 1.15, pressScaleY: 0.85))
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .overlay {
                  RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(Palette.rule, lineWidth: Radius.hairline)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
              }
            }
          }
        }

        HStack(spacing: Spacing.sm) {
          TextField("タグを追加（任意）", text: $tagInput)
            .autocorrectionDisabled()
            .onSubmit(addTag)
          ElasticSendButton(
            isEnabled: !tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            symbolName: "plus",
            accessibilityLabelText: "タグを追加",
            size: 32,
            action: addTag
          )
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
    VStack(spacing: Spacing.lg) {
      // 経糸が一本増えた, という見立て.
      WeaveMark(weftProgress: weaveProgress)
        .frame(width: 84, height: 46)
        .scaleEffect(weaveProgress > 0 ? 1.0 : 0.78)

      JellyToastPill(message: "紡ぎました", icon: "checkmark.circle.fill")

      Text("アプリを開くと診断が始まります.")
        .font(.footnote)
        .foregroundStyle(Palette.inkMuted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WashiBackground())
    .onAppear {
      withAnimation(ElasticMotion.toastOpen) {
        weaveProgress = 1.0
      }
    }
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
    withAnimation(ElasticMotion.jellyPop) {
      model.tags.append(name)
    }
    tagInput = ""
  }
}

/// 保存できたことを示す小さな織り. 経糸に緯糸が一本通った形.
struct WeaveMark: View, @MainActor Animatable {
  var weftProgress: CGFloat = 1.0

  nonisolated var animatableData: CGFloat {
    get { weftProgress }
    set { weftProgress = newValue }
  }

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
      let weftWidth = max(0, min(1, weftProgress)) * size.width
      context.fill(
        Path(CGRect(x: 0, y: y - weftThickness / 2, width: weftWidth, height: weftThickness)),
        with: .color(Palette.indigo)
      )
    }
    .accessibilityHidden(true)
  }
}
