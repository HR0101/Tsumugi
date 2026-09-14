# Tsumugi — 記事保存・AI 診断アプリ

`仕様書.md`（記事保存・AI 診断アプリ 仕様書 v1.0）にもとづく iOS クライアントの実装です。
共有シートから保存した Web 記事に対して、**要約・信頼度診断・情報の新しさ診断**の 3 つを自動で行います。

---

## 1. 実装した範囲

今回の実装スコープは **iOS アプリ一式（本体アプリ＋Share Extension）** です。
仕様書 6.1 のサーバ側（Node.js / PostgreSQL / Redis / Worker Pool）は実装していません。
その代わり、診断パイプライン（仕様書 6.2）を**端末内で実行**する構成にしてあり、
サーバなしで保存から診断まで一通り動きます。

### 画面（仕様書 5.1）

| ID | 画面 | 実装 |
|---|---|---|
| S-01 | Share Extension シート | ✅ タイトル / サムネ / タグ / メモ / 保存 |
| S-02 | ライブラリ（ホーム） | ✅ 検索・フィルタチップ・カード / リスト切替・ソート |
| S-03 | Item 詳細 | ✅ スコアカード＋4 タブ（要約・本文・診断・メモ） |
| S-04 | 信頼度診断詳細 | ✅ 総合スコア / レーダーチャート / 根拠 / フラグ / 外部照合 |
| S-05 | 鮮度診断詳細 | ✅ ゲージ / 半減期グラフ / 補正 / 陳腐化ポイント / 後続情報 |
| S-06 | リーダービュー | ✅ フォント・行間・背景色・ハイライト・読み上げ |
| S-07 | 検索結果 | ✅ キーワード＋意味的近さの統合リスト |
| S-08 | タグ管理 | ✅ 一覧 / 件数 / リネーム / 統合 / 削除 |
| S-09 | 設定 | ✅ 言語・厳しさ・プロバイダ・通知・利用量・データ管理 |
| S-10 | オンボーディング | ✅ 共有シート追加手順＋診断の限界の説明 |
| S-11 | 週次ダイジェスト | ✅ 陳腐化アラート / 未読リマインド / 保存傾向 |

### 診断エンジン

仕様書 9.1 の「プロバイダ抽象化レイヤ」を `AnalysisProvider` プロトコルとして実装し、
2 つの実装を差し替えられるようにしています。

| プロバイダ | いつ使われるか | 特徴 |
|---|---|---|
| `HeuristicAnalysisProvider` | 既定（API キー未設定時） | 端末内で完結。通信なし。抽出型要約＋辞書・ドメイン評価によるルールベース診断 |
| `ClaudeAnalysisProvider` | 設定で API キーを登録したとき | Claude API（Messages API / Structured Output）で要約・信頼度・鮮度を判定 |

**どちらのプロバイダを使っても、総合スコアの合成は必ず決定的な関数で行います。**
LLM にスコアの数字を決めさせず、`CredibilityScoring.compose`（仕様書 9.4）と
`FreshnessScoring.compute`（仕様書 9.5）に通すことで、モデルを差し替えても採点基準が揺れません。

---

## 2. セットアップ

### 2.1 App Group（必須）

本体アプリと Share Extension は App Group `group.com.HR.Tsumugi` 経由で共有キューをやり取りします。
`.entitlements` には設定済みですが、**実機で動かす場合は Apple Developer で App Group の登録が必要**です。

1. Xcode で `Tsumugi` ターゲット → Signing & Capabilities → `+ Capability` → **App Groups**
2. `group.com.HR.Tsumugi` を追加（チェックを入れる）
3. `ShareExtension` ターゲットにも同じ手順で追加

未設定のままでもクラッシュはしません。`AppGroup.containerURL` がアプリ内のフォールバック先に切り替わり、
本体アプリ単体（URL 貼り付け保存）は動きます。設定画面の「共有コンテナ（App Group）」欄で状態を確認できます。

### 2.2 Claude API キー（任意）

設定 → AI プロバイダ → Claude API キー から登録します。キーは Keychain
（`kSecAttrAccessibleAfterFirstUnlock`）に保管されます。未設定ならオンデバイス診断で動作します。

> ⚠️ **セキュリティ上の注意**
> アプリに API キーを直接持たせる構成は、端末を解析された場合にキーが漏洩する可能性があります。
> 仕様書 6.1 / 10.3 の本来の構成は「API Gateway 経由でサーバがキーを保持する」ものです。
> 本実装は個人利用・検証用途に限定してください。

### 2.3 ビルドと実行

```bash
xcodebuild -project Tsumugi.xcodeproj -scheme Tsumugi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

xcodebuild test -project Tsumugi.xcodeproj -scheme Tsumugi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TsumugiTests
```

---

## 3. ディレクトリ構成

