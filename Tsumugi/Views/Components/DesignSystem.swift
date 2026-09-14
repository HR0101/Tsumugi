//
//  DesignSystem.swift
//  Tsumugi
//
//  診断結果の帯に当てる伝統色.
//  地の色・書体・面の作りは Shared/WaTheme.swift に置いてあり,
//  Share Extension とも共有している.
//

import SwiftUI

extension Palette {

  // MARK: 信頼度の帯（仕様書 4.4.2）

  /// 信頼度の帯に対応する伝統色.
  static func waColor(for band: CredibilityBand) -> WaColor {
    switch band {
    case .high: return WaColor("常磐色", light: 0x1E6B45, dark: 0x6FBE92)
    case .moderate: return WaColor("若竹色", light: 0x3F7A62, dark: 0x82C2A6)
    case .caution: return WaColor("山吹色", light: 0x8A6414, dark: 0xDFB454)
    case .doubtful: return WaColor("柿色", light: 0xA0552A, dark: 0xDD9060)
    case .low: return WaColor("蘇芳", light: 0x8E2F3A, dark: 0xD9757F)
    }
  }

  static func color(for band: CredibilityBand) -> Color {
    waColor(for: band).color
  }

  // MARK: 鮮度の帯（仕様書 4.5.3）

  /// 鮮度は「若草 → 刈安 → 朽葉 → 消炭」と, 草木が色を変えて朽ちるまでの順に並べている.
  /// 色そのものが時間経過を語るようにするため.
  static func waColor(for label: StalenessLabel) -> WaColor {
    switch label {
    case .current: return WaColor("若草色", light: 0x3D7136, dark: 0x8CC57E)
    case .aging: return WaColor("刈安色", light: 0x756421, dark: 0xD0BC63)
    case .stale: return WaColor("朽葉色", light: 0x8F5D30, dark: 0xD0A067)
    case .obsolete: return WaColor("消炭色", light: 0x574F4A, dark: 0xA79C93)
    case .timeless: return WaColor("瑠璃紺", light: 0x33478F, dark: 0x8B9AD8)
    case .unknown: return WaColor("鈍色", light: 0x6B665E, dark: 0xA8A296)
    }
  }

  static func color(for label: StalenessLabel) -> Color {
    waColor(for: label).color
  }
}
