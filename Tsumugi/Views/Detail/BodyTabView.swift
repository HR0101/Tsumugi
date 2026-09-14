//
//  BodyTabView.swift
//  Tsumugi
//
//  仕様書 5.2: 詳細画面の「本文」タブ.
//  抽出した本文の先頭を表示し, リーダービュー（S-06）への導線を置く.
//

import SwiftUI
import SwiftData

struct BodyTabView: View {
  let item: Item
  let onOpenReader: () -> Void

  /// タブ内で表示する文字数の上限. 全文はリーダービューで読む.
  private let previewLength = 1_200

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      if let bodyText = item.bodyText, !bodyText.isEmpty {
        VStack(alignment: .leading, spacing: Spacing.md) {
          HStack {
            Text("本文（\(item.charCount) 文字）").sectionTitleStyle()
            Spacer()
            Button {
              onOpenReader()
            } label: {
              Label("リーダーで読む", systemImage: "doc.text")
                .font(.caption)
            }
          }

          Text(preview(of: bodyText))
            .font(.callout)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)

          if bodyText.count > previewLength {
            Button(action: onOpenReader) {
              Label("続きを読む", systemImage: "arrow.right")
                .font(.footnote.weight(.medium))
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperPanel()

        if !item.highlights.isEmpty {
          highlightsSection
        }

        licenseNotice
      } else {
        EmptyStateView(
          symbolName: "doc.questionmark",
          title: "本文を取得できていません",
          message: item.status == .unsupportedFormat
            ? "PDF や動画は現在のバージョンでは未対応です. 原文リンクからご確認ください."
            : "ペイウォールや JavaScript で描画されるページでは本文を取得できないことがあります. 共有シートから保存し直すと取得できる場合があります."
        )
        .frame(maxWidth: .infinity)
      }
    }
  }

  private var highlightsSection: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      Text("ハイライト（\(item.highlights.count)）").sectionTitleStyle()
      ForEach(item.highlights.sorted { $0.createdAt < $1.createdAt }) { highlight in
        VStack(alignment: .leading, spacing: Spacing.xs) {
          QuoteBlock(quote: highlight.quote)
          if !highlight.note.isEmpty {
            Text(highlight.note)
              .font(.caption)
              .foregroundStyle(Palette.inkMuted)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .paperPanel()
  }

  /// 仕様書 10.6: 著作権に関する扱いを明示する.
  private var licenseNotice: some View {
    Label(
      "保存した本文は私的複製の範囲でこの端末にのみ保持されます. 他の人と共有できるのは原文リンクと自分で書いたメモ・要約だけです.",
      systemImage: "lock.doc"
    )
    .font(.caption2)
    .foregroundStyle(Palette.inkMuted.opacity(0.72))
    .fixedSize(horizontal: false, vertical: true)
  }

  private func preview(of text: String) -> String {
    guard text.count > previewLength else { return text }
    return String(text.prefix(previewLength)) + "…"
  }
}
