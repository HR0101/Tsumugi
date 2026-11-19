//
//  ElasticMotion.swift
//  Tsumugi / ShareExtension 共通
//
//  iOS Elastic & Liquid UI Motion Grammar（全9パターン）を,
//  紬の和紙・伝統色（Palette）に合わせて組み立てた共通モーション基盤.
//

import SwiftUI
import UIKit
import Observation

// MARK: - 0. Motion Tokens & Wa Palette Aliases

enum ElasticMotion {
  // Video-Derived Asymmetric Springs
  static let elasticArchOpen = Animation.spring(response: 0.45, dampingFraction: 0.52)
  static let liquidOpen = Animation.spring(response: 0.45, dampingFraction: 0.50)
  static let liquidClose = Animation.spring(response: 0.30, dampingFraction: 0.92)
  static let iconSpin = Animation.spring(response: 0.28, dampingFraction: 0.72)
  static let pillExpand = Animation.spring(response: 0.42, dampingFraction: 0.68)

  // Cute Elastic Extension Springs
  static let squishPress = Animation.spring(response: 0.22, dampingFraction: 0.78)
  static let squishRelease = Animation.spring(response: 0.36, dampingFraction: 0.45)
  static let elasticTab = Animation.spring(response: 0.40, dampingFraction: 0.62)
  static let elasticTabFast = Animation.spring(response: 0.28, dampingFraction: 0.56)
  static let elasticTabSlow = Animation.spring(response: 0.44, dampingFraction: 0.64)
  static let jellyPop = Animation.spring(response: 0.46, dampingFraction: 0.52)
  static let rubberSnap = Animation.spring(response: 0.44, dampingFraction: 0.48)
  static let sparkleBurst = Animation.spring(response: 0.48, dampingFraction: 0.55)
  static let toastOpen = Animation.spring(response: 0.42, dampingFraction: 0.52)
  static let toastClose = Animation.spring(response: 0.28, dampingFraction: 0.92)
  static let microFade = Animation.easeOut(duration: 0.16)

  // Wa-Themed Semantic Colors
  static let sheetTop = Palette.paper
  static let sheetBottom = Palette.ground
  static let accent = Palette.indigo
  static let accentSecondary = Palette.asagi
  static let pillFill = Palette.indigo
  static let destructive = Palette.suou
  static let sendEnabled = Palette.indigo
  static let sendDisabled = Palette.rule
  static let sparklePrimary = Palette.yamabuki
  static let sparkleSecondary = Palette.asagi
  static let segmentTrack = Palette.trackTint
  static let segmentPill = Palette.paper
}

// MARK: - 1. Pattern 1: 弾性アーチ変形シート

struct ElasticArchSheetShape: Shape {
  var cornerRadius: CGFloat = 28
  /// 正: 上へ凸アーチ、負: 下へ凹サグ、0: 水平
  var bowOffset: CGFloat

  nonisolated var animatableData: CGFloat {
    get { bowOffset }
    set { bowOffset = newValue }
  }

  nonisolated func path(in rect: CGRect) -> Path {
    var path = Path()
    let r = min(cornerRadius, rect.width / 2)

    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + r, y: rect.minY),
      control: CGPoint(x: rect.minX, y: rect.minY)
    )
    // 2次ベジェ中央の変位は controlY の 1/2 のため bowOffset * 2
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - r, y: rect.minY),
      control: CGPoint(x: rect.midX, y: rect.minY - bowOffset * 2)
    )
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + r),
      control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

struct ElasticSheetOverlay<Content: View>: View {
  @Binding var isPresented: Bool
  var onScrimTap: (() -> Void)? = nil
  @ViewBuilder var content: () -> Content

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var bowOffset: CGFloat = 0
  @State private var sheetVisible = false
  @State private var archTask: Task<Void, Never>?

  var body: some View {
    ZStack(alignment: .bottom) {
      if sheetVisible {
        // 背面スケールは 1.0x 固定のまま, 20% の静かな減光のみで奥行きを作る.
        Color.black.opacity(0.20)
          .ignoresSafeArea()
          .transition(.opacity)
          .onTapGesture {
            if let onScrimTap {
              onScrimTap()
            } else {
              isPresented = false
            }
          }
          .accessibilityAddTraits(.isButton)
          .accessibilityLabel("シートを閉じる")

        VStack(spacing: 0) {
          Capsule()
            .fill(Palette.rule.opacity(0.85))
            .frame(width: 36, height: 4)
            .padding(.top, 9)
            .padding(.bottom, 4)
            .offset(y: -bowOffset * 0.65)
            .accessibilityHidden(true)

          content()
        }
        .frame(maxWidth: .infinity)
        .background {
          let sheetShape = ElasticArchSheetShape(bowOffset: bowOffset)
          sheetShape
            .fill(ElasticMotion.sheetTop)
            .overlay {
              sheetShape
                .stroke(Palette.rule, lineWidth: Radius.hairline)
            }
            .shadow(color: Palette.shadow.opacity(PaperShadow.raised.opacity), radius: PaperShadow.raised.radius, y: -4)
            .ignoresSafeArea(edges: .bottom)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .onAppear {
      if isPresented && !sheetVisible {
        presentSheet()
      }
    }
    .onChange(of: isPresented) { _, show in
      if show {
        presentSheet()
      } else {
        dismissSheet()
      }
    }
    .onDisappear {
      archTask?.cancel()
      archTask = nil
    }
  }

  private func presentSheet() {
    archTask?.cancel()
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : ElasticMotion.elasticArchOpen) {
      sheetVisible = true
      bowOffset = reduceMotion ? 0 : 40
    }
    guard !reduceMotion else { return }
    archTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(90))
      guard !Task.isCancelled, isPresented else { return }
      withAnimation(ElasticMotion.elasticArchOpen) {
        bowOffset = 0
      }
    }
  }

