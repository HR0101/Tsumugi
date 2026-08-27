//
//  ClaudeAPIClient.swift
//  Tsumugi
//
//  Anthropic Messages API（`POST /v1/messages`）への薄いクライアント.
//
//  Swift 用の公式 SDK は提供されていないため, URLSession による raw HTTP で実装する.
//  仕様書 9.1 の「すべての診断出力は JSON Schema による Structured Output で強制」を
//  `output_config.format` で満たす.
//
//  ⚠️ セキュリティ上の注意:
//  本実装は API キーを端末の Keychain に保管して直接 Anthropic API を呼び出す.
//  この構成では, 端末を解析されるとキーが漏洩する可能性がある.
//  仕様書 6.1 / 10.3 の本来の構成（API Gateway 経由でサーバがキーを保持する）へ
//  移行するまでは, 個人利用・検証用途に限定して使用すること.
//

import Foundation

/// 用途ごとのモデル階層. 仕様書 9.1「モデル選定方針」に対応する.
enum ModelTier: String, Codable, CaseIterable, Sendable {
  /// トピック分類・タグ提案など. コスト最小化を優先する.
  case small
  /// 要約. コストと品質の均衡.
  case medium
  /// 信頼度診断. 多段の判断が必要なため推論を強化する.
  case large

  /// 既定のモデル ID.
  var defaultModelID: String {
    switch self {
    case .small: return "claude-haiku-4-5"
    case .medium: return "claude-sonnet-5"
    case .large: return "claude-opus-5"
    }
  }

  var displayName: String {
    switch self {
    case .small: return "分類・タグ提案"
    case .medium: return "要約"
    case .large: return "信頼度・鮮度診断"
    }
  }

  /// 適応的思考（adaptive thinking）に対応する階層か.
  /// Haiku 4.5 は旧世代のため, このパラメータを送らない.
  var supportsAdaptiveThinking: Bool {
    self != .small
  }

  /// `output_config.effort` に対応する階層か.
  var supportsEffort: Bool {
    self != .small
  }
}

/// API クライアントの設定.
struct ClaudeConfiguration: Sendable {
  var apiKey: String
  var models: [ModelTier: String]
  /// リクエストのタイムアウト（秒）. 仕様書 6.2 のタイムアウト 60 秒に合わせる.
  var timeout: TimeInterval = 60

  func modelID(for tier: ModelTier) -> String {
    models[tier] ?? tier.defaultModelID
  }
}

/// Anthropic Messages API クライアント.
struct ClaudeAPIClient: Sendable {

  private enum Constant {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"
    /// 非ストリーミング要求の既定の出力上限.
    static let maxTokens = 16_000
    /// Claude Opus 5 でポリシー上の拒否が起きた際に別モデルへ自動フォールバックするベータ機能.
    static let fallbackBeta = "server-side-fallback-2026-07-01"
  }

  private let configuration: ClaudeConfiguration
  private let urlSession: URLSession

  init(configuration: ClaudeConfiguration, urlSession: URLSession = .shared) {
    self.configuration = configuration
    self.urlSession = urlSession
  }

  /// JSON Schema で出力形式を強制したうえでメッセージを送り, 生成された JSON を返す.
  ///
  /// - Parameters:
  ///   - tier: 使用するモデル階層.
  ///   - system: システムプロンプト.
  ///   - userPrompt: ユーザーメッセージ.
  ///   - schema: 出力を強制する JSON Schema.
  ///   - effort: 推論の深さ（`low` / `medium` / `high` / `xhigh` / `max`）.
  /// - Returns: スキーマに適合した JSON の `Data`.
  func requestStructuredJSON(
    tier: ModelTier,
    system: String,
    userPrompt: String,
    schema: [String: Any],
    effort: String = "medium"
  ) async throws -> Data {
    var body: [String: Any] = [
      "model": configuration.modelID(for: tier),
      "max_tokens": Constant.maxTokens,
      "system": system,
      "messages": [["role": "user", "content": userPrompt]],
      "output_config": [
        "format": [
          "type": "json_schema",
          "schema": schema
        ]
      ]
    ]

    // 注意: 現行モデル（Opus 5 / Sonnet 5 など）は temperature / top_p / seed を受け付けず,
    // 指定すると 400 になる. 仕様書 9.1 が求める再現性は
    // Structured Output によるスキーマ強制と, 決定的なスコア合成（9.4 / 9.5）で担保する.
    if tier.supportsAdaptiveThinking {
      body["thinking"] = ["type": "adaptive"]
    }
    if tier.supportsEffort {
      var outputConfig = body["output_config"] as? [String: Any] ?? [:]
      outputConfig["effort"] = effort
      body["output_config"] = outputConfig
    }

    var betas: [String] = []
    if configuration.modelID(for: tier).hasPrefix("claude-opus-5") {
      // ポリシー上の拒否が返った場合に, 同一リクエスト内で別モデルへ退避させる.
      body["fallbacks"] = "default"
      betas.append(Constant.fallbackBeta)
    }

    var request = URLRequest(url: Constant.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = configuration.timeout
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue(Constant.apiVersion, forHTTPHeaderField: "anthropic-version")
    if !betas.isEmpty {
      request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw AnalysisError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw AnalysisError.providerFailure(message: errorMessage(from: data, statusCode: httpResponse.statusCode))
    }

    return try extractJSONPayload(from: data)
  }

  // MARK: - レスポンスの解釈

  /// `content` 配列から最初のテキストブロックを取り出し, JSON として返す.
  private func extractJSONPayload(from data: Data) throws -> Data {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw AnalysisError.invalidResponse
    }

    // 安全性の判断でモデルが応答を拒否した場合（HTTP 200 で返る）.
    if let stopReason = root["stop_reason"] as? String, stopReason == "refusal" {
      let explanation = (root["stop_details"] as? [String: Any])?["explanation"] as? String
      throw AnalysisError.providerFailure(
        message: explanation ?? "モデルがこの記事の診断を辞退しました."
      )
    }

    guard let content = root["content"] as? [[String: Any]] else {
      throw AnalysisError.invalidResponse
    }

    for block in content where block["type"] as? String == "text" {
      guard let text = block["text"] as? String else { continue }
      // output_config.format により, このテキストは有効な JSON であることが保証されている.
      guard let payload = text.data(using: .utf8) else { continue }
      return payload
    }

    throw AnalysisError.invalidResponse
  }

  private func errorMessage(from data: Data, statusCode: Int) -> String {
    if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let error = root["error"] as? [String: Any],
       let message = error["message"] as? String {
      return "\(message)（HTTP \(statusCode)）"
    }
    switch statusCode {
    case 401: return "API キーが無効です（HTTP 401）."
    case 429: return "レート制限に達しました. しばらく待って再試行してください（HTTP 429）."
    case 500...599: return "プロバイダ側で一時的な障害が発生しています（HTTP \(statusCode)）."
    default: return "リクエストが拒否されました（HTTP \(statusCode)）."
    }
  }
}