```
Tsumugi/
├── Models/        SwiftData モデルと列挙型（仕様書 7.3）
├── Core/          URL 正規化・本文抽出・日本語処理（仕様書 4.2 / 16.2）
├── Analysis/      診断エンジン（仕様書 4.4 / 4.5 / 9.x）
├── Services/      取り込み・設定・通知・Keychain（仕様書 6.2 / 10.3）
└── Views/
    ├── Components/  意匠の部品（織り・レーダー・半減期グラフ・スコア札）
    └── …            各画面（仕様書 5.x）
Shared/            本体アプリと Share Extension の共通コード
                   （WaTheme.swift に和の配色・書体・面の定義）
ShareExtension/    共有シート（仕様書 4.1 / 16.1）
TsumugiTests/      Swift Testing による単体・統合テスト
TsumugiUITests/    主要画面を通しで開く UI テスト
```

---

## 4. 仕様書との主な対応

| 仕様書 | 実装 |
|---|---|
| 4.1 Share Extension | `ShareExtension/ShareViewController.swift`, `SharePreprocessor.js` |
| 4.2 本文抽出 | `Core/ArticleExtractor.swift`（Readability 相当を自前実装） |
| 4.3 要約 | `Analysis/ExtractiveSummarizer.swift`, `AnalysisPrompts.swift` |
| 4.4 信頼度診断 | `Analysis/HeuristicAnalysisProvider.swift`, `ClaudeAnalysisProvider.swift` |
| 4.5 鮮度診断 | `Analysis/FreshnessScoring.swift`, `TopicClassifier.swift` |
| 6.2 処理パイプライン | `Analysis/AnalysisPipeline.swift`, `Services/IngestService.swift` |
| 9.3 出力スキーマ | `Analysis/AnalysisSchemas.swift`（JSON Schema による強制） |
| 9.4 スコア合成 | `Analysis/CredibilityScoring.swift` |
| 9.5 鮮度スコア | `Analysis/FreshnessScoring.swift` |
| 9.6 ハルシネーション対策 | `Analysis/GroundingValidator.swift` |
| 12.2 段階的診断 | `SettingsStore.stagedAnalysisEnabled` + `IngestService.runDeepAnalysisIfNeeded` |
| 16.2 URL 正規化 | `Shared/URLNormalizer.swift` |
| 16.3 必須表示文言 | `Views/Components/DisclaimerViews.swift` |

---

## 5. 仕様との差分・既知の制約

実装にあたり、仕様書の記述をそのまま適用できなかった点を挙げます。

### 5.1 `temperature = 0.2` / `seed` 固定（仕様書 9.1）

**適用していません。** 現行の Claude モデル（Opus 5 / Sonnet 5 など）は
`temperature` / `top_p` / `seed` を受け付けず、指定すると HTTP 400 になります。
再現性は次の 2 つで担保しています。

- 出力形式を JSON Schema（`output_config.format`）で強制する
- **スコアの数値は LLM に決めさせず**、決定的な合成関数（9.4 / 9.5）に通す

### 5.2 外部照合（仕様書 4.4.1 #5）と後続情報（4.5.3 `successors`）

Web 検索 API が必要なため、**判定していません**。
仕様書 9.6「不明の明示」に従い、推測でスコアを埋めることはせず
「判定できませんでした」として**重みを再正規化**します（外部照合の重み 0.15 を残り 4 項目へ配分）。
診断画面にもその旨を表示します。

### 5.3 サーバ側（仕様書 6.1 / 7.1 / 8.x）

未実装です。`items` / `summaries` / `credibility_reports` / `freshness_reports` に相当する
テーブル定義は SwiftData モデルとして 1 対 1 で写してあるため、
サーバを追加する際は `AnalysisProvider` と `IngestService` の差し替えで接続できます。

### 5.4 その他の未実装項目

| 仕様 | 状態 |
|---|---|
| LB-05 セマンティック検索（埋め込みベクトル） | 語の共起による近似で代替 |
| LB-10 エクスポート（Notion / Obsidian / Readwise） | 未実装（原文リンク＋要約の共有のみ） |
| LB-11 複数記事の横断要約 | 未実装 |
| LB-12 ウィジェット | 未実装 |
| OT-01 Action Extension | 未実装（Share Extension のみ） |
| OT-02 App Intents / Siri | 未実装 |
| OT-04 CloudKit 同期 | 未実装（entitlements のみ残置） |
| OT-05 Handoff | 未実装 |
| SM-05 長文の map-reduce 要約 | 24,000 字で切り詰め（切り詰めた旨をプロンプトに明示） |
| 12.3 StoreKit 2 課金 | 未実装（月間診断回数のカウントと無料枠フォールバックのみ） |
| PDF / 動画（3.2） | `unsupportedFormat` として保存し、その旨を表示 |

### 5.5 設計上の判断

- **抽出型要約**: オンデバイス要約は本文の文をそのまま選ぶ方式にしました。
  原文にない記述を生成しないため、仕様書 9.6 の Grounding 要件を構造的に満たします。
- **`version_outdated` 補正**: 現行バージョンを照会できないため、
  「バージョン番号への言及がある」かつ「更新の速い分野で 2 年以上経過」の場合のみ適用します。
