//
//  SettingsView.swift
//  Tsumugi
//
//  仕様書 S-09: 設定.
//  出力言語 / 診断の厳しさ / 通知 / 課金 / データ管理 / プライバシー.
//

import SwiftUI
import SwiftData

struct SettingsView: View {

  @Environment(SettingsStore.self) private var settingsStore
  @Environment(IngestService.self) private var ingest
  @Environment(\.modelContext) private var modelContext
  @Query private var items: [Item]

  @State private var isShowingAPIKeyEditor = false
  @State private var isShowingDeleteConfirmation = false
  @State private var isRunningBatch = false
  @State private var batchResultMessage: String?

  var body: some View {
    @Bindable var settings = settingsStore

    NavigationStack {
      Form {
        analysisSection($settings)
        providerSection($settings)
        notificationSection($settings)
        quotaSection
        librarySection
        privacySection
        aboutSection
      }
      .scrollContentBackground(.hidden)
      .background(WashiBackground())
      .navigationTitle("設定")
      .sheet(isPresented: $isShowingAPIKeyEditor) {
        APIKeyEditor()
      }
      .alert("すべてのデータを削除しますか", isPresented: $isShowingDeleteConfirmation) {
        Button("キャンセル", role: .cancel) {}
        Button("削除", role: .destructive) { deleteAllData() }
      } message: {
        Text("保存した記事・要約・診断結果・タグ・メモがすべて消えます. この操作は取り消せません.")
      }
      .alert(
        "再評価が完了しました",
        isPresented: Binding(
          get: { batchResultMessage != nil },
          set: { if !$0 { batchResultMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) { batchResultMessage = nil }
      } message: {
        Text(batchResultMessage ?? "")
      }
    }
  }

  // MARK: - 診断

  private func analysisSection(_ settings: Bindable<SettingsStore>) -> some View {
    Section {
      Picker("出力言語", selection: settings.outputLanguage) {
        Text("日本語").tag("ja")
        Text("English").tag("en")
        Text("中文").tag("zh")
        Text("한국어").tag("ko")
      }

      Picker("診断の厳しさ", selection: settings.strictness) {
        ForEach(AnalysisStrictness.allCases, id: \.self) { value in
          Text(value.displayName).tag(value)
        }
      }
      Text(settings.wrappedValue.strictness.detail)
        .font(.caption)
        .foregroundStyle(Palette.inkMuted)

      Toggle("段階的診断", isOn: settings.stagedAnalysisEnabled)
      Text("有効にすると, 保存時は本文抽出と要約だけを行い, 信頼度・鮮度の診断は記事を開いたときに実行します. 読まない記事の診断コストを抑えられます.")
        .font(.caption)
        .foregroundStyle(Palette.inkMuted)
    } header: {
      Text("診断")
    }
  }

  // MARK: - AI プロバイダ

  private func providerSection(_ settings: Bindable<SettingsStore>) -> some View {
    Section {
      Picker("使用するプロバイダ", selection: settings.providerMode) {
        ForEach(ProviderMode.allCases, id: \.self) { mode in
          Text(mode.displayName).tag(mode)
        }
      }

      HStack {
        Text("現在の診断エンジン")
        Spacer()
        Text(settingsStore.activeProviderName)
          .font(.footnote)
          .foregroundStyle(Palette.inkMuted)
      }

      Button {
        isShowingAPIKeyEditor = true
      } label: {
        HStack {
          Text("Claude API キー")
          Spacer()
          Text(settingsStore.isClaudeConfigured ? "設定済み" : "未設定")
            .font(.footnote)
            .foregroundStyle(settingsStore.isClaudeConfigured ? .secondary : Color.orange)
        }
      }

      if let error = settingsStore.keychainError {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(Palette.color(for: .caution))
      }

      ForEach(ModelTier.allCases, id: \.self) { tier in
        HStack {
          Text(tier.displayName)
          Spacer()
          Text(settingsStore.modelIDs[tier] ?? tier.defaultModelID)
            .font(.caption.monospaced())
            .foregroundStyle(Palette.inkMuted)
        }
      }
    } header: {
      Text("AI プロバイダ")
    } footer: {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text("API キーが未設定の場合は, 端末内で完結するルールベース診断が使われます. 通信を一切行わないため, 記事の内容が外部へ送信されることはありません.")
        Label(
          "アプリに API キーを直接持たせる構成は, 端末を解析された場合にキーが漏れる可能性があります. 個人利用の範囲でお使いください.",
          systemImage: "exclamationmark.shield"
        )
        .foregroundStyle(Palette.color(for: .caution))
      }
      .font(.caption)
    }
  }

  // MARK: - 通知

  private func notificationSection(_ settings: Bindable<SettingsStore>) -> some View {
    Section {
      Toggle("診断完了を通知する", isOn: settings.notificationsEnabled)
      Toggle("週次ダイジェストを受け取る", isOn: settings.weeklyDigestEnabled)

      Button {
        Task { await runStalenessBatch() }
      } label: {
        HStack {
          Text("いま鮮度を再評価する")
          Spacer()
          if isRunningBatch { ProgressView().controlSize(.small) }
        }
      }
      .disabled(isRunningBatch || items.isEmpty)
    } header: {
      Text("通知")
    } footer: {
      Text("週次ダイジェストでは, 保存済みの記事のうち新たに陳腐化した可能性のあるものをお知らせします. 鮮度の再評価は時間経過だけで計算できるため, AI の呼び出しは発生しません.")
    }
  }

  // MARK: - 利用量

  private var quotaSection: some View {
    Section {
      HStack {
        Text("今月の AI 診断")
        Spacer()
        Text("\(settingsStore.monthlyAnalysisCount) / \(SettingsStore.freeMonthlyAnalysisLimit) 件")
          .font(.footnote.monospacedDigit())
          .foregroundStyle(settingsStore.hasExceededFreeQuota ? Color.orange : .secondary)
      }
      ProgressView(
        value: Double(min(settingsStore.monthlyAnalysisCount, SettingsStore.freeMonthlyAnalysisLimit)),
        total: Double(SettingsStore.freeMonthlyAnalysisLimit)
      )
    } header: {
      Text("利用量")
    } footer: {
      Text("無料枠を超えた場合も要約は引き続き利用できます（仕様の Free プラン相当）. オンデバイス診断は上限の対象外です.")
    }
  }

  // MARK: - ライブラリ

  private var librarySection: some View {
    Section("ライブラリ") {
      NavigationLink {
        TagManagerView()
      } label: {
        Label("タグ管理", systemImage: "number")
      }

      HStack {
        Text("保存済みの記事")
        Spacer()
        Text("\(items.count) 件")
          .font(.footnote)
          .foregroundStyle(Palette.inkMuted)
      }

      HStack {
        Text("未読")
        Spacer()
        Text("\(items.filter { !$0.isRead }.count) 件")
          .font(.footnote)
          .foregroundStyle(Palette.inkMuted)
      }
    }
  }

  // MARK: - プライバシーとデータ管理

  private var privacySection: some View {
    Section {
      HStack {
        Text("共有コンテナ（App Group）")
        Spacer()
        Text(AppGroup.isSharedContainerAvailable ? "有効" : "未設定")
          .font(.footnote)
          .foregroundStyle(AppGroup.isSharedContainerAvailable ? .secondary : Color.orange)
      }

      Button(role: .destructive) {
        isShowingDeleteConfirmation = true
      } label: {
        Label("すべてのデータを削除", systemImage: "trash")
      }
    } header: {
      Text("プライバシーとデータ管理")
    } footer: {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        Text("保存した記事の本文はこの端末にのみ保持され, 私的複製の範囲で利用します. 他の人と共有できるのは原文リンクと自分で書いたメモ・要約だけです.")
        Text("App Group が「未設定」と表示される場合, Share Extension との共有コンテナが使えていません. Xcode の Signing & Capabilities で App Groups に「\(AppGroup.identifier)」を追加してください.")
      }
      .font(.caption)
    }
  }

