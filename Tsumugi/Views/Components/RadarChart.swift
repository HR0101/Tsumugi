//
//  RadarChart.swift
//  Tsumugi
//
//  仕様書 S-04: 信頼度診断詳細画面の 5 カテゴリのレーダーチャート.
//  判定できなかったカテゴリは面に含めない（仕様書 9.6「不明の明示」）.
//
//  家紋の作りを借りて, 細い罫の円で全体を囲み, 中の図形は 5 つの頂点を結んだ多角形にする.
//  塗りはグラデーションを使わず, 染めた布のような一様な色で置く.
//

import SwiftUI

struct RadarChart: View {

  /// 1 軸分のデータ.
  struct Axis: Identifiable {
    let id: String
    let label: String
    let value: Int
    let isDetermined: Bool
  }

  let axes: [Axis]
  let tint: Color
  /// 目盛りの本数.
  private let gridLevels = 4

  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      // ラベルを描く余白を確保する.
      let radius = min(size.width, size.height) / 2 - 34
      guard radius > 0, axes.count >= 3 else { return }

      drawEnclosingCircle(context: context, center: center, radius: radius)
      drawGrid(context: context, center: center, radius: radius)
      drawAxes(context: context, center: center, radius: radius)
      drawValuePolygon(context: context, center: center, radius: radius)
      drawLabels(context: context, center: center, radius: radius)
    }
    .aspectRatio(1.15, contentMode: .fit)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilitySummary)
  }

  // MARK: - 描画

  /// 各軸の角度（12 時方向から時計回り）.
  private func angle(at index: Int) -> CGFloat {
    -.pi / 2 + (2 * .pi) * CGFloat(index) / CGFloat(axes.count)
  }

  private func point(center: CGPoint, radius: CGFloat, index: Int, ratio: CGFloat) -> CGPoint {
    let theta = angle(at: index)
    return CGPoint(
      x: center.x + cos(theta) * radius * ratio,
      y: center.y + sin(theta) * radius * ratio
    )
  }

  /// 家紋の「丸に〜」にならって, 図形全体を細い円で囲う.
  private func drawEnclosingCircle(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
    let outer = radius + 10
    let circle = Path(ellipseIn: CGRect(
      x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2
    ))
    context.stroke(circle, with: .color(Palette.rule), lineWidth: 1)
  }

  private func drawGrid(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
    for level in 1...gridLevels {
      let ratio = CGFloat(level) / CGFloat(gridLevels)
      var path = Path()
      for index in axes.indices {
        let vertex = point(center: center, radius: radius, index: index, ratio: ratio)
        if index == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
      }
      path.closeSubpath()
      context.stroke(path, with: .color(Palette.rule.opacity(0.75)), lineWidth: 0.6)
    }
  }

  private func drawAxes(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
    for index in axes.indices {
      var path = Path()
      path.move(to: center)
      path.addLine(to: point(center: center, radius: radius, index: index, ratio: 1))
      context.stroke(path, with: .color(Palette.rule.opacity(0.75)), lineWidth: 0.6)
    }
  }

  private func drawValuePolygon(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
    var path = Path()
    for index in axes.indices {
      let axis = axes[index]
      // 判定できなかった軸は 0 として扱い, へこみで「欠けている」ことを見せる.
      let ratio = axis.isDetermined ? CGFloat(max(0, min(100, axis.value))) / 100 : 0
      let vertex = point(center: center, radius: radius, index: index, ratio: ratio)
      if index == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
    }
    path.closeSubpath()

    // 染めた布のように, 一様な色で塗る.
    context.fill(path, with: .color(tint.opacity(0.24)))
    context.stroke(path, with: .color(tint), lineWidth: 1.4)

    // 頂点に小さな点を打つ（糸の結び目のつもり）.
    for index in axes.indices where axes[index].isDetermined {
      let ratio = CGFloat(max(0, min(100, axes[index].value))) / 100
      let vertex = point(center: center, radius: radius, index: index, ratio: ratio)
      let dot = Path(ellipseIn: CGRect(x: vertex.x - 2.5, y: vertex.y - 2.5, width: 5, height: 5))
      context.fill(dot, with: .color(tint))
    }
  }

  private func drawLabels(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
    for index in axes.indices {
      let axis = axes[index]
      let anchor = point(center: center, radius: radius + 20, index: index, ratio: 1)

      let title = Text(axis.label)
        .font(.custom("HiraMinProN-W6", size: 11, relativeTo: .caption2))
        .foregroundStyle(axis.isDetermined ? Palette.ink : Palette.inkMuted)
      context.draw(title, at: anchor, anchor: .center)

      let valueText = Text(axis.isDetermined ? "\(axis.value)" : "—")
        .font(.custom("HiraMinProN-W6", size: 12, relativeTo: .caption2))
        .foregroundStyle(axis.isDetermined ? tint : Palette.inkMuted)
      context.draw(valueText, at: CGPoint(x: anchor.x, y: anchor.y + 12), anchor: .center)
    }
  }

  private var accessibilitySummary: String {
    let parts = axes.map { axis in
      axis.isDetermined ? "\(axis.label) \(axis.value) 点" : "\(axis.label) は判定できませんでした"
    }
    return "カテゴリ別スコア. " + parts.joined(separator: ", ")
  }
}
