//
//  DecayChart.swift
//  Tsumugi
//
//  仕様書 S-05: 鮮度診断詳細画面の半減期グラフ.
//  F_time = 100 × 0.5^(Δt / H) の曲線と, 現在位置を重ねて描く.
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
        legend(color: .secondary, text: "半減期 \(halfLifeDays) 日")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
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
      context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 0.8)
      context.draw(
        Text("\(Int(score))").font(.system(size: 9)).foregroundStyle(.secondary),
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
    context.stroke(path, with: .color(tint), lineWidth: 2)

    // 曲線の下を薄く塗る.
    var filled = path
    filled.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
    filled.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
    filled.closeSubpath()
    context.fill(filled, with: .color(tint.opacity(0.12)))
  }

  private func drawHalfLifeMarker(context: GraphicsContext, plot: CGRect) {
    let markerX = x(for: Double(halfLifeDays), in: plot)
    var path = Path()
    path.move(to: CGPoint(x: markerX, y: plot.minY))
    path.addLine(to: CGPoint(x: markerX, y: plot.maxY))
    context.stroke(
      path,
      with: .color(.secondary.opacity(0.5)),
      style: StrokeStyle(lineWidth: 1, dash: [3, 3])
    )
  }

  private func drawCurrentPosition(context: GraphicsContext, plot: CGRect) {
    let decayed = FreshnessScoring.decayedScore(elapsedDays: Double(elapsedDays), halfLifeDays: halfLifeDays)
    let pointX = x(for: Double(elapsedDays), in: plot)

    // 現在位置の縦線.
    var line = Path()
    line.move(to: CGPoint(x: pointX, y: plot.minY))
    line.addLine(to: CGPoint(x: pointX, y: plot.maxY))
    context.stroke(line, with: .color(tint.opacity(0.6)), lineWidth: 1)

    // 減衰カーブ上の点.
    let curvePoint = CGPoint(x: pointX, y: y(for: decayed, in: plot))
    context.fill(
      Path(ellipseIn: CGRect(x: curvePoint.x - 4, y: curvePoint.y - 4, width: 8, height: 8)),
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
      Text("\(elapsedDays)日").font(.system(size: 9).weight(.medium)).foregroundStyle(tint),
      at: CGPoint(x: min(pointX, plot.maxX - 16), y: plot.maxY + 10),
      anchor: .center
    )
  }

  private func legend(color: Color, text: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Capsule().fill(color).frame(width: 12, height: 3)
      Text(text)
    }
  }
}
