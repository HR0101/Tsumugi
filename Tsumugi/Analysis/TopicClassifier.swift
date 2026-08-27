//
//  TopicClassifier.swift
//  Tsumugi
//
//  仕様書 4.5.1 / 9.1: トピック分類（小型モデル相当の処理をオンデバイスの辞書で近似する）.
//

import Foundation

/// 記事のトピックを分類する.
enum TopicClassifier {

  /// トピックごとの手がかり語. 重みは語の識別力に応じて設定している.
  private static let signals: [TopicClass: [(term: String, weight: Double)]] = [
    .ai: [
      ("生成AI", 3), ("LLM", 3), ("大規模言語モデル", 3), ("機械学習", 2), ("ディープラーニング", 2),
      ("プロンプト", 2), ("推論コスト", 3), ("GPT", 2), ("Claude", 2), ("Gemini", 2),
      ("トークン", 1.5), ("ファインチューニング", 2.5), ("埋め込み", 1.5), ("AIエージェント", 3),
      ("machine learning", 2), ("neural network", 2), ("transformer", 2)
    ],
    .software: [
      ("ライブラリ", 2), ("フレームワーク", 2), ("API", 1.5), ("SDK", 2), ("リファクタ", 2),
      ("チュートリアル", 2), ("実装", 1), ("バージョン", 1.5), ("インストール", 2), ("デプロイ", 2),
      ("TypeScript", 2), ("Swift", 2), ("Python", 2), ("React", 2), ("Docker", 2),
      ("npm", 2), ("git", 1.5), ("コンパイル", 2), ("パッケージ", 1.5)
    ],
    .hardware: [
      ("スマートフォン", 2), ("レビュー", 1), ("バッテリー", 2), ("ディスプレイ", 2), ("チップ", 2),
      ("iPhone", 2), ("MacBook", 2), ("GPU", 2), ("CPU", 2), ("実機", 2), ("開封", 2),
      ("スペック", 2), ("ベンチマーク", 2)
    ],
    .market: [
      ("株価", 3), ("為替", 3), ("円安", 3), ("円高", 3), ("日経平均", 3), ("景況感", 3),
      ("金利", 2.5), ("インフレ", 2.5), ("決算", 2), ("相場", 2.5), ("利上げ", 2.5),
      ("GDP", 2), ("市況", 3), ("investment", 2)
    ],
    .regulation: [
      ("法律", 2.5), ("改正", 2.5), ("施行", 3), ("補助金", 3), ("税率", 3), ("税制", 3),
      ("規制", 2.5), ("ガイドライン", 2), ("省令", 3), ("条例", 3), ("義務化", 2.5),
      ("控除", 2.5), ("申請", 1.5), ("制度", 2)
    ],
    .medical: [
      ("治療", 3), ("症状", 3), ("疾患", 3), ("投薬", 3), ("副作用", 3), ("診断", 2),
      ("ワクチン", 3), ("臨床", 3), ("健康", 1.5), ("サプリ", 2),
      ("医師", 2), ("患者", 2.5), ("処方", 3)
    ],
    .academic: [
      ("論文", 3), ("研究", 2), ("実験", 2.5), ("被験者", 3), ("仮説", 2.5), ("有意差", 3),
      ("査読", 3), ("学会", 2.5), ("理論", 2), ("定理", 3), ("証明", 2)
    ],
    .news: [
      ("発表した", 2), ("速報", 3), ("会見", 2.5), ("事故", 2.5), ("災害", 2.5), ("逮捕", 3),
      ("本日", 2), ("昨日", 2), ("記者", 2), ("判明した", 2), ("公表した", 2)
    ],
    .howto: [
      ("作り方", 3), ("方法", 1.5), ("手順", 2), ("コツ", 2.5), ("レシピ", 3), ("入門", 2),
      ("使い方", 2.5), ("初心者", 2), ("おすすめ", 1), ("やり方", 2.5), ("書き方", 2.5)
    ],
    .timeless: [
      ("歴史", 2.5), ("古代", 3), ("中世", 3), ("哲学", 2.5), ("数学", 2), ("語源", 3),
      ("由来", 2), ("世紀", 2.5), ("古典", 3)
    ]
  ]

  /// 分類が成立したとみなす最低スコア. 下回った場合は `software`（既定の半減期 240 日）とする.
  private static let confidenceThreshold = 4.0

  /// タイトル・見出し・本文からトピックを判定する.
  /// タイトルと見出しは本文より強い手がかりとして重み付けする.
  static func classify(title: String, headings: [String], body: String) -> TopicClass {
    let titleText = title + "\n" + headings.joined(separator: "\n")
    let bodyText = String(body.prefix(6_000))

    var scores: [TopicClass: Double] = [:]
    for (topic, terms) in signals {
      var score = 0.0
      for (term, weight) in terms {
        let inTitle = countOccurrences(of: term, in: titleText)
        let inBody = countOccurrences(of: term, in: bodyText)
        // タイトル中の語は 3 倍, 本文は出現回数の平方根で頭打ちにする.
        score += Double(inTitle) * weight * 3.0
        score += min(Double(inBody).squareRoot(), 4.0) * weight
      }
      scores[topic] = score
    }

    guard let best = scores.max(by: { $0.value < $1.value }), best.value >= confidenceThreshold else {
      return .software
    }
    return best.key
  }

  private static func countOccurrences(of term: String, in text: String) -> Int {
    guard !term.isEmpty else { return 0 }
    return text.lowercased().components(separatedBy: term.lowercased()).count - 1
  }
}