  private func dismissSheet() {
    archTask?.cancel()
    withAnimation(ElasticMotion.liquidClose) {
      bowOffset = 0
      sheetVisible = false
    }
  }
}

// MARK: - 2. Pattern 2: 送信ボタン活性化＆発射ポップ

struct ElasticSendButton: View {
  var isEnabled: Bool
  var isLoading: Bool = false
  var symbolName: String = "arrow.up"
  var accessibilityLabelText: String = "送信"
  var size: CGFloat = 36
  var action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var iconOffsetY: CGFloat = 0
  @State private var iconOpacity: Double = 1
  @State private var launchCount = 0
  @State private var resetTask: Task<Void, Never>?

  var body: some View {
    Button {
      trigger()
    } label: {
      ZStack {
        Circle()
          .fill(isEnabled ? ElasticMotion.sendEnabled : ElasticMotion.sendDisabled)
          .animation(ElasticMotion.microFade, value: isEnabled)

        if isLoading {
          ProgressView()
            .controlSize(.small)
            .tint(Palette.paper)
        } else {
          Image(systemName: symbolName)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(Palette.paper)
            .offset(y: iconOffsetY)
            .opacity(iconOpacity)
        }
      }
      .frame(width: size, height: size)
      .contentShape(Circle())
    }
    .buttonStyle(SquishyPillButtonStyle(pressScaleX: 1.09, pressScaleY: 0.88))
    .disabled(!isEnabled || isLoading)
    .accessibilityLabel(accessibilityLabelText)
    .sensoryFeedback(.impact(flexibility: .soft), trigger: launchCount)
    .onDisappear {
      resetTask?.cancel()
      resetTask = nil
    }
  }

  private func trigger() {
    guard isEnabled, !isLoading else { return }
    launchCount += 1
    resetTask?.cancel()

    if !reduceMotion {
      withAnimation(ElasticMotion.squishRelease) {
        iconOffsetY = -18
        iconOpacity = 0
      }
      resetTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(260))
        guard !Task.isCancelled else { return }
        iconOffsetY = 10
        iconOpacity = 0
        withAnimation(ElasticMotion.microFade) {
          iconOffsetY = 0
          iconOpacity = 1
        }
      }
    }
    action()
  }
}

// MARK: - 3. Pattern 3: リアルタイムテキスト判定 → 放物線オーブ飛翔 → ピル展開

enum DetectionPhase: Equatable {
  case idle
  case drawingUnderline
  case condensingOrb
  case flyingOrb
  case pillActive
}

nonisolated func quadBezierPoint(t: CGFloat, p0: CGPoint, control: CGPoint, p1: CGPoint) -> CGPoint {
  let u = 1 - t
  return CGPoint(
    x: u * u * p0.x + 2 * u * t * control.x + t * t * p1.x,
    y: u * u * p0.y + 2 * u * t * control.y + t * t * p1.y
  )
}

/// 必ず `.overlay { DetectionFlightLayer(...) }` でコンポーザー本体へ重ねる（ZStack 兄弟禁止）.
struct DetectionFlightLayer: View, @MainActor Animatable {
  var phase: DetectionPhase
  var tokenRect: CGRect
  var targetCenter: CGPoint
  var underlineTrimStart: CGFloat
  var underlineTrimEnd: CGFloat
  var flightProgress: CGFloat

  init(
    phase: DetectionPhase,
    tokenRect: CGRect,
    targetCenter: CGPoint,
    underlineTrimStart: CGFloat,
    underlineTrimEnd: CGFloat,
    flightProgress: CGFloat
  ) {
    self.phase = phase
    self.tokenRect = tokenRect
    self.targetCenter = targetCenter
    self.underlineTrimStart = underlineTrimStart
    self.underlineTrimEnd = underlineTrimEnd
    self.flightProgress = flightProgress
  }

  init(controller: DetectionFlightController) {
    self.init(
      phase: controller.phase,
      tokenRect: controller.tokenRectInContainer,
      targetCenter: controller.pillCenter,
      underlineTrimStart: controller.underlineTrimStart,
      underlineTrimEnd: controller.underlineTrimEnd,
      flightProgress: controller.flightProgress
    )
  }