  private var aboutSection: some View {
    Section {
      NavigationLink {
        OnboardingView(isPresentedAsSheet: false)
      } label: {
        Label("使い方と診断の限界について", systemImage: "questionmark.circle")
      }
    } header: {
      Text("このアプリについて")
    } footer: {
      Text("この診断は AI による自動評価であり, 正確性を保証するものではありません. 評価対象は情報の提示方法（出典・透明性・検証可能性）であり, 主張内容の正しさや思想的な立場を判定するものではありません. 最終的な判断はご自身で行ってください.")
    }
  }

  // MARK: - 操作

  private func runStalenessBatch() async {
    isRunningBatch = true
    let count = await ingest.refreshStalenessBatch()
    isRunningBatch = false
    batchResultMessage = count > 0
      ? "\(count) 件が新たに「陳腐化の可能性が高い」に変わりました."
      : "新たに陳腐化した記事はありませんでした."
  }

  private func deleteAllData() {
    for item in items {
      modelContext.delete(item)
    }
    if let tags = try? modelContext.fetch(FetchDescriptor<Tag>()) {
      for tag in tags { modelContext.delete(tag) }
    }
    if let feedbacks = try? modelContext.fetch(FetchDescriptor<AnalysisFeedback>()) {
      for feedback in feedbacks { modelContext.delete(feedback) }
    }
    try? modelContext.save()
  }
}

/// API キーを入力するシート. 入力値は Keychain に保管する（仕様書 10.3）.
struct APIKeyEditor: View {

  @Environment(SettingsStore.self) private var settings
  @Environment(\.dismiss) private var dismiss

  @State private var keyInput = ""
  @State private var isRevealed = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          if isRevealed {
            TextField("sk-ant-…", text: $keyInput)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .font(.callout.monospaced())
          } else {
            SecureField("sk-ant-…", text: $keyInput)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }

          Toggle("入力内容を表示", isOn: $isRevealed)
        } header: {
          Text("Claude API キー")
        } footer: {
          Text("キーは端末の Keychain に保存されます（アプリのアンロック後にのみ読み出せる設定）. 空にして保存すると削除され, オンデバイス診断に戻ります.")
        }

        Section {
          Label(
            "API キーを端末に置く構成は, 端末が解析された場合に漏洩する可能性があります. 本番運用ではサーバ側にキーを置き, アプリはサーバ経由で診断を依頼する構成をおすすめします.",
            systemImage: "exclamationmark.shield"
          )
          .font(.caption)
          .foregroundStyle(Palette.color(for: .caution))
        }

        Section {
          Label("記事の本文と URL が Anthropic の API へ送信されます.", systemImage: "arrow.up.forward")
          Label("送信したくない記事がある場合は「オンデバイスのみ」を選んでください.", systemImage: "iphone")
        }
        .font(.caption)
        .foregroundStyle(Palette.inkMuted)
      }
      .scrollContentBackground(.hidden)
      .background(WashiBackground())
      .navigationTitle("API キー")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            settings.apiKey = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            dismiss()
          }
        }
      }
      .onAppear { keyInput = settings.apiKey ?? "" }
    }
  }
}
