//
//  OnboardingView.swift
//  Tsumugi
//
//  仕様書 S-10: オンボーディング.
//  共有シートへの追加手順と, 診断の限界に関する説明.
//  仕様書 14「診断結果への過度な依存」への対策として, 限界の説明を必ず通る導線に置く.
//

import SwiftUI

struct OnboardingView: View {

  /// シートとして表示しているか. 設定画面から開いた場合は false.
  var isPresentedAsSheet: Bool = true

  @Environment(SettingsStore.self) private var settings
  @Environment(\.dismiss) private var dismiss
  @State private var page = 0

  private let pageCount = 3

  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $page) {
        sharePage.tag(0)
        diagnosisPage.tag(1)
        limitationPage.tag(2)
      }
      .tabViewStyle(.page(indexDisplayMode: .always))
      .indexViewStyle(.page(backgroundDisplayMode: .always))

      footer
    }
    .background(Palette.canvas)
    .navigationTitle("使い方")
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: - ページ 1: 共有シートへの追加

  private var sharePage: some View {
    OnboardingPage(
      symbolName: "square.and.arrow.up",
      title: "共有シートから保存",
      message: "Safari やほかのアプリで記事を開き, 共有ボタンから Tsumugi を選ぶだけで保存できます."
    ) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        stepRow(number: 1, text: "記事を開いて共有ボタン（\(Image(systemName: "square.and.arrow.up"))）をタップ")
        stepRow(number: 2, text: "アプリ一覧を右へスクロールし「その他」をタップ")
        stepRow(number: 3, text: "「Tsumugi」を有効にして, 上のほうへ並べ替え")
        stepRow(number: 4, text: "次回から共有シートに Tsumugi が現れます")

        Label(
          "オフラインでも保存できます. 通信が戻ったときに本文の取得と診断を実行します.",
          systemImage: "wifi.slash"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, Spacing.sm)
      }
    }
  }

  // MARK: - ページ 2: 何を診断するのか

  private var diagnosisPage: some View {
    OnboardingPage(
      symbolName: "checkmark.seal",
      title: "2 つのスコアで見分ける",
      message: "保存した記事に「信頼度」と「情報の新しさ」のスコアを付けます."
    ) {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        featureRow(
          symbolName: "checkmark.seal.fill",
          color: Palette.color(for: .high),
          title: "信頼度",
          detail: "発信元・透明性・論拠の質・中立性・外部照合の 5 項目を重み付けして 0〜100 で表します. どの項目が何点だったか, その根拠は何かをすべて確認できます."
        )
        featureRow(
          symbolName: "leaf.fill",
          color: Palette.color(for: .current),
          title: "情報の新しさ",
          detail: "分野ごとの「情報の半減期」を使い, 時間経過で情報がどれだけ古くなったかを計算します. AI 分野は 120 日, 法令は 500 日といった具合です."
        )
        featureRow(
          symbolName: "text.alignleft",
          color: .accentColor,
          title: "3 段階の要約",
          detail: "TL;DR・キーポイント・詳細要約の 3 つの粒度で要約します. 記事が挙げた主張と根拠も分けて取り出します."
        )
      }
    }
  }

  // MARK: - ページ 3: 診断の限界（必読）

  private var limitationPage: some View {
    OnboardingPage(
      symbolName: "exclamationmark.triangle",
      title: "この診断の限界",
      message: "スコアを鵜呑みにしないでください. 何を判定していて, 何を判定していないかをご確認ください."
    ) {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        limitationRow(
          symbolName: "checkmark.circle",
          title: "判定していること",
          detail: "出典が示されているか, 著者と日付が明記されているか, 表現が扇動的でないか — つまり「情報の提示の作法」です."
        )
        limitationRow(
          symbolName: "xmark.circle",
          title: "判定していないこと",
          detail: "書かれている主張が事実かどうか, 政治的・思想的に正しいかどうかは判定しません. 作法が整った記事でも内容が誤っていることはあります."
        )
        limitationRow(
          symbolName: "person.fill.questionmark",
          title: "最終判断はご自身で",
          detail: "AI の判定は参考情報です. 医療・金融・法律に関わる内容は, 必ず専門家にご確認ください."
        )

        DiagnosisDisclaimer()
      }
    }
  }

  // MARK: - 部品

  private var footer: some View {
    VStack(spacing: Spacing.md) {
      if page < pageCount - 1 {
        Button {
          withAnimation { page += 1 }
        } label: {
          Text("次へ").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      } else {
        Button {
          settings.hasCompletedOnboarding = true
          if isPresentedAsSheet { dismiss() }
        } label: {
          Text(isPresentedAsSheet ? "内容を理解して始める" : "閉じる").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }

      if isPresentedAsSheet && page < pageCount - 1 {
        Button("スキップ") {
          settings.hasCompletedOnboarding = true
          dismiss()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, Spacing.xl)
    .padding(.bottom, Spacing.xl)
    .padding(.top, Spacing.md)
  }

  private func stepRow(number: Int, text: LocalizedStringKey) -> some View {
    HStack(alignment: .top, spacing: Spacing.md) {
      Text("\(number)")
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .frame(width: 22, height: 22)
        .background(Color.accentColor, in: Circle())
      Text(text)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func featureRow(symbolName: String, color: Color, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: Spacing.md) {
      Image(systemName: symbolName)
        .font(.title3)
        .foregroundStyle(color)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func limitationRow(symbolName: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: Spacing.md) {
      Image(systemName: symbolName)
        .font(.title3)
        .foregroundStyle(Color.accentColor)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// オンボーディングの 1 ページ分の共通レイアウト.
struct OnboardingPage<Content: View>: View {
  let symbolName: String
  let title: String
  let message: String
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.lg) {
        Image(systemName: symbolName)
          .font(.system(size: 44, weight: .light))
          .foregroundStyle(Color.accentColor)
          .padding(.top, Spacing.xl)

        Text(title)
          .font(.title2.weight(.bold))
          .fixedSize(horizontal: false, vertical: true)

        Text(message)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Spacing.xl)
      .padding(.bottom, Spacing.xxl)
    }
  }
}
