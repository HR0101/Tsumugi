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
//  ・地と面は和紙と墨の無彩色に近い色にとどめ, 青や茶に寄せない.
//    染め色は織りの帯（WeaveSwatch）と診断の帯にだけ使い, 藍は操作と選択中だけに使う.
//  ・面は重ねた和紙として扱う. グラデーションや縁の光は使わず, 面の明度差と細い罫で奥行きを示す.
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

  /// 生成り（きなり）／墨（すみ）: 画面全体の地.
  static let ground = WaColor("生成り", light: 0xF4F1EA, dark: 0x161513).color
  /// 白練（しろねり）／墨の紙: 一段持ち上がった面.
  static let paper = WaColor("白練", light: 0xFDFBF7, dark: 0x201E1B).color
  /// 罫（けい）. 面を仕切る細い線. 面の上に墨を 10% 重ねた色を不透明で持つ.
  static let rule = WaColor("罫", light: 0xE7E5E0, dark: 0x35322E).color

  /// 紙の下に落ちる影. 色を付けず, 明所でだけ小さく使う（暗所は面の明度差で奥行きを示す）.
  static let shadow = WaColor("紙の影", light: 0x000000, dark: 0x000000).color

  // MARK: 墨と藍

  /// 墨（すみ）: 本文の色.
  static let ink = WaColor("墨", light: 0x1F1B16, dark: 0xEFE9DE).color
  /// 鈍色（にびいろ）: 補足の文字.
  static let inkMuted = WaColor("鈍色", light: 0x5E554A, dark: 0xAAA398).color
  /// 藍（あい）: 紬を代表する染め色. 主操作・選択中・リンクだけに使う.
  static let indigo = WaColor("藍", light: 0x254966, dark: 0x8FA8C4).color
  /// 浅葱（あさぎ）: 藍を薄めた色. 補助的な強調に使う.
  static let asagi = WaColor("浅葱", light: 0x376C74, dark: 0x86BFC4).color
  /// 蘇芳（すおう）: 破棄・削除など注意を要する操作に使う伝統色.
  static let suou = WaColor("蘇芳", light: 0x8E2F3A, dark: 0xD9757F).color
  /// 山吹（やまぶき）: お気に入りや祝いのアクセントに使う伝統色.
  static let yamabuki = WaColor("山吹", light: 0x8A6414, dark: 0xDFB454).color
  /// セグメントのトラックなど, 地より一段沈んだ面.
  static let trackTint = WaColor("薄墨地", light: 0xEFE9DF, dark: 0x2A2724).color

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
  /// 一覧の記事見出し。本文との差を保ちつつ、3行でも重く見えない大きさ。
  static let cardTitle = mincho(18, relativeTo: .headline)
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
  /// 紙の端を柔らかく丸め, 面の重なりを見せる.
  static let panel: CGFloat = 14
  static let chip: CGFloat = 7
  /// 罫の太さ.
  static let hairline: CGFloat = 0.75
}

// MARK: - 面と罫

extension View {
  /// 和紙の面. 平らな面に細い罫を 1 本回し, 明所でだけ小さな影を落とす.
  func paperPanel(padding: CGFloat = Spacing.lg) -> some View {
    self
      .padding(padding)
      .background { PaperSurface() }
  }

  /// 節の見出し. 左に短い墨の罫を立てる（掛軸の軸のような目印）.
  func sectionTitleStyle() -> some View {
    HStack(spacing: Spacing.sm) {
      Rectangle()
        .fill(Palette.inkMuted)
        .frame(width: 2, height: 13)
      self
        .font(WaFont.subheading)
        .foregroundStyle(Palette.ink)
        .textCase(nil)
      Spacer(minLength: 0)
    }
  }
}

/// 内容をクリップせず, 背景の面だけに陰影を付ける.
struct PaperSurface: View {
  var cornerRadius: CGFloat = Radius.panel
  var isRaised: Bool = true

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let shadow = PaperShadow.resolve(isRaised: isRaised, colorScheme: colorScheme)
    shape
      .fill(Palette.paper)
      .overlay { WashiGrain(fiberCount: 34, opacity: 0.012).clipShape(shape) }
      .overlay { shape.strokeBorder(Palette.rule, lineWidth: Radius.hairline) }
      .shadow(color: Palette.shadow.opacity(shadow.opacity), radius: shadow.radius, x: 0, y: shadow.y)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

/// 面の影の大きさ. 色を付けず, 暗所では使わない.
enum PaperShadow {
  struct Value {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat
  }

  /// 影なし（暗所用）.
  static let none = Value(opacity: 0, radius: 0, y: 0)
  /// 地に置いた面.
  static let resting = Value(opacity: 0.05, radius: 1, y: 1)
  /// 一段浮かせた面.
  static let raised = Value(opacity: 0.06, radius: 12, y: 8)

  static func resolve(isRaised: Bool, colorScheme: ColorScheme) -> Value {
    guard colorScheme == .light else { return none }
    return isRaised ? raised : resting
  }
}

/// 画面全体の地. 和紙の繊維の質感をうっすら重ねる.
struct WashiBackground: View {
  var body: some View {
    ZStack {
      Palette.ground
      WashiGrain(fiberCount: 105, opacity: 0.012)
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
        let length = 3 + generator.nextDouble() * 12
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

/// 主要な操作のボタン. 藍で染めた札に見立て, 押し込み時に体積保存の弾力を与える.
struct WaButtonStyle: ButtonStyle {
  var isProminent: Bool = true

  func makeBody(configuration: Configuration) -> some View {
    BodyView(configuration: configuration, isProminent: isProminent)
  }

  private struct BodyView: View {
    let configuration: Configuration
    let isProminent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
      let pressed = configuration.isPressed
      // 押している間は影を消し, 面が地に沈んだように見せる.
      let shadow = pressed ? PaperShadow.none : PaperShadow.resolve(isRaised: false, colorScheme: colorScheme)
      configuration.label
        .font(WaFont.subheading)
        .foregroundStyle(isProminent ? Palette.paper : Palette.indigo)
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background {
          if isProminent {
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
              .fill(Palette.indigo)
          } else {
            PaperSurface(cornerRadius: Radius.chip, isRaised: false)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .shadow(color: Palette.shadow.opacity(shadow.opacity), radius: shadow.radius, x: 0, y: shadow.y)
        .scaleEffect(
          x: pressed && !reduceMotion ? 1.07 : 1.0,
          y: pressed && !reduceMotion ? 0.90 : 1.0,
          anchor: .center
        )
        .brightness(pressed ? -0.03 : 0)
        .animation(
          reduceMotion ? ElasticMotion.microFade : (pressed ? ElasticMotion.squishPress : ElasticMotion.squishRelease),
          value: pressed
        )
    }
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
