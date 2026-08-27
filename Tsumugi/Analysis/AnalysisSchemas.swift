//
//  AnalysisSchemas.swift
//  Tsumugi
//
//  仕様書 9.3: 診断出力を強制する JSON Schema 群.
//  仕様書 9.1「すべての診断出力は JSON Schema による Structured Output で強制」に対応する.
//

import Foundation

enum AnalysisSchemas {

  /// 要約（仕様書 4.3）.
  static let summary: [String: Any] = [
    "type": "object",
    "required": ["tldr", "key_points", "detailed", "claims", "facts"],
    "additionalProperties": false,
    "properties": [
      "tldr": ["type": "string", "maxLength": 200],
      "key_points": [
        "type": "array",
        "minItems": 3,
        "maxItems": 7,
        "items": ["type": "string", "maxLength": 120]
      ],
      "detailed": ["type": "string", "maxLength": 1200],
      "claims": [
        "type": "array",
        "maxItems": 5,
        "items": [
          "type": "object",
          "required": ["claim", "evidence", "evidence_quality"],
          "additionalProperties": false,
          "properties": [
            "claim": ["type": "string", "maxLength": 200],
            "evidence": ["type": "string", "maxLength": 200],
            "evidence_quality": [
              "type": "string",
              "enum": ["primary_source", "official", "academic", "single_vendor", "secondary", "none"]
            ]
          ]
        ]
      ],
      "facts": [
        "type": "array",
        "maxItems": 12,
        "items": [
          "type": "object",
          "required": ["type", "value", "context"],
          "additionalProperties": false,
          "properties": [
            "type": [
              "type": "string",
              "enum": ["percentage", "amount", "count", "date", "version", "duration", "organization", "person", "place", "regulation", "other"]
            ],
            "value": ["type": "string", "maxLength": 80],
            "context": ["type": "string", "maxLength": 120]
          ]
        ]
      ]
    ]
  ]

  /// 信頼度診断（仕様書 9.3 のスキーマに, 外部照合とカテゴリ別根拠を加えたもの）.
  static let credibility: [String: Any] = [
    "type": "object",
    "required": ["scores", "rationale", "flags", "confidence"],
    "additionalProperties": false,
    "properties": [
      "scores": [
        "type": "object",
        "required": ["source", "transparency", "evidence", "neutrality"],
        "additionalProperties": false,
        "properties": [
          "source": scoreProperty,
          "transparency": scoreProperty,
          "evidence": scoreProperty,
          "neutrality": scoreProperty,
          // 外部照合は判定できない場合があるため必須にしない.
          "corroboration": scoreProperty
        ]
      ],
      "rationale": [
        "type": "array",
        "minItems": 4,
        "maxItems": 5,
        "items": [
          "type": "object",
          "required": ["category", "reason", "determined"],
          "additionalProperties": false,
          "properties": [
            "category": [
              "type": "string",
              "enum": ["source", "transparency", "evidence", "neutrality", "corroboration"]
            ],
            // 仕様書 9.3: 判断理由は 200 字以内.
            "reason": ["type": "string", "maxLength": 200],
            // 仕様書 10.6: 引用は 1 箇所 120 字以内に制限する.
            "quote": ["type": "string", "maxLength": 120],
            "determined": ["type": "boolean"]
          ]
        ]
      ],
      "flags": [
        "type": "array",
        "items": [
          "type": "string",
          "enum": [
            "no_author", "no_date", "sponsored", "affiliate_heavy",
            "no_citation", "contradicted", "sensational",
            "ai_generated_suspect", "satire", "medical_ymyl", "financial_ymyl"
          ]
        ]
      ],
      "confidence": ["type": "string", "enum": ["high", "medium", "low"]]
    ]
  ]

  /// 鮮度診断（仕様書 4.5.3）.
  static let freshness: [String: Any] = [
    "type": "object",
    "required": ["topic_class", "adjustments", "obsolete_points"],
    "additionalProperties": false,
    "properties": [
      "topic_class": [
        "type": "string",
        "enum": TopicClass.allCases.map(\.rawValue)
      ],
      "adjustments": [
        "type": "array",
        "maxItems": 5,
        "items": [
          "type": "object",
          "required": ["reason", "evidence"],
          "additionalProperties": false,
          "properties": [
            "reason": [
              "type": "string",
              "enum": ["update_history", "version_outdated", "year_outdated", "deprecated", "successor_exists"]
            ],
            "evidence": ["type": "string", "maxLength": 160]
          ]
        ]
      ],
      "obsolete_points": [
        "type": "array",
        "maxItems": 3,
        "items": [
          "type": "object",
          "required": ["quote", "reason"],
          "additionalProperties": false,
          "properties": [
            "quote": ["type": "string", "maxLength": 120],
            "reason": ["type": "string", "maxLength": 200]
          ]
        ]
      ]
    ]
  ]

  /// タグ提案（仕様書 LB-07）.
  static let tags: [String: Any] = [
    "type": "object",
    "required": ["tags"],
    "additionalProperties": false,
    "properties": [
      "tags": [
        "type": "array",
        "minItems": 1,
        "maxItems": 5,
        "items": ["type": "string", "maxLength": 20]
      ]
    ]
  ]

  private static let scoreProperty: [String: Any] = [
    "type": "integer", "minimum": 0, "maximum": 100
  ]
}
