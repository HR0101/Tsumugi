//
//  AnalysisPrompts.swift
//  Tsumugi
//
//  仕様書 9.2: 診断プロンプト. 仕様書 4.4.4 の設計原則をプロンプト側で強制する.
//

import Foundation

enum AnalysisPrompts {

  /// 本文をプロンプトへ載せる際の上限. 長文は先頭を優先して切り詰める.
  static let maxBodyLength = 24_000

  // MARK: - 信頼度診断（仕様書 9.2）

  static let credibilitySystem = """
  あなたは情報リテラシー教育の専門家です。与えられた記事について、
  「主張内容の政治的・思想的な正しさ」ではなく、
  「情報提示の作法（検証可能性・透明性・出典の質）」のみを評価してください。

  ## 絶対に守るルール
  1. 政治的立場、宗教、思想の是非を評価対象にしない。
  2. 評価は必ず記事本文とメタデータから引用できる事実に基づく。
  3. 判断できない項目は推測せず、その項目の determined を false にし、confidence を "low" とする。
  4. 各スコアには必ず本文からの引用（60字以内が望ましく、120字を超えてはならない）を根拠として添える。
     引用は本文に一字一句存在する文字列でなければならない。要約や言い換えを引用として書いてはならない。
  5. 医療・金融・法律に関する記事は該当フラグ（medical_ymyl / financial_ymyl）を立て、専門家確認を促す。
  6. 「このサイトはフェイクニュースである」のような断定表現を出力しない。
     「出典の提示が少ない」のような記述的表現に限定する。

  ## 各カテゴリの評価観点
  - source（発信元）: ドメインの性質、運営者情報の有無、既知の評価。
  - transparency（透明性）: 著者名、著者プロフィール、発行日・更新日、修正履歴、問い合わせ先。
  - evidence（論拠の質）: 出典リンクの数と質（一次情報／論文／公的機関／二次まとめ）、数値の出所。
  - neutrality（中立性）: 煽動的表現、断定過多、感情語密度、クリックベイト見出し、広告・アフィリエイト密度。
  - corroboration（外部照合）: 他ソースとの一致・矛盾。参照できる情報がない場合は determined を false にする。

  出力は指定された JSON スキーマに厳密に従うこと。
  """

  static func credibilityUser(_ input: AnalysisInput) -> String {
    let reputation = input.domainReputation ?? DomainReputationTable.reputation(for: input.host)
    let outbound = input.outboundLinks.prefix(20).map { link in
      "- \(link.url)\(link.isAuthoritative ? "（一次情報・公的機関・学術の可能性）" : "")"
    }.joined(separator: "\n")

    return """
    ## 入力
    - URL: \(input.canonicalURL)
    - ドメイン評価（既知情報）: \(reputation.category.displayName) / 基礎スコア \(reputation.baseScore) / \(reputation.notes)
    - サイト名: \(input.siteName ?? "不明")
    - 著者: \(input.author ?? "不明")
    - 発行日: \(formatted(input.publishedAt)) / 更新日: \(formatted(input.updatedAt))
    - 外部リンク数: \(input.outboundLinks.count) 件（うち一次情報候補 \(input.authoritativeLinkCount) 件）
    - 広告・アフィリエイトリンク数: \(input.affiliateLinkCount)
    - 外部リンク一覧:
    \(outbound.isEmpty ? "（外部リンクなし）" : outbound)

    ## 記事タイトル
    \(input.title)

    ## 本文
    \(truncateBody(input.bodyText))

    ## 出力
    credibility_report スキーマに厳密に従った JSON のみを出力する。
    """
  }

  // MARK: - 要約（仕様書 4.3）

  static func summarySystem(language: String) -> String {
    """
    あなたは正確さを最優先する編集者です。与えられた記事を要約してください。

    ## 絶対に守るルール
    1. 原文に書かれていない事実を一切追加しない。推測・補完・一般常識の付け足しを禁じる。
    2. 数値・固有名詞・日付は原文の表記をそのまま用いる。単位換算や概算への置き換えを禁じる。
    3. 記事の「主張」と、その主張を支えるために記事が挙げている「根拠」を分けて記述する。
    4. 記事が断定していない事柄を断定形で書かない。原文が「とされる」なら要約も留保を保つ。
    5. 出力言語は \(languageName(language)) とする。原文の言語が何であってもこれに従う。

    ## 粒度
    - tldr: 1〜2 文。記事全体の要点。
    - key_points: 3〜7 項目。それぞれ 1 文。
    - detailed: 400〜800 字程度の要約。

    出力は指定された JSON スキーマに厳密に従うこと。
    """
  }

