// AZDialView.swift
// AZDial の SwiftUI 再実装
// 旧 AZDial.m の PITCH=15.0、右端=最小値・左端=最大値の挙動を再現

import SwiftUI

// MARK: - AZDialView（公開コンポーネント）

struct AZDialView: View {
    @Binding var value: Int
    let min: Int
    let max: Int
    let step: Int           // ダイアルの1ステップ値
    let stepperStep: Int    // ステッパーボタンの刻み（0=非表示）

    var body: some View {
        HStack(spacing: 6) {
            if stepperStep > 0 {
                Stepper("", value: $value, in: min...max, step: stepperStep)
                    .labelsHidden()
                    .frame(width: 94)
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
    /// 目盛りの視覚ピッチ（px）—pitch と異なる値にすることで余りが毎ステップ変化する
    private let tickGap: CGFloat = 16.0

    /// ドラッグ累積スクロール量（px）。AZDialBack に直接渡す
    @State private var scrollOffset: CGFloat = 0
    @State private var dragBase: CGFloat = 0
    @GestureState private var isDragging = false

    @Environment(\.colorScheme) private var colorScheme

    /// ダークモードほど影を濃くし、ハイライトを明るくする
    private var shadowOpacity: CGFloat { colorScheme == .dark ? 0.45 : 0.25 }
    private var rimOpacity:    CGFloat { colorScheme == .dark ? 0.28 : 0.08 }

    var body: some View {
        ZStack {
            // ── AZDialBack がスクロールオフセットに応じてリアルタイムに流れる ──
            AZDialBack(offset: scrollOffset, tickGap: tickGap)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            // ── 左右フェード（端の沈み込み）──
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.50), Color.clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 28)
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.50)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 28)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))

            // ── 上端リムハイライト＋下端内側シャドウ ──
            VStack(spacing: 0) {
                // 上端：明るいリム（ダークモードで特に有効）
                LinearGradient(
                    colors: [Color.white.opacity(rimOpacity), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 5)
                Spacer()
                // 下端：内側シャドウ
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.30)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        // ── 弧形ドロップシャドウ（中央が高い接触影＝円柱が台に乗る感）──
        .overlay(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(shadowOpacity))
                .frame(height: 24)
                .blur(radius: 5)
                .padding(.horizontal, 6)
                .offset(y: 10)
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { drag in
                    let delta = drag.translation.width - dragBase
                    // scrollOffset をピクセル単位でリアルタイム更新（滑らかに流れる）
                    // 右→左ドラッグで値増加（旧実装と同方向）
                    scrollOffset -= delta
                    dragBase = drag.translation.width

                    // pitch ごとに value をスナップ
                    let targetSteps = Int(scrollOffset / pitch)
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
        // ステッパー等から value が外部変更された場合に追従
        .onChange(of: value) { _, newVal in
            if !isDragging {
                scrollOffset = offsetForValue(newVal)
            }
        }
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
        CGFloat(v - min) / CGFloat(step) * pitch
    }
}

// MARK: - AZDialBack（スクロール背景コンポーネント）
// offset が 1px 変わるたびに Canvas が再描画され、目盛りが流れる

struct AZDialBack: View {
    let offset: CGFloat
    var tickGap: CGFloat = 16.0

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - カラースキーム別パレット

    private var bgEdge: Color {
        colorScheme == .dark
            ? Color(white: 0.18)
            : Color(white: 0.58)
    }
    private var bgCenter: Color {
        colorScheme == .dark
            ? Color(white: 0.48)
            : Color(white: 0.92)
    }
    private var hEdgeOpacity: CGFloat { colorScheme == .dark ? 0.38 : 0.22 }
    private var hMidOpacity:  CGFloat { colorScheme == .dark ? 0.10 : 0.05 }

    private var tickShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.90)
            : Color.black.opacity(0.55)
    }
    private var tickBodyColor: Color {
        colorScheme == .dark
            ? Color(white: 0.72).opacity(0.85)
            : Color(white: 0.95).opacity(0.90)
    }
    private var tickHiColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.40)
            : Color.white.opacity(0.80)
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // ── ベース：上下端を暗くした小豆色（垂直方向の丸み感）──
            let bgGrad = Gradient(stops: [
                .init(color: bgEdge,   location: 0.00),
                .init(color: bgCenter, location: 0.35),
                .init(color: bgCenter, location: 0.65),
                .init(color: bgEdge,   location: 1.00),
            ])
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(bgGrad, startPoint: .zero, endPoint: CGPoint(x: 0, y: h))
            )

            // ── 水平方向の立体感：左右端を暗くし中央を明るく（固定）──
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color.black.opacity(hEdgeOpacity), location: 0.00),
                        .init(color: Color.black.opacity(hMidOpacity),  location: 0.28),
                        .init(color: .clear,                            location: 0.50),
                        .init(color: Color.black.opacity(hMidOpacity),  location: 0.72),
                        .init(color: Color.black.opacity(hEdgeOpacity), location: 1.00),
                    ]),
                    startPoint: CGPoint(x: 0, y: h / 2),
                    endPoint:   CGPoint(x: w, y: h / 2)
                )
            )

            // ── 目盛り ──
            let topY = h * 0.22
            let tickH = h * 0.56

            var x = (-offset).truncatingRemainder(dividingBy: tickGap)
            if x > 0 { x -= tickGap }

            while x < w {
                drawOneTick(ctx: ctx, x: x, topY: topY, tickH: tickH)
                x += tickGap
            }
        }
    }

    private func drawOneTick(ctx: GraphicsContext, x: CGFloat, topY: CGFloat, tickH: CGFloat) {
        let w: CGFloat = 7.0
        let r: CGFloat = w / 2

        // 影（少し右下にオフセット）
        let shadowRect = CGRect(x: x - r + 1.5, y: topY + 1.0, width: w, height: tickH)
        ctx.fill(Path(ellipseIn: shadowRect), with: .color(tickShadowColor))

        // 本体楕円（左右グラデーション）
        let bodyRect = CGRect(x: x - r, y: topY, width: w, height: tickH)
        ctx.fill(
            Path(ellipseIn: bodyRect),
            with: .linearGradient(
                Gradient(colors: [tickShadowColor, tickBodyColor, tickShadowColor]),
                startPoint: CGPoint(x: x - r, y: topY + tickH / 2),
                endPoint:   CGPoint(x: x + r, y: topY + tickH / 2)
            )
        )

        // ハイライト（左寄り）
        let hiRect = CGRect(x: x - r + 0.5, y: topY, width: w * 0.35, height: tickH)
        ctx.fill(Path(ellipseIn: hiRect), with: .color(tickHiColor))
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
