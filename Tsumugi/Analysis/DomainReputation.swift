//
//  DomainReputation.swift
//  Tsumugi
//
//  仕様書 7.1 `domain_reputations` / 4.4.1「発信元の評価」.
//
//  サーバ側の Domain Reputation API に相当する評価を, オンデバイスの表と規則で近似する.
//

import Foundation

/// ドメインの基礎評価.
struct DomainReputation: Sendable, Hashable {
  var domain: String
  /// 0〜100 の基礎スコア.
  var baseScore: Int
  var category: Category
  /// 編集方針・運営者情報のページを持つと分かっているか.
  var hasEditorialPolicy: Bool
  var notes: String

  enum Category: String, Sendable, Codable {
    case government
    case academic
    case majorMedia
    case techMedia
    case corporate
    case communityBlog
    case personalBlog
    case aggregator
    case unknown

    var displayName: String {
      switch self {
      case .government: return "公的機関"
      case .academic: return "学術"
      case .majorMedia: return "報道機関"
      case .techMedia: return "技術メディア"
      case .corporate: return "企業サイト"
      case .communityBlog: return "投稿型プラットフォーム"
      case .personalBlog: return "個人ブログ"
      case .aggregator: return "まとめ・アグリゲータ"
      case .unknown: return "分類なし"
      }
    }
  }
}

/// ドメイン評価を引くためのローカル辞書.
///
/// v1.0 ではオンデバイスの表と TLD 規則で判定する.
/// サーバ実装時は `DomainReputationProviding` を差し替えるだけで API 参照に切り替えられる.
enum DomainReputationTable {

  /// 個別に評価が分かっているドメイン.
  private static let known: [String: DomainReputation] = {
    var table: [String: DomainReputation] = [:]

    func register(_ domain: String, _ score: Int, _ category: DomainReputation.Category, policy: Bool, _ notes: String) {
      table[domain] = DomainReputation(
        domain: domain,
        baseScore: score,
        category: category,
        hasEditorialPolicy: policy,
        notes: notes
      )
    }

    // 公的機関・学術
    register("e-gov.go.jp", 96, .government, policy: true, "日本の法令データベース. 一次情報.")
    register("digital.go.jp", 94, .government, policy: true, "デジタル庁の公式発表.")
    register("mhlw.go.jp", 94, .government, policy: true, "厚生労働省の公式発表.")
    register("arxiv.org", 88, .academic, policy: true, "査読前のプレプリントを含む点に注意.")
    register("jstage.jst.go.jp", 92, .academic, policy: true, "査読付き学術論文のプラットフォーム.")

    // 報道・技術メディア
    register("nikkei.com", 84, .majorMedia, policy: true, "編集方針と訂正記事の運用が公開されている.")
    register("nhk.or.jp", 86, .majorMedia, policy: true, "公共放送. 速報は続報で内容が変わることがある.")
    register("itmedia.co.jp", 76, .techMedia, policy: true, "技術メディア. 発表内容の転載記事を含む.")
    register("publickey1.jp", 78, .techMedia, policy: true, "一次情報へのリンクが多い技術メディア.")

    // 投稿型プラットフォーム
    register("qiita.com", 62, .communityBlog, policy: false, "投稿者による品質差が大きい投稿型プラットフォーム.")
    register("zenn.dev", 64, .communityBlog, policy: false, "投稿型プラットフォーム. 一次情報の確認を推奨.")
    register("note.com", 58, .communityBlog, policy: false, "投稿型プラットフォーム. 編集の査読はない.")
    register("medium.com", 58, .communityBlog, policy: false, "投稿型プラットフォーム. 編集の査読はない.")
    register("github.com", 80, .corporate, policy: true, "ソースコードと公式ドキュメントの一次情報.")

    return table
  }()

  /// TLD・ドメイン特徴からカテゴリと基礎スコアを推定する規則.
  private static let suffixRules: [(suffix: String, score: Int, category: DomainReputation.Category, notes: String)] = [
    (".go.jp", 94, .government, "日本の政府機関ドメイン. 一次情報である可能性が高い."),
    (".gov", 92, .government, "政府機関ドメイン. 一次情報である可能性が高い."),
    (".ac.jp", 88, .academic, "日本の学術機関ドメイン."),
    (".edu", 86, .academic, "教育機関ドメイン."),
    (".or.jp", 74, .corporate, "日本の法人格を持つ団体のドメイン."),
    (".co.jp", 70, .corporate, "日本の企業ドメイン. 自社に有利な記述が含まれる場合がある."),
    (".lg.jp", 90, .government, "日本の地方自治体ドメイン.")
  ]

  /// 既定の基礎スコア. 情報が無いドメインに適用する.
  private static let defaultScore = 60

  /// ホスト名から評価を引く.
  static func reputation(for host: String) -> DomainReputation {
    let normalized = host.lowercased().hasPrefix("www.") ? String(host.lowercased().dropFirst(4)) : host.lowercased()

    if let exact = known[normalized] { return exact }

    // サブドメインを削りながら親ドメインを探す.
    var components = normalized.split(separator: ".").map(String.init)
    while components.count > 2 {
      components.removeFirst()
      let parent = components.joined(separator: ".")
      if let match = known[parent] {
        return DomainReputation(
          domain: normalized,
          baseScore: match.baseScore,
          category: match.category,
          hasEditorialPolicy: match.hasEditorialPolicy,
          notes: match.notes
        )
      }
    }

    for rule in suffixRules where normalized.hasSuffix(rule.suffix) {
      return DomainReputation(
        domain: normalized,
        baseScore: rule.score,
        category: rule.category,
        hasEditorialPolicy: rule.category == .government || rule.category == .academic,
        notes: rule.notes
      )
    }

    return DomainReputation(
      domain: normalized,
      baseScore: defaultScore,
      category: .unknown,
      hasEditorialPolicy: false,
      notes: "このドメインの評価情報は登録されていません. 記事単体の作法から判断しています."
    )
  }
}
