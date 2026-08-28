//
//  WaTheme.swift
//  Tsumugi / ShareExtension 共通
//
//  ── デザインの考え方 ────────────────────────────────────────
//  アプリ名の「紬（つむぎ）」は, 真綿から手で紡いだ糸を草木で染め, 手で織った布のこと.
//  散らばった記事を手元でより合わせ, 1 枚の布に織り上げていく——という見立てを,
//  そのまま画面の造りに落としている.
//
//  ・配色は草木染めの伝統色に限定する（藍・蘇芳・山吹・刈安・朽葉…）.
//    化学染料のような彩度の高い色は使わない.
//  ・面は「浮くカード」ではなく「和紙の面」として扱う. 影を落とさず, 罫（けい）で仕切る.
//  ・見出しは明朝体. 本文と操作系は角ゴシックのままにして可読性を優先する.
//  ・信頼度を経糸（たていと）, 鮮度を緯糸（よこいと）に見立てる（WeaveSwatch を参照）.
//
//  仕様書 10.5 に従い, 色は必ずアイコン形状とテキストラベルを伴って使い,
//  文字色は明所・暗所のどちらでもコントラスト比 4.5:1 以上を確保する.
//

import SwiftUI

// MARK: - 伝統色

/// 明所・暗所で切り替わる 1 色を, 和名とともに定義する.
struct WaColor {
  /// 色の和名. 診断画面などで出典として示す.
  let name: String
  private let light: Color
  private let dark: Color

  init(_ name: String, light: UInt32, dark: UInt32) {
    self.name = name
    self.light = Color(hex: light)
    self.dark = Color(hex: dark)
  }

  /// 表示中の外観に合わせた色.
  var color: Color {
    Color(uiColor: UIColor { traits in
      UIColor(traits.userInterfaceStyle == .dark ? dark : light)
    })
  }
}

private extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1
    )
  }
}

enum Palette {

  // MARK: 地の色

  /// 生成り（きなり）／墨紺（すみこん）: 画面全体の地.
  static let ground = WaColor("生成り", light: 0xE4DCC8, dark: 0x11151C).color
  /// 白練（しろねり）／褐返（かちがえし）: 一段持ち上がった面.
  static let paper = WaColor("白練", light: 0xF8F4EB, dark: 0x1C232F).color
  /// 罫（けい）. 面を仕切る細い線.
  static let rule = WaColor("罫", light: 0xC0B69F, dark: 0x333D4A).color

  // MARK: 墨と藍

  /// 墨（すみ）: 本文の色.
  static let ink = WaColor("墨", light: 0x23262B, dark: 0xE8E3D6).color
  /// 鈍色（にびいろ）: 補足の文字.
  static let inkMuted = WaColor("鈍色", light: 0x605C51, dark: 0x9A9486).color
  /// 藍（あい）: 紬を代表する染め色. 操作と強調に使う.
  static let indigo = WaColor("藍", light: 0x234E78, dark: 0x7FA9CE).color
  /// 浅葱（あさぎ）: 藍を薄めた色. 補助的な強調に使う.
  static let asagi = WaColor("浅葱", light: 0x376C74, dark: 0x86BFC4).color

}

// MARK: - 書体

/// 見出しは明朝体, 本文と操作系は角ゴシック.
/// 明朝は縦画と横画の太さの差が大きく, 小さな文字では読みにくくなるため,
/// 表題・見出し・数値だけに使う.
enum WaFont {

  /// ヒラギノ明朝 ProN. iOS に同梱されている.
  private static let minchoBold = "HiraMinProN-W6"
  private static let minchoRegular = "HiraMinProN-W3"

  /// 明朝体を Dynamic Type に追従させて返す.
  private static func mincho(_ size: CGFloat, relativeTo style: Font.TextStyle, bold: Bool = true) -> Font {
    .custom(bold ? minchoBold : minchoRegular, size: size, relativeTo: style)
  }

