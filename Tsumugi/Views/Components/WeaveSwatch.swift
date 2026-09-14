//
//  WeaveSwatch.swift
//  Tsumugi
//
//  この画面の「顔」になる部品.
//
//  紬は, 手で紡いだ糸を経（たて）と緯（よこ）に交差させて織る布.
//  それになぞらえて, 記事の 2 つの評価を 1 枚の布として描く.
//
//  ・経糸（たていと）＝ 信頼度. 布を縦に支える骨格.
//  ・緯糸（よこいと）＝ 鮮度. 時間の流れに沿って横に渡していく糸.
//
//  スコアが低いほど糸が抜け, 布は薄く透ける.
//  糸の太さのむら（節）は記事の URL ハッシュから決まるので,
//  同じ記事はいつも同じ布になり, 別の記事とは必ず違う布になる.
//

import SwiftUI

struct WeaveSwatch: View {

  /// 経糸の強さ（信頼度）. 未診断なら nil.
  let warpScore: Int?
  /// 緯糸の強さ（鮮度）. 未診断なら nil.
  let weftScore: Int?
  let warpColor: Color
  let weftColor: Color
  /// 模様を決める種. 記事ごとに固定の値を渡す.
  let seed: UInt64
  /// 糸の本数. 表示サイズに合わせて増減させる.
  var threadCount: Int = 18

  /// 未診断の糸に使う色.
  private var unwovenColor: Color { Palette.rule }

  var body: some View {
    Canvas { context, size in
      drawThreads(context: context, size: size, isWarp: true)
      drawThreads(context: context, size: size, isWarp: false)
    }
    .drawingGroup()
    .accessibilityHidden(true)
  }

  /// 経糸・緯糸を 1 方向分描く.
  private func drawThreads(context: GraphicsContext, size: CGSize, isWarp: Bool) {
    let score = isWarp ? warpScore : weftScore
    let color = score == nil ? unwovenColor : (isWarp ? warpColor : weftColor)
    // 経糸は下に敷き, 緯糸を少し透かして重ねると交差が沈んで布に見える.
    let baseOpacity = isWarp ? 0.95 : 0.72
    let density = Double(score ?? 0) / 100.0

    // 方向ごとに種をずらし, 経と緯で別の揺らぎにする.
    var generator = SeededGenerator(seed: seed &+ (isWarp ? 0 : 0x5DEECE66D))

    let span = isWarp ? size.width : size.height
    let length = isWarp ? size.height : size.width
    let pitch = span / Double(threadCount)

    for index in 0..<threadCount {
      let position = (Double(index) + 0.5) * pitch

      // スコアが低いほど糸が抜ける. 抜けた糸は下地としてかすかに残す.
      let isPresent = score != nil && generator.nextDouble() < density
      let threadOpacity = isPresent ? baseOpacity : (score == nil ? 0.5 : 0.12)

      // 1 本の糸を短い区間に分け, 区間ごとに太さを変えて「節」を作る.
      let segmentCount = 9
      let segmentLength = length / Double(segmentCount)

      for segment in 0..<segmentCount {
        let start = Double(segment) * segmentLength
        // 節: まれに太くなる. これが紬の手紡ぎらしさになる.
        let isSlub = generator.nextDouble() < 0.14
        let thickness = pitch * (isSlub ? generator.next(in: 0.55...0.78) : generator.next(in: 0.24...0.42))
        let jitter = (generator.nextDouble() - 0.5) * pitch * 0.18

        let rect = isWarp
          ? CGRect(x: position + jitter - thickness / 2, y: start, width: thickness, height: segmentLength)
          : CGRect(x: start, y: position + jitter - thickness / 2, width: segmentLength, height: thickness)

        context.fill(
          Path(rect),
          with: .color(color.opacity(threadOpacity * generator.next(in: 0.78...1.0)))
        )
      }
    }
  }
}

/// 記事詳細の頭に置く布. 2 つのスコアを 1 枚の布として見せる.
struct ItemWeaveBand: View {
  let item: Item
  var height: CGFloat = 64

  private var seed: UInt64 {
    // URL ハッシュ（16 進 64 文字）の先頭 16 桁を種にする.
    UInt64(item.urlHash.prefix(16), radix: 16) ?? 0x5851F42D4C957F2D
  }

  var body: some View {
    VStack(spacing: Spacing.sm) {
      WeaveSwatch(
        warpScore: item.credibilityScore,
        weftScore: item.freshnessScore,
        warpColor: item.credibility.map { Palette.color(for: $0.band) } ?? Palette.rule,
        weftColor: item.freshness.map { Palette.color(for: $0.stalenessLabel) } ?? Palette.rule,
        seed: seed,
        threadCount: 26
      )
      .frame(height: height)
      .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
          .strokeBorder(Palette.rule, lineWidth: Radius.hairline)
      }

      HStack(spacing: Spacing.md) {
        threadLegend(mark: "経", title: "信頼度", color: item.credibility.map { Palette.color(for: $0.band) })
        threadLegend(mark: "緯", title: "鮮度", color: item.freshness.map { Palette.color(for: $0.stalenessLabel) })
        Spacer(minLength: 0)
        Text("この記事だけの織り")
          .font(.caption2)
          .foregroundStyle(Palette.inkMuted)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(weaveDescription)
  }

  private func threadLegend(mark: String, title: String, color: Color?) -> some View {
    HStack(spacing: Spacing.xs) {
      Text(mark)
        .font(WaFont.subheading)
        .foregroundStyle(color ?? Palette.inkMuted)
      Text(title)
        .font(.caption2)
        .foregroundStyle(Palette.inkMuted)
    }
  }

  private var weaveDescription: String {
    let credibility = item.credibilityScore.map { "信頼度 \($0) 点" } ?? "信頼度は未診断"
    let freshness = item.freshnessScore.map { "鮮度 \($0) 点" } ?? "鮮度は未診断"
    return "この記事の織り. 経糸は\(credibility), 緯糸は\(freshness)."
  }
}