  static func summaryUser(_ input: AnalysisInput) -> String {
    var prompt = """
    ## 記事タイトル
    \(input.title)

    ## 出典
    \(input.siteName ?? input.host) / 著者: \(input.author ?? "不明") / 発行日: \(formatted(input.publishedAt))

    ## 本文
    \(truncateBody(input.bodyText))
    """

    if let selection = input.selection, selection.count >= 10 {
      prompt += """


      ## 読者がハイライトした箇所
      次の箇所を読者は重要とみなしています。要約ではこの箇所に関係する内容を優先的に含めてください。
      \(selection.prefix(400))
      """
    }
    return prompt
  }

  // MARK: - 鮮度診断（仕様書 4.5）

  static let freshnessSystem = """
  あなたは技術文書のメンテナンス担当者です。与えられた記事について、
  「情報がどれだけ古くなっている可能性があるか」を判定してください。
  主張の正しさではなく、「時間の経過によって前提が変わっていないか」だけを見ます。

  ## 手順
  1. 記事のトピックを次の分類から 1 つ選ぶ:
     ai（AI・生成AI） / software（ソフトウェア・ライブラリ） / hardware（ハードウェア）
     / market（市況・経済指標） / regulation（法令・制度・税制） / medical（医療・健康）
     / academic（学術・基礎研究） / news（速報性のあるニュース） / howto（普遍的ハウツー）
     / timeless（歴史・古典・数学など時間で古くならない知識）
  2. 次の補正のうち、記事から根拠を引用できるものだけを adjustments に挙げる:
     - update_history: 発行日より新しい更新日が明記されている
     - version_outdated: 本文中の製品・API バージョンが現行より 2 世代以上古い
     - year_outdated: 「2023年最新」のように、現在より 2 年以上前の年号を見出しに含む
     - deprecated: 言及されている技術・制度が廃止または非推奨であると明確に読み取れる
     - successor_exists: 記事自身が「続編」「更新版」の存在に言及している
  3. 「執筆時点」を前提にした記述のうち、いま読むと誤解を生みうるものを obsolete_points に挙げる。
     quote は本文に一字一句存在する文字列でなければならない（120字以内）。

  ## 禁止事項
  - 推測で補正を追加しない。根拠を引用できない補正は挙げない。
  - スコアそのものは計算しない。判定材料のみを返す。

  出力は指定された JSON スキーマに厳密に従うこと。
  """

  static func freshnessUser(_ input: AnalysisInput) -> String {
    """
    ## 現在日時
    \(formatted(input.now))

    ## 記事タイトル
    \(input.title)

    ## 見出し
    \(input.headings.prefix(20).joined(separator: "\n"))

    ## 発行日 / 更新日
    \(formatted(input.publishedAt)) / \(formatted(input.updatedAt))

    ## 本文
    \(truncateBody(input.bodyText))
    """
  }

  // MARK: - タグ提案（仕様書 LB-07）

  static let tagSystem = """
  あなたは記事に検索用のタグを付ける司書です。
  記事の主題を表す 3〜5 個の短いタグ（各 20 文字以内）を提案してください。
  記事に書かれていない話題のタグを付けてはいけません。
  """

  static func tagUser(_ input: AnalysisInput) -> String {
    """
    ## タイトル
    \(input.title)

    ## 本文の冒頭
    \(input.bodyText.prefix(2_000))
    """
  }

  // MARK: - 補助

  private static func truncateBody(_ body: String) -> String {
    guard body.count > maxBodyLength else { return body }
    // 仕様書 SM-05 の map-reduce 要約は v1.0 では未実装のため,
    // 上限を超える場合は冒頭を優先して切り詰め, その旨を明示する.
    return String(body.prefix(maxBodyLength)) + "\n\n（本文はここで切り詰められています）"
  }

  private static func formatted(_ date: Date?) -> String {
    guard let date else { return "不明" }
    return dateFormatter.string(from: date)
  }

  private static func languageName(_ code: String) -> String {
    switch code {
    case "ja": return "日本語"
    case "en": return "英語"
    case "zh": return "中国語"
    case "ko": return "韓国語"
    default: return code
    }
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yyyy年M月d日"
    return formatter
  }()
}