  var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
    get { AnimatablePair(underlineTrimStart, AnimatablePair(underlineTrimEnd, flightProgress)) }
    set {
      underlineTrimStart = newValue.first
      underlineTrimEnd = newValue.second.first
      flightProgress = newValue.second.second
    }
  }

  var body: some View {
    ZStack {
      if (phase == .drawingUnderline || phase == .condensingOrb), !tokenRect.isEmpty {
        Path { path in
          let y = tokenRect.maxY + 1.5
          path.move(to: CGPoint(x: tokenRect.minX, y: y))
          path.addLine(to: CGPoint(x: tokenRect.maxX, y: y))
        }
        .trim(from: underlineTrimStart, to: underlineTrimEnd)
        .stroke(ElasticMotion.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
      }

      if (phase == .condensingOrb || phase == .flyingOrb), !tokenRect.isEmpty, targetCenter != .zero {
        let p0 = CGPoint(x: tokenRect.maxX, y: tokenRect.maxY + 1.5)
        // 文字へ被らない低めホップ制御点 (-7pt)
        let control = CGPoint(x: p0.x + (targetCenter.x - p0.x) * 0.35, y: p0.y - 7)
        let pos = phase == .condensingOrb ? p0 : quadBezierPoint(t: flightProgress, p0: p0, control: control, p1: targetCenter)
        let diameter: CGFloat = phase == .condensingOrb ? 9.5 : (9.5 - 4.8 * flightProgress)

        Circle()
          .fill(ElasticMotion.accent)
          .frame(width: diameter, height: diameter)
          .position(pos)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct TextDetectionMatch: Equatable {
  enum Kind: Equatable {
    case url(String)
    case hashtag(String)
    case date(Date)
  }

  let text: String
  let displayLabel: String
  let kind: Kind
  let rectInTextView: CGRect

  var symbolName: String {
    switch kind {
    case .url: return "link"
    case .hashtag: return "tag.fill"
    case .date: return "calendar"
    }
  }
}

enum TextDetectionMode {
  case urlOnly
  case noteTokens
}

struct DetectingTextView: UIViewRepresentable {
  @Binding var text: String
  var mode: TextDetectionMode
  var isURLInput: Bool = false
  var accessibilityLabel: String = "テキスト入力"
  var onDetectionChange: (TextDetectionMatch?) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    textView.backgroundColor = .clear
    textView.font = UIFont.preferredFont(forTextStyle: .callout)
    textView.adjustsFontForContentSizeCategory = true
    textView.textColor = UIColor(Palette.ink)
    textView.tintColor = UIColor(Palette.indigo)
    textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
    textView.textContainer.lineFragmentPadding = 2
    textView.isScrollEnabled = true
    textView.accessibilityLabel = accessibilityLabel

    if isURLInput {
      textView.autocapitalizationType = .none
      textView.autocorrectionType = .no
      textView.keyboardType = .URL
      textView.textContentType = .URL
    } else {
      textView.autocapitalizationType = .sentences
      textView.autocorrectionType = .default
    }

    textView.text = text
    context.coordinator.scheduleInitialDetection(for: textView)
    return textView
  }

  func updateUIView(_ uiView: UITextView, context: Context) {
    context.coordinator.parent = self
    if uiView.text != text {
      uiView.text = text
      context.coordinator.scheduleDetection(in: uiView)
    }
    uiView.accessibilityLabel = accessibilityLabel
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: DetectingTextView
    private var lastReportedMatch: TextDetectionMatch?

    init(parent: DetectingTextView) {
      self.parent = parent
    }

    func scheduleInitialDetection(for textView: UITextView) {
      guard !textView.text.isEmpty else { return }
      scheduleDetection(in: textView)
    }

    func scheduleDetection(in textView: UITextView) {
      DispatchQueue.main.async { [weak self, weak textView] in
        guard let self, let textView else { return }
        self.evaluateDetection(in: textView)
      }
    }

    func textViewDidChange(_ textView: UITextView) {
      let current = textView.text ?? ""
      if parent.text != current {
        parent.text = current
      }
      scheduleDetection(in: textView)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      // スクロール等で枠位置が変わった場合に備え, 既存テキストがあれば座標を再評価する.
      guard !(textView.text ?? "").isEmpty else { return }
      scheduleDetection(in: textView)
    }

    func evaluateDetection(in textView: UITextView) {
      let raw = textView.text ?? ""
      let detected = detectToken(in: raw, textView: textView)
      if detected != lastReportedMatch {
        lastReportedMatch = detected
        parent.onDetectionChange(detected)
      }
    }

    private func detectToken(in text: String, textView: UITextView) -> TextDetectionMatch? {
      guard !text.isEmpty else { return nil }
      let nsText = text as NSString
      let fullRange = NSRange(location: 0, length: nsText.length)

      var candidates: [(range: NSRange, text: String, displayLabel: String, kind: TextDetectionMatch.Kind)] = []

      if parent.mode == .noteTokens {
        if let regex = try? NSRegularExpression(pattern: "#([^\\s#、。,.!?！？]+)") {
          for match in regex.matches(in: text, range: fullRange) where match.numberOfRanges >= 2 {
            let tokenRange = match.range(at: 0)
            let nameRange = match.range(at: 1)
            let token = nsText.substring(with: tokenRange)
            let tagName = nsText.substring(with: nameRange)
            candidates.append((tokenRange, token, "#\(tagName) をタグに追加", .hashtag(tagName)))
          }
        }
      }

      if let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        for match in linkDetector.matches(in: text, range: fullRange) {
          guard let url = match.url,
                let scheme = url.scheme?.lowercased(),
                scheme == "http" || scheme == "https",
                let host = url.host(), !host.isEmpty else {
            continue
          }
          let token = nsText.substring(with: match.range)
          candidates.append((match.range, token, host, .url(url.absoluteString)))
        }
      }

      if parent.mode == .noteTokens,
         let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
        for match in dateDetector.matches(in: text, range: fullRange) {
          guard let date = match.date else { continue }
          let token = nsText.substring(with: match.range)
          candidates.append((match.range, token, DateStyle.short.string(from: date), .date(date)))
        }
      }

      guard let chosen = candidates.max(by: { $0.range.location < $1.range.location }) else {
        return nil
      }

      let rect = boundingRect(for: chosen.range, in: textView)
      return TextDetectionMatch(
        text: chosen.text,
        displayLabel: chosen.displayLabel,
        kind: chosen.kind,
        rectInTextView: rect
      )
    }

    private func boundingRect(for nsRange: NSRange, in textView: UITextView) -> CGRect {
      textView.layoutIfNeeded()
      let beginning = textView.beginningOfDocument
      guard let start = textView.position(from: beginning, offset: nsRange.location),
            let end = textView.position(from: start, offset: nsRange.length),
            let textRange = textView.textRange(from: start, to: end) else {
        return fallbackRect(in: textView)
      }

      var rect = textView.firstRect(for: textRange)
      if rect.isNull || rect.isInfinite || rect.width < 4 || rect.height < 4 {
        let startCaret = textView.caretRect(for: start)
        let endCaret = textView.caretRect(for: end)
        if !startCaret.isNull && !endCaret.isNull {
          rect = startCaret.union(endCaret)
        } else {
          return fallbackRect(in: textView)
        }
      }

      rect = rect.offsetBy(dx: -textView.contentOffset.x, dy: -textView.contentOffset.y)
      let safeBounds = textView.bounds.insetBy(dx: 8, dy: 6)
      let clamped = rect.intersection(safeBounds)
      return clamped.isEmpty ? fallbackRect(in: textView) : clamped
    }

    private func fallbackRect(in textView: UITextView) -> CGRect {
      let inset = textView.textContainerInset
      return CGRect(x: inset.left + 8, y: inset.top + 4, width: max(48, textView.bounds.width * 0.35), height: 22)
    }
  }
}

struct DetectedActionPill: View {
  var phase: DetectionPhase
  var match: TextDetectionMatch?
  var idleSymbol: String = "link"
  var coordinateSpaceName: String
  var onCenterChange: (CGPoint) -> Void
  var action: () -> Void

  var body: some View {
    let isActive = phase == .pillActive && match != nil
    let symbol = match?.symbolName ?? idleSymbol

    Button {
      if isActive { action() }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isActive ? Palette.paper : Palette.indigo)
          .frame(width: 18, height: 18)

        if isActive, let label = match?.displayLabel {
          Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.paper)
            .lineLimit(1)
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
      }
      .padding(.horizontal, isActive ? 12 : 8)
      .frame(height: 32)
      .background {
        Capsule()
          .fill(isActive ? ElasticMotion.pillFill : ElasticMotion.segmentTrack.opacity(0.65))
      }
      .overlay {
        Capsule()
          .strokeBorder(
            isActive ? Color.clear : Palette.rule,
            lineWidth: Radius.hairline
          )
      }
      .clipShape(Capsule())
    }
    .buttonStyle(SquishyPillButtonStyle(pressScaleX: 1.07, pressScaleY: 0.90))
    .disabled(!isActive)
    .animation(ElasticMotion.pillExpand, value: isActive)
    .onGeometryChange(for: CGPoint.self) { proxy in
      let frame = proxy.frame(in: .named(coordinateSpaceName))
      return CGPoint(x: frame.midX, y: frame.midY)
    } action: { center in
      onCenterChange(center)
    }
    .accessibilityLabel(isActive ? (match?.displayLabel ?? "検出結果") : "リンクやタグの検出待機中")
  }
}

