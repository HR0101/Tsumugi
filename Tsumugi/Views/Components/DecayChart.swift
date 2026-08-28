//
//  DecayChart.swift
//  Tsumugi
//
//  仕様書 S-05: 鮮度診断詳細画面の半減期グラフ.
//  F_time = 100 × 0.5^(Δt / H) の曲線と, 現在位置を重ねて描く.
//
//  曲線の下は, 墨が和紙にしみて薄れていくように,
//  上から下へ色が抜けるグラデーションで塗る.
//

import SwiftUI

struct DecayChart: View {

  /// 適用された半減期（日）.
  let halfLifeDays: Int
  /// 基準日からの経過日数.
  let elapsedDays: Int
  /// 補正を含む最終スコア.
  let finalScore: Int
  let tint: Color

  /// 横軸の最大値. 半減期 3 回分か, 経過日数の 1.2 倍のうち大きい方.
  private var maxDays: Double {
    max(Double(halfLifeDays) * 3, Double(elapsedDays) * 1.2, 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Canvas { context, size in
        let plot = CGRect(
          x: 26,
          y: 8,
          width: max(size.width - 34, 1),
          height: max(size.height - 26, 1)
        )
        drawAxes(context: context, plot: plot)
        drawCurve(context: context, plot: plot)
        drawHalfLifeMarker(context: context, plot: plot)
        drawCurrentPosition(context: context, plot: plot)
      }
      .frame(height: 150)

      HStack(spacing: Spacing.md) {
        legend(color: tint, text: "時間減衰カーブ")
        legend(color: Palette.rule, text: "半減期 \(halfLifeDays) 日")
      }
      .font(.caption2)
      .foregroundStyle(Palette.inkMuted)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "半減期グラフ. 半減期は \(halfLifeDays) 日, 経過は \(elapsedDays) 日, 現在の鮮度は \(finalScore) 点です."
    )
  }

  // MARK: - 描画

  private func x(for days: Double, in plot: CGRect) -> CGFloat {
    plot.minX + plot.width * CGFloat(min(days / maxDays, 1))
  }

  private func y(for score: Double, in plot: CGRect) -> CGFloat {
    plot.maxY - plot.height * CGFloat(max(0, min(score, 100)) / 100)
  }

  private func drawAxes(context: GraphicsContext, plot: CGRect) {
    // 横の目盛り線（0 / 50 / 100）.
    for score in [0.0, 50.0, 100.0] {
      let lineY = y(for: score, in: plot)
      var path = Path()
      path.move(to: CGPoint(x: plot.minX, y: lineY))
      path.addLine(to: CGPoint(x: plot.maxX, y: lineY))
      context.stroke(path, with: .color(Palette.rule.opacity(0.8)), lineWidth: 0.6)
      context.draw(
        Text("\(Int(score))").font(.system(size: 9)).foregroundStyle(Palette.inkMuted),
        at: CGPoint(x: plot.minX - 12, y: lineY),
        anchor: .center
      )
    }
  }

  private func drawCurve(context: GraphicsContext, plot: CGRect) {
    var path = Path()
    let steps = 120
    for step in 0...steps {
      let days = maxDays * Double(step) / Double(steps)
      let score = FreshnessScoring.decayedScore(elapsedDays: days, halfLifeDays: halfLifeDays)
      let vertex = CGPoint(x: x(for: days, in: plot), y: y(for: score, in: plot))
      if step == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
    }
    // 墨のにじみに見立て, 上から下へ抜けていく塗りにする.
    var filled = path
    filled.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
    filled.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
    filled.closeSubpath()
    context.fill(
      filled,
      with: .linearGradient(
        Gradient(colors: [tint.opacity(0.30), tint.opacity(0.02)]),
        startPoint: CGPoint(x: plot.minX, y: plot.minY),
        endPoint: CGPoint(x: plot.minX, y: plot.maxY)
      )
    )
    context.stroke(path, with: .color(tint), lineWidth: 1.5)
  }

  private func drawHalfLifeMarker(context: GraphicsContext, plot: CGRect) {
    let markerX = x(for: Double(halfLifeDays), in: plot)
    var path = Path()
    path.move(to: CGPoint(x: markerX, y: plot.minY))
    path.addLine(to: CGPoint(x: markerX, y: plot.maxY))
    context.stroke(
      path,
      with: .color(Palette.rule),
      style: StrokeStyle(lineWidth: 1, dash: [2, 4])
    )
  }

  private func drawCurrentPosition(context: GraphicsContext, plot: CGRect) {
    let decayed = FreshnessScoring.decayedScore(elapsedDays: Double(elapsedDays), halfLifeDays: halfLifeDays)
    let pointX = x(for: Double(elapsedDays), in: plot)

    // 現在位置の縦線.
    var line = Path()
    line.move(to: CGPoint(x: pointX, y: plot.minY))
    line.addLine(to: CGPoint(x: pointX, y: plot.maxY))
    context.stroke(line, with: .color(tint.opacity(0.7)), lineWidth: 1)

    // 減衰カーブ上の点.
    let curvePoint = CGPoint(x: pointX, y: y(for: decayed, in: plot))
    context.fill(
      Path(ellipseIn: CGRect(x: curvePoint.x - 3.5, y: curvePoint.y - 3.5, width: 7, height: 7)),
      with: .color(tint)
    )

    // 補正を含む最終スコアの位置（減衰値と異なる場合のみ）.
    if abs(decayed - Double(finalScore)) >= 1 {
      let finalPoint = CGPoint(x: pointX, y: y(for: Double(finalScore), in: plot))
      context.stroke(
        Path(ellipseIn: CGRect(x: finalPoint.x - 5, y: finalPoint.y - 5, width: 10, height: 10)),
        with: .color(tint),
        lineWidth: 2
      )
    }

    context.draw(
      Text("\(elapsedDays)日").font(.custom("HiraMinProN-W6", size: 10, relativeTo: .caption2)).foregroundStyle(tint),
      at: CGPoint(x: min(pointX, plot.maxX - 16), y: plot.maxY + 10),
      anchor: .center
    )
  }

  private func legend(color: Color, text: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Rectangle().fill(color).frame(width: 12, height: 2)
      Text(text)
    }
  }
}