- **`deprecated` 補正**: 外部知識なしでは検証できないため、オンデバイス診断では適用しません
  （Claude プロバイダ側では、記事から根拠を引用できる場合のみ適用します）。
- **AI タグの品質**: オンデバイスのタグ提案は `NaturalLanguage` の品詞解析にもとづくため、
  「知ら」のような活用語尾が混じることがあります。API キーを設定すると LLM 側で提案されます。

---

## 6. 法務・表示に関する実装（仕様書 10.6 / 16.3）

- 診断画面には必ず免責文言（仕様書 16.3）を表示します。
- 引用は 1 箇所 **120 字以内**に制限しています（`ObsoletePoint.quote`、`RationaleEntry.quote`）。
- 医療・金融分野の記事には YMYL フラグを立て、専門家への相談を促す固定文言を表示します。
- 本文の対外共有機能は実装していません。共有できるのは**原文リンクと自作の要約**のみです。
- 判定は「情報提示の作法」に限定し、「フェイクニュースである」等の断定表現は出力しません。

---

## 7. デザインについて

### 7.1 見立て

アプリ名の「紬（つむぎ）」は, 真綿から手で紡いだ糸を草木で染め, 手で織った布のことです。
散らばった記事を手元でより合わせ, 一枚の布に織り上げていく——という見立てを, そのまま画面の造りにしています。

**この見立ては装飾ではなく, 情報の構造そのものです。**

| 布 | アプリ |
|---|---|
| 経糸（たていと） | 信頼度。布を縦に支える骨格 |
| 緯糸（よこいと） | 鮮度。時間の流れに沿って横に渡していく糸 |
| 節（ふし） | 記事ごとの個体差。URL ハッシュから決まる |

記事詳細の冒頭には, その記事だけの「織り」（`WeaveSwatch`）を描いています。
経糸の色と密度が信頼度, 緯糸が鮮度を表し, スコアが低いほど糸が抜けて布は薄く透けます。
糸の太さのむらは URL ハッシュから決まるので, **同じ記事はいつも同じ布, 別の記事は必ず違う布**になります。

### 7.2 配色 — 草木染めの伝統色

化学染料のような彩度の高い色は使わず, 草木で染められる色に限定しています。

| 用途 | 色 |
|---|---|
| 地 | 生成り（明所） / 墨紺（暗所） |
| 面 | 白練 / 褐返 |
| 文字 | 墨 / 鈍色 |
| 操作・強調 | 藍 / 浅葱 |

診断の帯には意味のある順序を持たせています。

- **信頼度**: 常磐色 → 若竹色 → 山吹色 → 柿色 → 蘇芳
- **鮮度**: 若草色 → 刈安色 → 朽葉色 → 消炭色
  （新芽 → 刈り取り → 落ち葉 → 灰。**色の並びそのものが時間の経過を語る**ようにしています）

スコアには色名も併記します（「56 点 / 注意が必要 / 山吹色」）。
色だけに頼らない表示（仕様書 10.5）を満たしつつ, 配色の由来も伝わります。

### 7.3 書体と面

- **見出し・記事タイトル・スコアの数値**: ヒラギノ明朝 ProN（`Font.custom(_:relativeTo:)` で Dynamic Type に追従）
- **本文・操作系**: 角ゴシック（明朝は小さい文字で読みにくいため）
- **リーダービューの本文**: 既定を明朝, 設定でゴシックに切替可能
- 面は「浮くカード」ではなく**和紙の面**として扱い, 影を落とさず罫（けい）で仕切ります
- 角丸は 2〜3pt（和の造形は直線が基本）
- 地には和紙の繊維をうっすら重ねています（`WashiGrain`）

### 7.4 アプリアイコン

平織（ひらおり）——経糸と緯糸が一本ずつ交互に上下する, 紬の基本組織——を図案にしています。
藍に染めた糸を経・緯それぞれ一本ずつ通し, **十字絣（じゅうじがすり）**の形にしました。
この十字が, アプリで扱う 2 つの評価の交点にあたります。

### 7.5 アクセシビリティ

伝統色は彩度が低く明度差が付きにくいため, **配色のコントラスト比を回帰テストで固定**しています
（`TsumugiTests/PaletteContrastTests.swift`）。明所・暗所のいずれでも 4.5:1 以上を保ちます。

---

## 8. 動作確認の記録

- 単体・統合テスト: **78 ケースすべて成功**（`TsumugiTests`）
  スコア合成（9.4 / 9.5）、URL 正規化（16.2）、本文抽出（4.2）、
  ルールベース診断（4.4 / 4.5）、ハルシネーション対策（9.6）、
  取り込みパイプライン（6.2、SwiftData への永続化まで）を検証しています。
- UI テスト: `TsumugiUITests/TsumugiUIFlowTests` が主要 9 画面を通しで開けることを確認済み。
- シミュレータ（iPhone 17 Pro / iOS 26.5）で、App Group の共有キューに投入した記事 3 件が
  抽出 → 要約 → 信頼度 → 鮮度まで処理され、各画面に表示されることを確認しました。

---