@Observable
final class DetectionFlightController {
  var phase: DetectionPhase = .idle
  var activeMatch: TextDetectionMatch?
  var textViewFrame: CGRect = .zero
  var pillCenter: CGPoint = .zero
  var underlineTrimStart: CGFloat = 0
  var underlineTrimEnd: CGFloat = 0
  var flightProgress: CGFloat = 0

  private var task: Task<Void, Never>?
  private var lastFlownSignature: String?

  var tokenRectInContainer: CGRect {
    guard let match = activeMatch else { return .zero }
    return match.rectInTextView.offsetBy(dx: textViewFrame.minX, dy: textViewFrame.minY)
  }

  func handleMatchChange(_ match: TextDetectionMatch?, reduceMotion: Bool) {
    task?.cancel()
    guard let match else {
      lastFlownSignature = nil
      withAnimation(ElasticMotion.liquidClose) {
        phase = .idle
        activeMatch = nil
        underlineTrimStart = 0
        underlineTrimEnd = 0
        flightProgress = 0
      }
      return
    }

    let signature = "\(match.text)|\(match.displayLabel)"
    if phase == .pillActive, lastFlownSignature == signature {
      activeMatch = match
      return
    }

    activeMatch = match
    underlineTrimStart = 0
    underlineTrimEnd = 0
    flightProgress = 0
    if phase == .pillActive {
      phase = .idle
    }

    task = Task { @MainActor in
      // 判定デバウンス: 入力停止から 550ms 後に発動.
      try? await Task.sleep(for: .milliseconds(550))
      guard !Task.isCancelled else { return }

      if reduceMotion {
        lastFlownSignature = signature
        withAnimation(ElasticMotion.microFade) {
          phase = .pillActive
        }
        return
      }

      // 1. 下線ドロー (230ms)
      phase = .drawingUnderline
      withAnimation(.easeOut(duration: 0.23)) {
        underlineTrimEnd = 1.0
      }
      try? await Task.sleep(for: .milliseconds(230))
      guard !Task.isCancelled else { return }

      // 2. 右端オーブ凝縮 (150ms + 33ms 溜め)
      phase = .condensingOrb
      withAnimation(.easeIn(duration: 0.15)) {
        underlineTrimStart = 1.0
      }
      try? await Task.sleep(for: .milliseconds(183))
      guard !Task.isCancelled else { return }

      // 3. 放物線アーク飛翔 (270ms)
      phase = .flyingOrb
      flightProgress = 0
      withAnimation(.timingCurve(0.22, 0.72, 0.32, 1.0, duration: 0.27)) {
        flightProgress = 1.0
      }
      try? await Task.sleep(for: .milliseconds(270))
      guard !Task.isCancelled else { return }

      // 4. 着弾 → ピル展開
      lastFlownSignature = signature
      withAnimation(ElasticMotion.pillExpand) {
        phase = .pillActive
      }
    }
  }

