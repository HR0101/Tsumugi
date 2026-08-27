//
//  URLNormalizer.swift
//  Tsumugi
//
//  仕様書 16.2: URL 正規化ルール.
//

import Foundation
import CryptoKit

/// 保存 URL を正規化し, 重複判定用のハッシュを生成する.
enum URLNormalizer {

  /// 除去するトラッキングパラメータ. 完全一致で判定するもの.
  private static let trackingParameters: Set<String> = [
    "fbclid", "gclid", "yclid", "ref", "ref_src", "spm",
    "at_medium", "at_campaign", "mc_cid", "mc_eid", "igshid", "cmpid"
  ]

  /// 除去するトラッキングパラメータの接頭辞.
  private static let trackingPrefixes = ["utm_"]

  /// SPA のハッシュルーティングとみなす接頭辞. これらはフラグメントを保持する.
  private static let spaFragmentPrefixes = ["/", "!"]

  /// 正規化結果.
  struct Result: Equatable, Sendable {
    /// 正規化後の URL 文字列.
    var canonicalURL: String
    /// 正規化 URL の SHA-256（16 進小文字）.
    var urlHash: String
  }

  /// URL を仕様書 16.2 の手順で正規化する.
  ///
  /// - Parameters:
  ///   - rawURL: ユーザーが共有した URL.
  ///   - canonicalHint: HTML の `<link rel="canonical">` から得た URL（手順 6）.
  /// - Returns: 正規化 URL とそのハッシュ. URL として解釈できない場合は `nil`.
  static func normalize(_ rawURL: String, canonicalHint: String? = nil) -> Result? {
    // 手順 6: canonical が存在すればそちらを優先する.
    let target = resolveCanonicalHint(canonicalHint, relativeTo: rawURL) ?? rawURL

    let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: trimmed), let host = components.host, !host.isEmpty else {
      return nil
    }

    // 手順 1: スキームを https に統一する.
    components.scheme = "https"

    // 手順 2: ホスト名を小文字化し, 先頭の www. を除去する.
    var normalizedHost = host.lowercased()
    if normalizedHost.hasPrefix("www.") {
      normalizedHost = String(normalizedHost.dropFirst(4))
    }
    components.host = normalizedHost
    // 既定ポートは冗長なので落とす.
    if components.port == 80 || components.port == 443 { components.port = nil }

    // 手順 3: トラッキングパラメータを除去する.
    if let queryItems = components.queryItems {
      let kept = queryItems.filter { !isTrackingParameter($0.name) }
      components.queryItems = kept.isEmpty ? nil : kept
    }

    // 手順 7: AMP URL を正規版へ変換する.
    applyAMPNormalization(to: &components)

    // 手順 4: フラグメントを除去する（SPA のハッシュルーティングは保持）.
    if let fragment = components.fragment, !isSPAFragment(fragment) {
      components.fragment = nil
    }

    // 手順 5: 末尾スラッシュを除去する.
    if components.path.count > 1, components.path.hasSuffix("/") {
      components.path = String(components.path.dropLast())
    }

    guard let url = components.url else { return nil }
    let canonical = url.absoluteString
    return Result(canonicalURL: canonical, urlHash: sha256(canonical))
  }

  /// 文字列の SHA-256 を 16 進小文字で返す（手順 8）.
  static func sha256(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - 内部処理

  private static func isTrackingParameter(_ name: String) -> Bool {
    let lowered = name.lowercased()
    if trackingParameters.contains(lowered) { return true }
    return trackingPrefixes.contains { lowered.hasPrefix($0) }
  }

  private static func isSPAFragment(_ fragment: String) -> Bool {
    guard let first = fragment.first else { return false }
    return spaFragmentPrefixes.contains(String(first))
  }

  /// `/amp/` `/amp` `?amp=1` を取り除いて正規版 URL に近づける.
  private static func applyAMPNormalization(to components: inout URLComponents) {
    if let queryItems = components.queryItems {
      let kept = queryItems.filter { $0.name.lowercased() != "amp" && $0.name.lowercased() != "outputtype" }
      components.queryItems = kept.isEmpty ? nil : kept
    }

    var path = components.path
    if path.hasSuffix("/amp") {
      path = String(path.dropLast(4))
    } else if path.hasSuffix("/amp/") {
      path = String(path.dropLast(5))
    }
    path = path.replacingOccurrences(of: "/amp/", with: "/")
    components.path = path.isEmpty ? "/" : path
  }

  /// canonical ヒントが相対パスの場合に元 URL を基準に解決する.
  private static func resolveCanonicalHint(_ hint: String?, relativeTo base: String) -> String? {
    guard let hint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    if hint.hasPrefix("http://") || hint.hasPrefix("https://") { return hint }
    guard let baseURL = URL(string: base) else { return nil }
    return URL(string: hint, relativeTo: baseURL)?.absoluteString
  }
}
