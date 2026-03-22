// AZDialView.swift
// AZDial の SwiftUI 再実装
// 旧 AZDial.m の PITCH=15.0、右端=最小値・左端=最大値の挙動を再現

import SwiftUI

// MARK: - ダイアルスタイル

enum DialStyle: Int, CaseIterable {
    case soft = 0
    case machined = 1
    case chrome = 2
    case fine = 3
    case hairline = 4

    var label: String {
        switch self {
        case .soft:     return String(localized: "DialStyle_Soft",     defaultValue: "ソフト")
        case .machined: return String(localized: "DialStyle_Machined", defaultValue: "マシン")
        case .chrome:   return String(localized: "DialStyle_Chrome",   defaultValue: "クローム")
        case .fine:     return String(localized: "DialStyle_Fine",     defaultValue: "ファイン")
        case .hairline: return String(localized: "DialStyle_Hairline", defaultValue: "ヘアライン")
        }
    }
}

// MARK: - AZDialView（公開コンポーネント）

struct AZDialView: View {
    @Binding var value: Int
    let min: Int
    let max: Int
    let step: Int           // ダイアルの1ステップ値
    let stepperStep: Int    // ステッパーボタンの刻み（0=非表示）
    var decimals: Int = 0   // 表示小数点桁数（ステップラベルのフォーマットに使用）

    private var stepLabelText: String {
        if decimals == 0 {
            return "±\(stepperStep)"
        } else {
            let val = Double(stepperStep) / pow(10.0, Double(decimals))
            return "±\(String(format: "%.\(decimals)f", val))"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if stepperStep > 0 {
                Stepper("", value: $value, in: min...max, step: stepperStep)
                    .labelsHidden()
                    .frame(width: 94)
                    .overlay(alignment: .bottom) {
                        Text(stepLabelText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .offset(y: 14)
                            .allowsHitTesting(false)
                    }
            }
            AZDialScrollArea(value: $value, min: min, max: max, step: step)
        }
        .frame(height: 44)
    }
}

// MARK: - スクロール領域

private struct AZDialScrollArea: View {
    @Binding var value: Int
    let min: Int
    let max: Int
    let step: Int

    /// 1ステップあたりのドラッグ感度（px）
    private let pitch: CGFloat = 15.0
    /// 目盛りの視覚ピッチ（px）
    private let tickGap: CGFloat = 10.0

    /// ドラッグ累積スクロール量（px）。AZDialBack に直接渡す
    @State private var scrollOffset: CGFloat = 0
    @State private var dragBase: CGFloat = 0
    @GestureState private var isDragging = false

    @Environment(\.colorScheme) private var colorScheme

    private var shadowOpacity: CGFloat { colorScheme == .dark ? 0.55 : 0.30 }
    private var rimBright:     CGFloat { colorScheme == .dark ? 0.55 : 0.50 }
    private var rimSoft:       CGFloat { colorScheme == .dark ? 0.18 : 0.12 }

    var body: some View {
        let currentStyle = DialStyle(rawValue: AppSettings.shared.dialStyle) ?? .machined
        ZStack {
            // ── スクロールする目盛り背景 ──
            AZDialBack(offset: scrollOffset, tickGap: tickGap, style: currentStyle)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // ── 左右エッジフェード（深い沈み込み）──
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.72), Color.clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 44)
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.72)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 44)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // ── 上下の内側シャドウ＋リムライン ──
            VStack(spacing: 0) {
                // 上端：鋭いスペキュラーライン＋フェード
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(rimBright), location: 0.00),
                        .init(color: Color.white.opacity(rimSoft),   location: 0.20),
                        .init(color: .clear,                          location: 1.00),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 9)
                Spacer()
                // 下端：内側シャドウ
                LinearGradient(
                    stops: [
                        .init(color: .clear,                          location: 0.00),
                        .init(color: Color.black.opacity(0.20),       location: 0.50),
                        .init(color: Color.black.opacity(0.48),       location: 1.00),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        // ── 楕円ドロップシャドウ（円柱が台に接触する影）──
        .overlay(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(shadowOpacity))
                .frame(height: 18)
                .blur(radius: 8)
                .padding(.horizontal, 2)
                .offset(y: 10)
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { drag in
                    // ドラッグ開始フレーム: value と同期してから delta 計算
                    if dragBase == 0 {
                        scrollOffset = offsetForValue(value)
                        dragBase = drag.translation.width
                    }
                    let delta = drag.translation.width - dragBase
                    // scrollOffset をピクセル単位でリアルタイム更新（滑らかに流れる）
                    scrollOffset -= delta
                    dragBase = drag.translation.width

                    // pitch ごとに value をスナップ（符号反転で右ドラッグ＝増加）
                    let targetSteps = Int(-scrollOffset / pitch)
                    let newValue = Swift.max(min, Swift.min(max, min + targetSteps * step))
                    if newValue != value {
                        value = newValue
                        HapticsHelper.selection()
                    }
                }
                .onEnded { _ in
                    dragBase = 0
                    // ドラッグ終了時に value の位置へスナップ
                    scrollOffset = offsetForValue(value)
                }
        )
        .onAppear {
            scrollOffset = offsetForValue(value)
        }
        .frame(height: 44)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = Swift.min(max, value + step)
                HapticsHelper.selection()
            case .decrement:
                value = Swift.max(min, value - step)
                HapticsHelper.selection()
            @unknown default: break
            }
        }
    }

    /// value → スクロールオフセット（px）変換
    private func offsetForValue(_ v: Int) -> CGFloat {
        -CGFloat(v - min) / CGFloat(step) * pitch
    }
}