  func reset() {
    task?.cancel()
    task = nil
    lastFlownSignature = nil
    phase = .idle
    activeMatch = nil
    underlineTrimStart = 0
    underlineTrimEnd = 0
    flightProgress = 0
  }

  func cancel() {
    task?.cancel()
    task = nil
  }
}

// MARK: - 4. Pattern 4: リキッドキャンセル UI（iOS 26+ Native Liquid Glass）

@available(iOS 26.0, *)
struct LiquidGlassCancelHeader<TrailingContent: View>: View {
  @Binding var isExpanded: Bool
  var title: String
  var expandOnCloseTap: Bool = true
  var primaryLabel: String = "破棄"
  var primarySymbol: String = "trash"
  var primaryIsDestructive: Bool = true
  var secondaryLabel: String? = "下書きに保存"
  var secondarySymbol: String = "tray.and.arrow.down"
  var onPrimary: () -> Void
  var onSecondary: (() -> Void)? = nil
  var onImmediateDismiss: (() -> Void)? = nil
  @ViewBuilder var trailingContent: () -> TrailingContent

  @Namespace private var glassNS
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var stage1 = false
  @State private var stage2 = false
  @State private var showTitle = true
  @State private var iconRotation: Angle = .zero
  @State private var cascadeTask: Task<Void, Never>?

  var body: some View {
    ZStack {
      Text(title)
        .font(WaFont.heading)
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
        .opacity(showTitle ? 1 : 0)
        .blur(radius: showTitle ? 0 : 4)
        .accessibilityHidden(!showTitle)

      HStack {
        GlassEffectContainer(spacing: 10) {
          HStack(spacing: 10) {
            Button {
              if isExpanded {
                isExpanded = false
              } else if expandOnCloseTap {
                isExpanded = true
              } else {
                onImmediateDismiss?()
              }
            } label: {
              Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .rotationEffect(iconRotation)
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID("close", in: glassNS)
            .frame(width: 40, height: 40)
            .contentShape(Circle())
            .accessibilityLabel(isExpanded ? "キャンセルを閉じる" : "閉じる")

            if stage1 {
              Button(action: onPrimary) {
                Label(primaryLabel, systemImage: primarySymbol)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(primaryIsDestructive ? ElasticMotion.destructive : Palette.ink)
                  .padding(.horizontal, 14)
                  .frame(height: 40)
              }
              .buttonStyle(.plain)
              .glassEffect(.regular.interactive(), in: .capsule)
              .glassEffectID("primary", in: glassNS)
            }

            if stage2, let secondaryLabel {
              Button {
                onSecondary?()
              } label: {
                Label(secondaryLabel, systemImage: secondarySymbol)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(Palette.indigo)
                  .padding(.horizontal, 14)
                  .frame(height: 40)
              }
              .buttonStyle(.plain)
              .glassEffect(.regular.interactive(), in: .capsule)
              .glassEffectID("secondary", in: glassNS)
            }
          }
          .accessibilityElement(children: .contain)
        }

        Spacer(minLength: 8)

        if !isExpanded {
          trailingContent()
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
      }
    }
    .frame(minHeight: 44)
    .sensoryFeedback(.impact(flexibility: .soft), trigger: isExpanded)
    .onChange(of: isExpanded) { _, expanded in
      runCascade(expanded: expanded)
    }
    .onDisappear {
      cascadeTask?.cancel()
      cascadeTask = nil
    }
  }

  private func runCascade(expanded: Bool) {
    cascadeTask?.cancel()
    cascadeTask = Task { @MainActor in
      if expanded {
        withAnimation(.easeOut(duration: 0.12)) { showTitle = false }
        withAnimation(reduceMotion ? .linear(duration: 0.12) : ElasticMotion.iconSpin) {
          iconRotation = .degrees(90)
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : ElasticMotion.liquidOpen) {
          stage1 = true
        }
        guard secondaryLabel != nil else { return }
        try? await Task.sleep(for: .milliseconds(110))
        guard !Task.isCancelled, isExpanded else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : ElasticMotion.liquidOpen) {
          stage2 = true
        }
      } else {
        withAnimation(ElasticMotion.liquidClose) {
          iconRotation = .zero
          stage2 = false
        }
        try? await Task.sleep(for: .milliseconds(60))
        guard !Task.isCancelled, !isExpanded else { return }
        withAnimation(ElasticMotion.liquidClose) {
          stage1 = false
        }
        try? await Task.sleep(for: .milliseconds(190))
        guard !Task.isCancelled, !isExpanded else { return }
        withAnimation(ElasticMotion.microFade) {
          showTitle = true
        }
      }
    }
  }
}

@available(iOS 26.0, *)
extension LiquidGlassCancelHeader where TrailingContent == EmptyView {
  init(
    isExpanded: Binding<Bool>,
    title: String,
    expandOnCloseTap: Bool = true,
    primaryLabel: String = "破棄",
    primarySymbol: String = "trash",
    primaryIsDestructive: Bool = true,
    secondaryLabel: String? = "下書きに保存",
    secondarySymbol: String = "tray.and.arrow.down",
    onPrimary: @escaping () -> Void,
    onSecondary: (() -> Void)? = nil,
    onImmediateDismiss: (() -> Void)? = nil
  ) {
    self.init(
      isExpanded: isExpanded,
      title: title,
      expandOnCloseTap: expandOnCloseTap,
      primaryLabel: primaryLabel,
      primarySymbol: primarySymbol,
      primaryIsDestructive: primaryIsDestructive,
      secondaryLabel: secondaryLabel,
      secondarySymbol: secondarySymbol,
      onPrimary: onPrimary,
      onSecondary: onSecondary,
      onImmediateDismiss: onImmediateDismiss,
      trailingContent: { EmptyView() }
    )
  }
}

// MARK: - 5. Pattern 5: 体積保存スクイッシュ押し込みボタン

struct SquishyPillButtonStyle: ButtonStyle {
  var pressScaleX: CGFloat = 1.07
  var pressScaleY: CGFloat = 0.90

