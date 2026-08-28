//
//  PaletteContrastTests.swift
//  TsumugiTests
//
//  仕様書 10.5:「コントラスト比 4.5:1 以上」を配色の回帰テストとして固定する.
//  伝統色は彩度が低く明度差が付きにくいため, 色を足すたびにここで検算する.
//

import Testing
import SwiftUI
import UIKit
@testable import Tsumugi

@MainActor
@Suite("配色のコントラスト（仕様書 10.5）")
struct PaletteContrastTests {

  /// WCAG の相対輝度.
  private func luminance(_ color: Color, style: UIUserInterfaceStyle) -> Double {
    let traits = UITraitCollection(userInterfaceStyle: style)
    let resolved = UIColor(color).resolvedColor(with: traits)

    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    func linear(_ value: CGFloat) -> Double {
      let channel = Double(value)
      return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// 2 色のコントラスト比.
  private func contrast(_ foreground: Color, on background: Color, style: UIUserInterfaceStyle) -> Double {
    let first = luminance(foreground, style: style)
    let second = luminance(background, style: style)
    let lighter = max(first, second)
    let darker = min(first, second)
    return (lighter + 0.05) / (darker + 0.05)
  }

  /// 検査対象の文字色を, 和名つきで列挙する.
  private var foregrounds: [(name: String, color: Color)] {
    var result: [(String, Color)] = [
      ("墨", Palette.ink),
      ("鈍色（補足文字）", Palette.inkMuted),
      ("藍", Palette.indigo),
      ("浅葱", Palette.asagi)
    ]
    for band in CredibilityBand.allCases {
      result.append((Palette.waColor(for: band).name, Palette.color(for: band)))
    }
    for label in StalenessLabel.allCases {
      result.append((Palette.waColor(for: label).name, Palette.color(for: label)))
    }
    return result
  }

  @Test("明所で 4.5:1 以上を満たす")
  func lightModeContrast() {
    for (name, color) in foregrounds {
      let value = contrast(color, on: Palette.paper, style: .light)
      #expect(value >= 4.5, "\(name) の明所コントラストが \(String(format: "%.2f", value)):1 しかありません")
    }
  }

  @Test("暗所で 4.5:1 以上を満たす")
  func darkModeContrast() {
    for (name, color) in foregrounds {
      let value = contrast(color, on: Palette.paper, style: .dark)
      #expect(value >= 4.5, "\(name) の暗所コントラストが \(String(format: "%.2f", value)):1 しかありません")
    }
  }

  @Test("地の色と面の色が見分けられる")
  func groundAndPaperAreDistinguishable() {
    // 罫だけに頼らずに面の輪郭が分かるよう, わずかな明度差を保つ.
    for style in [UIUserInterfaceStyle.light, .dark] {
      let value = contrast(Palette.ground, on: Palette.paper, style: style)
      #expect(value >= 1.06, "地と面の差が小さすぎます（\(String(format: "%.3f", value))）")
    }
  }

  @Test("帯の色には必ず和名が付いている")
  func everyBandHasATraditionalName() {
    for band in CredibilityBand.allCases {
      #expect(!Palette.waColor(for: band).name.isEmpty)
    }
    for label in StalenessLabel.allCases {
      #expect(!Palette.waColor(for: label).name.isEmpty)
    }
  }

  @Test("明朝体が端末で利用できる")
  func minchoFontIsAvailable() {
    // 見出しと数値に使う書体. 端末に無ければ体裁が崩れるので確認しておく.
    #expect(UIFont(name: "HiraMinProN-W6", size: 16) != nil)
    #expect(UIFont(name: "HiraMinProN-W3", size: 16) != nil)
  }
}
