// NumpadValueText.swift
// 数値テキストをタップするとテンキーシートで直接入力できるコンポーネント

import SwiftUI

// MARK: - 公開コンポーネント

/// 値をタップするとテンキー入力シートを表示する Text ボタン
struct NumpadValueText: View {
    @Binding var value: Int
    let min: Int
    let max: Int
    let decimals: Int
    let color: Color

    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Text(ValueFormatter.format(value, decimals: decimals))
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            NumpadInputSheet(value: $value, min: min, max: max, decimals: decimals)
                .presentationDetents([.height(100)])
                .presentationDragIndicator(.hidden)
        }
    }
}

// MARK: - 入力シート（内部）

private struct NumpadInputSheet: View {
    @Binding var value: Int
    let min: Int
    let max: Int
    let decimals: Int

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var placeholder: String {
        ValueFormatter.format(value, decimals: decimals)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Cancel", defaultValue: "キャンセル")) {
                dismiss()
            }
            .buttonStyle(.bordered)
            TextField(placeholder, text: $text)
                .keyboardType(decimals > 0 ? .decimalPad : .numberPad)
                .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .focused($focused)
            Button(String(localized: "Done", defaultValue: "OK")) {
                apply()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 16)
        .onAppear { focused = true }
    }

    private func apply() {
        let parsed: Int?
        if decimals == 0 {
            parsed = Int(text)
        } else {
            parsed = Double(text).map { Int(($0 * pow(10.0, Double(decimals))).rounded()) }
        }
        guard let v = parsed, v >= min, v <= max else { return }
        value = v
    }
}