  func makeBody(configuration: Configuration) -> some View {
    BodyView(
      configuration: configuration,
      pressScaleX: pressScaleX,
      pressScaleY: pressScaleY
    )
  }

  private struct BodyView: View {
    let configuration: Configuration
    let pressScaleX: CGFloat
    let pressScaleY: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      let pressed = configuration.isPressed
      configuration.label
        .scaleEffect(
          x: pressed && !reduceMotion ? pressScaleX : 1.0,
          y: pressed && !reduceMotion ? pressScaleY : 1.0,
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

// MARK: - 6. Pattern 6: ゼリー・セグメントピルバー

struct ElasticSegmentedBar<SelectionValue: Hashable>: View {
  let options: [(value: SelectionValue, title: String)]
  @Binding var selection: SelectionValue

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var spaceID = UUID().uuidString
  @State private var tabFrames: [Int: CGRect] = [:]
  @State private var pillMinX: CGFloat = 0
  @State private var pillMaxX: CGFloat = 0
  @State private var pillHeight: CGFloat = 34
  @State private var initialized = false
  @State private var lastAnimatedIndex: Int?

  private var selectedIndex: Int? {
    options.firstIndex { $0.value == selection }
  }

  var body: some View {
    let coordName = "elasticSegSpace-\(spaceID)"

    ZStack(alignment: .leading) {
      if initialized && pillMaxX > pillMinX {
        Capsule()
          .fill(ElasticMotion.segmentPill)
          .overlay {
            Capsule()
              .strokeBorder(Palette.rule, lineWidth: Radius.hairline)
          }
          .shadow(color: Palette.shadow.opacity(PaperShadow.resting.opacity), radius: PaperShadow.resting.radius, y: PaperShadow.resting.y)
          .frame(width: max(20, pillMaxX - pillMinX), height: pillHeight)
          .offset(x: pillMinX)
      }

      HStack(spacing: 4) {
        ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
          let isSelected = option.value == selection
          Button {
            select(idx)
          } label: {
            Text(option.title)
              .font(.subheadline.weight(isSelected ? .semibold : .medium))
              .foregroundStyle(isSelected ? Palette.ink : Palette.inkMuted)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
              .padding(.horizontal, 10)
              .padding(.vertical, 8)
              .frame(maxWidth: .infinity)
              .contentShape(Capsule())
          }
          .buttonStyle(SquishyPillButtonStyle(pressScaleX: 1.05, pressScaleY: 0.92))
          .accessibilityAddTraits(isSelected ? [.isSelected] : [])
          .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(coordName))
          } action: { rect in
            let previous = tabFrames[idx]
            tabFrames[idx] = rect
            if isSelected && !initialized {
              pillMinX = rect.minX
              pillMaxX = rect.maxX
              pillHeight = rect.height
              lastAnimatedIndex = idx
              initialized = true
            } else if isSelected, let previous, abs(previous.width - rect.width) > 1.5 {
              pillMinX = rect.minX
              pillMaxX = rect.maxX
              pillHeight = rect.height
            }
          }
        }
      }
    }
    .padding(4)
    .background {
      Capsule()
        .fill(ElasticMotion.segmentTrack)
        .overlay {
          Capsule()
            .strokeBorder(Palette.rule.opacity(0.45), lineWidth: Radius.hairline)
        }
    }
    .coordinateSpace(name: coordName)
    .sensoryFeedback(.selection, trigger: selection)
    .onChange(of: selection) { _, _ in
      guard let newIdx = selectedIndex, newIdx != lastAnimatedIndex, let target = tabFrames[newIdx] else {
        return
      }
      let movingRight = (lastAnimatedIndex ?? newIdx) < newIdx
      lastAnimatedIndex = newIdx
      animatePill(to: target, movingRight: movingRight)
    }
  }

