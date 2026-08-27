//
//  CredibilityFlag.swift
//  Tsumugi
//
//  仕様書 4.4.3: 信頼度診断の警告フラグ.
//

import Foundation

/// 信頼度診断で立てられる警告フラグ.
///
/// 仕様書 4.4.4 の設計原則に従い, 文言はすべて「記述的表現」に限定し
/// 「フェイクニュースである」等の断定表現は用いない.
enum CredibilityFlag: String, Codable, CaseIterable, Sendable, Identifiable {
  case noAuthor = "no_author"
  case noDate = "no_date"
  case sponsored = "sponsored"
  case affiliateHeavy = "affiliate_heavy"
  case noCitation = "no_citation"
  case contradicted = "contradicted"
  case sensational = "sensational"
  case aiGeneratedSuspect = "ai_generated_suspect"
  case satire = "satire"
  case medicalYMYL = "medical_ymyl"
  case financialYMYL = "financial_ymyl"

  var id: String { rawValue }

  /// 画面に表示する短いラベル.
  var displayName: String {
    switch self {
    case .noAuthor: return "著者不明"
    case .noDate: return "発行日不明"
    case .sponsored: return "広告・PR 記事"
    case .affiliateHeavy: return "アフィリエイトリンク多数"
    case .noCitation: return "出典の提示がない"
    case .contradicted: return "他ソースと矛盾する記述"
    case .sensational: return "扇動的・断定的表現"
    case .aiGeneratedSuspect: return "AI 自動生成の疑い"
    case .satire: return "風刺・パロディの可能性"
    case .medicalYMYL: return "医療・健康分野"
    case .financialYMYL: return "金融・投資分野"
    }
  }

  /// フラグの意味を補足する説明文.
  var detail: String {
    switch self {
    case .noAuthor: return "記事の書き手が明記されていないため, 責任の所在を確認できません."
    case .noDate: return "発行日を特定できないため, 情報の新しさを評価できません."
    case .sponsored: return "広告・PR である旨の表記が確認されました. 内容が宣伝目的である可能性があります."
    case .affiliateHeavy: return "アフィリエイトリンクが多く含まれます. 商品評価に利害が絡む可能性があります."
    case .noCitation: return "主張を裏付ける出典リンクがほとんど提示されていません."
    case .contradicted: return "他のソースと食い違う記述が見つかりました. 複数の情報源での確認をおすすめします."
    case .sensational: return "断定的・感情に訴える表現が多く見られます."
    case .aiGeneratedSuspect: return "定型的な文体が多く, 自動生成された文章である可能性があります."
    case .satire: return "風刺・パロディを掲載するサイトの可能性があります."
    case .medicalYMYL: return "医療・健康に関する内容です. 判断の前に医療専門家にご相談ください."
    case .financialYMYL: return "金融・投資に関する内容です. 判断の前に専門家にご相談ください."
    }
  }

  /// SF Symbols 名. 仕様書 10.5 に従い色だけに依存しない表現とするため必ず併記する.
  var symbolName: String {
    switch self {
    case .noAuthor: return "person.crop.circle.badge.questionmark"
    case .noDate: return "calendar.badge.exclamationmark"
    case .sponsored: return "megaphone"
    case .affiliateHeavy: return "cart.badge.questionmark"
    case .noCitation: return "link.badge.plus"
    case .contradicted: return "arrow.triangle.branch"
    case .sensational: return "flame"
    case .aiGeneratedSuspect: return "cpu"
    case .satire: return "theatermasks"
    case .medicalYMYL: return "cross.case"
    case .financialYMYL: return "yensign.circle"
    }
  }

  /// YMYL（Your Money or Your Life）分野かどうか.
  /// 仕様書 10.6 に従い, 該当時は専門家相談を促す固定文言を表示する.
  var isYMYL: Bool {
    self == .medicalYMYL || self == .financialYMYL
  }

  /// 仕様書 9.4 の `FLAG_PENALTIES`. 総合スコアから減点する点数.
  var penalty: Double {
    switch self {
    case .sponsored: return 8
    case .affiliateHeavy: return 10
    case .noCitation: return 6
    case .contradicted: return 18
    case .sensational: return 8
    case .aiGeneratedSuspect: return 10
    case .satire: return 25
    case .noAuthor, .noDate, .medicalYMYL, .financialYMYL: return 0
    }
  }
}