// MARK: - AZDialBack（スクロール背景コンポーネント）
// offset が 1px 変わるたびに Canvas が再描画され、目盛りが流れる

struct AZDialBack: View {
    let offset: CGFloat
    var tickGap: CGFloat = 16.0
    var style: DialStyle = .machined

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - カラースキーム×スタイル別パレット

    // 溝（背景）
    private var groove: Color {
        switch style {
        case .soft:
            return colorScheme == .dark ? Color(white: 0.20) : Color(white: 0.62)
        case .machined:
            return colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.52)
        case .chrome:
            return colorScheme == .dark ? Color(white: 0.03) : Color(white: 0.42)
        case .fine:
            return colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.52)
        case .hairline:
            return colorScheme == .dark ? Color(white: 0.02) : Color(white: 0.38)
        }
    }
    // リッジ側面（暗い）
    private var ridgeDark: Color {
        switch style {
        case .soft:
            return colorScheme == .dark ? Color(white: 0.32) : Color(white: 0.70)
        case .machined:
            return colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.62)
        case .chrome:
            return colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.52)
        case .fine:
            return colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.62)
        case .hairline:
            return colorScheme == .dark ? Color(white: 0.30) : Color(white: 0.65)
        }
    }
    // リッジ正面中央（凸面の最明部）
    private var ridgeBright: Color {
        switch style {
        case .soft:
            return colorScheme == .dark ? Color(white: 0.62) : Color(white: 0.84)
        case .machined:
            return colorScheme == .dark ? Color(white: 0.52) : Color(white: 0.80)
        case .chrome:
            return colorScheme == .dark
                ? Color(red: 0.84, green: 0.87, blue: 0.92)
                : Color(red: 0.90, green: 0.93, blue: 0.97)
        case .fine:
            return colorScheme == .dark ? Color(white: 0.52) : Color(white: 0.80)
        case .hairline:
            return colorScheme == .dark ? Color(white: 0.78) : Color(white: 0.95)
        }
    }
    // リッジ頂面エッジ（鋭いハイライト線）
    private var ridgeEdge: Color {
        switch style {
        case .soft:
            return colorScheme == .dark ? Color(white: 0.72) : Color(white: 0.92)
        case .machined:
            return colorScheme == .dark ? Color(white: 0.80) : Color.white
        case .chrome:
            return Color.white
        case .fine:
            return colorScheme == .dark ? Color(white: 0.80) : Color.white
        case .hairline:
            return Color.white
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // ── 溝色で全面塗り（溝＝背景）──
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(groove))

            // ── リッジ ──
            let topY:  CGFloat = 0
            let tickH: CGFloat = h

            var x = (-offset).truncatingRemainder(dividingBy: tickGap)
            if x > 0 { x -= tickGap }

            while x < w {
                drawOneRidge(ctx: ctx, x: x, topY: topY, h: tickH)
                x += tickGap
            }
        }
    }

    /// スタイル別リッジ描画
    private func drawOneRidge(ctx: GraphicsContext, x: CGFloat, topY: CGFloat, h: CGFloat) {
        switch style {

        case .soft:
            // 幅広・ソフトグラデーション（ハイライト線なし）
            let rw = tickGap * 0.58
            let rx = x - rw / 2
            ctx.fill(
                Path(CGRect(x: rx, y: topY, width: rw, height: h)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: ridgeDark,   location: 0.00),
                        .init(color: ridgeBright, location: 0.50),
                        .init(color: ridgeDark,   location: 1.00),
                    ]),
                    startPoint: CGPoint(x: rx,      y: topY + h / 2),
                    endPoint:   CGPoint(x: rx + rw, y: topY + h / 2)
                )
            )

        case .machined:
            // 機械加工されたナーリングリッジ（矩形＋横グラデ＋頂面ハイライト）
            let rw = tickGap * 0.46
            let rx = x - rw / 2
            let ridgeRect = CGRect(x: rx, y: topY, width: rw, height: h)
            ctx.fill(
                Path(ridgeRect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: ridgeDark,   location: 0.00),
                        .init(color: ridgeBright, location: 0.50),
                        .init(color: ridgeDark,   location: 1.00),
                    ]),
                    startPoint: CGPoint(x: rx,      y: topY + h / 2),
                    endPoint:   CGPoint(x: rx + rw, y: topY + h / 2)
                )
            )
            // 頂面ハイライト線
            ctx.fill(
                Path(CGRect(x: rx + rw * 0.15, y: topY, width: rw * 0.70, height: 1.2)),
                with: .color(ridgeEdge)
            )

        case .chrome:
            // ポリッシュクローム（高コントラスト、鋭いエッジ＋中央スペキュラー）
            let rw = tickGap * 0.42
            let rx = x - rw / 2
            ctx.fill(
                Path(CGRect(x: rx, y: topY, width: rw, height: h)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: ridgeDark,   location: 0.00),
                        .init(color: ridgeBright, location: 0.40),
                        .init(color: Color.white, location: 0.50),
                        .init(color: ridgeBright, location: 0.60),
                        .init(color: ridgeDark,   location: 1.00),
                    ]),
                    startPoint: CGPoint(x: rx,      y: topY + h / 2),
                    endPoint:   CGPoint(x: rx + rw, y: topY + h / 2)
                )
            )
            // 頂面ハイライト線（幅広、鮮明）
            ctx.fill(
                Path(CGRect(x: rx + rw * 0.10, y: topY, width: rw * 0.80, height: 1.5)),
                with: .color(ridgeEdge)
            )

        case .fine:
            // 細めの精密リッジ（マシンと同系・幅0.28）
            let rw = tickGap * 0.28
            let rx = x - rw / 2
            ctx.fill(
                Path(CGRect(x: rx, y: topY, width: rw, height: h)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: ridgeDark,   location: 0.00),
                        .init(color: ridgeBright, location: 0.50),
                        .init(color: ridgeDark,   location: 1.00),
                    ]),
                    startPoint: CGPoint(x: rx,      y: topY + h / 2),
                    endPoint:   CGPoint(x: rx + rw, y: topY + h / 2)
                )
            )
            // 頂面ハイライト線
            ctx.fill(
                Path(CGRect(x: rx + rw * 0.15, y: topY, width: rw * 0.70, height: 1.0)),
                with: .color(ridgeEdge)
            )

        case .hairline:
            // 極細ヘアライン（幅0.16・グラデーションなし単色）
            let rw = tickGap * 0.16
            let rx = x - rw / 2
            ctx.fill(
                Path(CGRect(x: rx, y: topY, width: rw, height: h)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: ridgeDark,   location: 0.00),
                        .init(color: ridgeBright, location: 0.50),
                        .init(color: ridgeDark,   location: 1.00),
                    ]),
                    startPoint: CGPoint(x: rx,      y: topY + h / 2),
                    endPoint:   CGPoint(x: rx + rw, y: topY + h / 2)
                )
            )
        }
    }
}

// MARK: - ハプティクスヘルパー

enum HapticsHelper {
    @MainActor
    static func selection() {
        let gen = UISelectionFeedbackGenerator()
        gen.selectionChanged()
    }
}

// MARK: - プレビュー

#Preview {
    @Previewable @State var value = 120
    VStack(spacing: 20) {
        Text("値: \(value)")
        AZDialView(value: $value, min: 30, max: 300, step: 1, stepperStep: 10)
            .padding(.horizontal)
        AZDialView(value: $value, min: 30, max: 300, step: 1, stepperStep: 0)
            .padding(.horizontal)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