  private func select(_ newIndex: Int) {
    guard options.indices.contains(newIndex) else { return }
    let oldIndex = selectedIndex ?? newIndex
    guard newIndex != oldIndex, let target = tabFrames[newIndex] else {
      lastAnimatedIndex = newIndex
      selection = options[newIndex].value
      return
    }
    let movingRight = newIndex > oldIndex
    lastAnimatedIndex = newIndex
    selection = options[newIndex].value
    animatePill(to: target, movingRight: movingRight)
  }

  private func animatePill(to target: CGRect, movingRight: Bool) {
    if reduceMotion {
      withAnimation(ElasticMotion.microFade) {
        pillMinX = target.minX
        pillMaxX = target.maxX
        pillHeight = target.height
      }
      return
    }

    withAnimation(movingRight ? ElasticMotion.elasticTabSlow : ElasticMotion.elasticTabFast) {
      pillMinX = target.minX
    }
    withAnimation(movingRight ? ElasticMotion.elasticTabFast : ElasticMotion.elasticTabSlow) {
      pillMaxX = target.maxX
      pillHeight = target.height
    }
  }
}

// MARK: - 7. Pattern 7: ゼリー出現＆ラバーバンドカード

enum RubberDragMode {
  case free
  case horizontalScrollSafe
  case entranceOnly
}

struct JellyRubberCard<Content: View>: View {
  var appearIndex: Int = 0
  var dragMode: RubberDragMode = .horizontalScrollSafe
  var useHighPriorityDrag: Bool = false
  @ViewBuilder var content: () -> Content

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false
  @State private var dragOffset: CGSize = .zero
  @State private var isPullingHorizontal = false
  @State private var appearTask: Task<Void, Never>?

  private var freeDragGesture: some Gesture {
    DragGesture(minimumDistance: 8)
      .onChanged { value in
        guard !reduceMotion else { return }
        dragOffset = CGSize(
          width: rubberBand(value.translation.width, limit: 42),
          height: rubberBand(value.translation.height, limit: 34)
        )
      }
      .onEnded { _ in
        withAnimation(ElasticMotion.rubberSnap) {
          dragOffset = .zero
        }
      }
  }

  private var horizontalScrollSafeGesture: some Gesture {
    DragGesture(minimumDistance: 14)
      .onChanged { value in
        guard !reduceMotion else { return }
        let t = value.translation
        if !isPullingHorizontal {
          guard abs(t.width) > abs(t.height) * 1.25, abs(t.width) > 14 else { return }
          isPullingHorizontal = true
        }
        dragOffset = CGSize(
          width: rubberBand(t.width, limit: 42),
          height: rubberBand(t.height, limit: 16)
        )
      }
      .onEnded { _ in
        isPullingHorizontal = false
        withAnimation(ElasticMotion.rubberSnap) {
          dragOffset = .zero
        }
      }
  }

  var body: some View {
    let stretchX = 1.0 - min(abs(dragOffset.height) / 360, 0.06) + min(abs(dragOffset.width) / 260, 0.07)
    let stretchY = 1.0 + min(abs(dragOffset.height) / 260, 0.07) - min(abs(dragOffset.width) / 360, 0.05)

    let styled = content()
      .scaleEffect(
        x: appeared ? (reduceMotion ? 1.0 : stretchX) : 0.90,
        y: appeared ? (reduceMotion ? 1.0 : stretchY) : 1.08,
        anchor: .center
      )
      .opacity(appeared ? 1 : 0)
      .offset(dragOffset)
      .rotationEffect(.degrees(Double(dragOffset.width) * 0.03))
      .onAppear {
        scheduleAppear()
      }
      .onDisappear {
        appearTask?.cancel()
        appearTask = nil
      }

    switch dragMode {
    case .entranceOnly:
      styled
    case .horizontalScrollSafe:
      styled.simultaneousGesture(horizontalScrollSafeGesture)
    case .free:
      if useHighPriorityDrag {
        styled.highPriorityGesture(freeDragGesture)
      } else {
        styled.gesture(freeDragGesture)
      }
    }
  }

  private func scheduleAppear() {
    guard !appeared else { return }
    appearTask?.cancel()
    let clampedIndex = min(max(0, appearIndex), 6)
    if reduceMotion || clampedIndex == 0 {
      withAnimation(reduceMotion ? .easeOut(duration: 0.2) : ElasticMotion.jellyPop) {
        appeared = true
      }
    } else {
      appearTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(clampedIndex * 55))
        guard !Task.isCancelled else { return }
        withAnimation(ElasticMotion.jellyPop) {
          appeared = true
        }
      }
    }
  }

  private func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
    let sign: CGFloat = value >= 0 ? 1 : -1
    let absVal = abs(value)
    return sign * (limit * absVal) / (absVal + limit)
  }
}