  /// 画面の表題（ライブラリ, 記事タイトルなど）.
  static let display = mincho(26, relativeTo: .title)
  /// 記事タイトル.
  static let title = mincho(21, relativeTo: .title3)
  /// 節の見出し.
  static let heading = mincho(16, relativeTo: .headline)
  /// 小さな見出し.
  static let subheading = mincho(14, relativeTo: .subheadline)
  /// スコアの数値（大）.
  static let numeralLarge = mincho(46, relativeTo: .largeTitle)
  /// スコアの数値（中）.
  static let numeralMedium = mincho(34, relativeTo: .title)
  /// 引用文.
  static let quote = mincho(16, relativeTo: .callout, bold: false)
}

// MARK: - 寸法

enum Spacing {
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 16
  static let xl: CGFloat = 24
  static let xxl: CGFloat = 32
}

enum Radius {
  /// 和の造形は直線が基本. 角はほとんど落とさない.
  static let panel: CGFloat = 3
  static let chip: CGFloat = 2
  /// 罫の太さ.
  static let hairline: CGFloat = 0.75
}

// MARK: - 面と罫

extension View {
  /// 和紙の面. 影を落とさず, 罫で輪郭を示す.
  func paperPanel(padding: CGFloat = Spacing.lg) -> some View {
    self
      .padding(padding)
      .background {
        ZStack {
          Rectangle().fill(Palette.paper)
          WashiGrain()
        }
      }
      .overlay {
        Rectangle()
          .strokeBorder(Palette.rule, lineWidth: Radius.hairline)
      }
      .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
  }

  /// 節の見出し. 左に短い藍の罫を立てる（掛軸の軸のような目印）.
  func sectionTitleStyle() -> some View {
    HStack(spacing: Spacing.sm) {
      Rectangle()
        .fill(Palette.indigo)
        .frame(width: 2, height: 13)
      self
        .font(WaFont.subheading)
        .foregroundStyle(Palette.ink)
        .textCase(nil)
      Spacer(minLength: 0)
    }
  }
}

/// 画面全体の地. 和紙の繊維の質感をうっすら重ねる.
struct WashiBackground: View {
  var body: some View {
    ZStack {
      Palette.ground
      WashiGrain(fiberCount: 260, opacity: 0.05)
    }
    .ignoresSafeArea()
  }
}

/// 和紙の繊維. 決まった種から擬似乱数で描くので, 再描画しても模様が動かない.
struct WashiGrain: View {
  var fiberCount: Int = 90
  var opacity: Double = 0.045

  var body: some View {
    Canvas { context, size in
      var generator = SeededGenerator(seed: 20260828)
      context.opacity = opacity

      for _ in 0..<fiberCount {
        let x = generator.nextDouble() * size.width
        let y = generator.nextDouble() * size.height
        // 繊維はおおむね横に寝ているので, 横長の線分にする.
        let length = 6 + generator.nextDouble() * 26
        let slant = (generator.nextDouble() - 0.5) * 0.5

        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + length, y: y + length * slant))
        context.stroke(path, with: .color(Palette.ink), lineWidth: 0.6)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// 種を固定できる擬似乱数生成器（線形合同法）.
/// 同じ記事にはいつも同じ模様を出すために使う.
struct SeededGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
  }

  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return state
  }

  /// 0.0 以上 1.0 未満の値を返す.
  mutating func nextDouble() -> Double {
    Double(next() >> 11) / Double(1 << 53)
  }

  /// 指定した範囲の値を返す.
  mutating func next(in range: ClosedRange<Double>) -> Double {
    range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
  }
}

// MARK: - ボタン

/// 主要な操作のボタン. 藍で染めた札に見立てる.
struct WaButtonStyle: ButtonStyle {
  var isProminent: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(WaFont.subheading)
      .foregroundStyle(isProminent ? Palette.paper : Palette.indigo)
      .padding(.horizontal, Spacing.xl)
      .padding(.vertical, Spacing.md)
      .background(isProminent ? Palette.indigo : Color.clear)
      .overlay {
        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
          .strokeBorder(Palette.indigo, lineWidth: Radius.hairline)
      }
      .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

// MARK: - 日付の表記

enum DateStyle {
  static let short: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yyyy.MM.dd"
    return formatter
  }()

  static let long: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "yyyy年M月d日"
    return formatter
  }()

  static func relative(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: .now)
  }
}