// MARK: - 8. Pattern 8: スパークル・ポップトグル＆数字ロール

struct SparklePopToggle: View {
  var isOn: Bool
  var count: Int? = nil
  var label: String? = nil
  var symbolName: String = "bookmark.fill"
  var activeColor: Color = ElasticMotion.sparklePrimary
  var secondaryColor: Color = ElasticMotion.sparkleSecondary
  var onToggle: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var burstProgress: CGFloat = 0
  @State private var burstOpacity: CGFloat = 0
  @State private var iconScale: CGFloat = 1.0
  @State private var animTask: Task<Void, Never>?

  var body: some View {
    Button(action: onToggle) {
      HStack(spacing: 6) {
        ZStack {
          ForEach(0..<6, id: \.self) { idx in
            let angle = Double(idx) * (Double.pi * 2 / 6) - Double.pi / 6
            let radius = 18 * burstProgress
            Circle()
              .fill(idx.isMultiple(of: 2) ? activeColor : secondaryColor)
              .frame(width: 5 * (1 - burstProgress * 0.65), height: 5 * (1 - burstProgress * 0.65))
              .offset(x: cos(angle) * radius, y: sin(angle) * radius)
              .opacity(burstOpacity)
          }

          Image(systemName: isOn ? symbolName : symbolName.replacingOccurrences(of: ".fill", with: ""))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isOn ? activeColor : Palette.inkMuted)
            .scaleEffect(iconScale)
        }
        .frame(width: 22, height: 22)

        if let label {
          Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? activeColor : Palette.inkMuted)
        }

        if let count {
          Text("\(count)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(isOn ? activeColor : Palette.inkMuted)
            .contentTransition(.numericText(countsDown: !isOn))
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background {
        Capsule()
          .fill(Palette.paper)
          .overlay {
            if isOn {
              Capsule().fill(activeColor.opacity(0.14))
            }
          }
      }
      .overlay {
        Capsule()
          .strokeBorder(isOn ? activeColor.opacity(0.35) : Palette.rule.opacity(0.65), lineWidth: Radius.hairline)
      }
    }
    .buttonStyle(SquishyPillButtonStyle(pressScaleX: 1.09, pressScaleY: 0.88))
    .sensoryFeedback(.impact(flexibility: .soft), trigger: isOn)
    .accessibilityAddTraits(isOn ? [.isSelected] : [])
    .onChange(of: isOn) { _, newValue in
      animateToggle(isOn: newValue)
    }
    .onDisappear {
      animTask?.cancel()
      animTask = nil
    }
  }

  private func animateToggle(isOn: Bool) {
    animTask?.cancel()
    guard !reduceMotion else {
      iconScale = 1.0
      burstOpacity = 0
      return
    }

    if isOn {
      burstProgress = 0
      burstOpacity = 1
      iconScale = 0.72
      withAnimation(ElasticMotion.sparkleBurst) {
        iconScale = 1.24
        burstProgress = 1
      }
      animTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled else { return }
        withAnimation(ElasticMotion.squishRelease) { iconScale = 1.0 }
        withAnimation(.easeOut(duration: 0.22)) { burstOpacity = 0 }
      }
    } else {
      withAnimation(ElasticMotion.liquidClose) {
        iconScale = 1.0
        burstOpacity = 0
      }
    }
  }
}

// MARK: - 9. Pattern 9: 浮遊ゼリー・トーストピル

struct JellyToastPill: View {
  let message: String?
  var icon: String = "checkmark.circle.fill"
  var tint: Color = ElasticMotion.pillFill

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var expanded = false
  @State private var visible = false
  @State private var toastTask: Task<Void, Never>?

  var body: some View {
    Group {
      if visible, let text = message {
        HStack(spacing: 8) {
          Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.paper)
          if expanded {
            Text(text)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Palette.paper)
              .lineLimit(1)
              .transition(.opacity.combined(with: .move(edge: .leading)))
          }
        }
        .padding(.horizontal, expanded ? 16 : 10)
        .frame(height: 38)
        .background(tint, in: Capsule())
        .clipShape(Capsule())
        .shadow(color: Palette.shadow.opacity(PaperShadow.raised.opacity), radius: PaperShadow.raised.radius, y: PaperShadow.raised.y)
        .scaleEffect(expanded ? 1.0 : 0.78)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
      }
    }
    .onAppear {
      if message != nil && !visible {
        present()
      }
    }
    .onChange(of: message) { _, newValue in
      if newValue != nil {
        present()
      } else {
        dismiss()
      }
    }
    .onDisappear {
      toastTask?.cancel()
      toastTask = nil
    }
  }

  private func present() {
    toastTask?.cancel()
    expanded = false
    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : ElasticMotion.toastOpen) {
      visible = true
    }
    toastTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(70))
      guard !Task.isCancelled, message != nil else { return }
      withAnimation(reduceMotion ? .easeOut(duration: 0.15) : ElasticMotion.toastOpen) {
        expanded = true
      }
    }
  }

  private func dismiss() {
    toastTask?.cancel()
    withAnimation(ElasticMotion.toastClose) {
      expanded = false
      visible = false
    }
  }
}
