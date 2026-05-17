// RecentConflictSheet.swift
// 直近10分以内の記録との衝突解決シート

import SwiftUI
import SwiftData

// MARK: - 衝突項目の対象フィールド

enum ConflictField: String, CaseIterable {
    case bpHi, bpLo, pulse, temp, weight, bodyFat, skMuscle

    var labelKey: String {
        switch self {
        case .bpHi:     return "metric.systolic.long"
        case .bpLo:     return "metric.diastolic.long"
        case .pulse:    return "metric.heartRate"
        case .temp:     return "metric.bodyTemp"
        case .weight:   return "metric.weight"
        case .bodyFat:  return "metric.bodyFat"
        case .skMuscle: return "metric.skeletalMuscle"
        }
    }

    var unitKey: LocalizedStringKey {
        switch self {
        case .bpHi, .bpLo: return "unit.mmHg"
        case .pulse:       return "unit.bpm"
        case .temp:        return "unit.celsius"
        case .weight:      return "unit.kg"
        case .bodyFat, .skMuscle: return "%"
        }
    }

    var decimals: Int {
        switch self {
        case .bpHi, .bpLo, .pulse: return 0
        case .temp, .weight, .bodyFat, .skMuscle: return 1
        }
    }

    var color: Color {
        switch self {
        case .bpHi:     return .red
        case .bpLo:     return .blue
        case .pulse:    return .orange
        case .temp:     return .pink
        case .weight:   return .indigo
        case .bodyFat:  return .purple
        case .skMuscle: return .teal
        }
    }

    /// 非表示判定に使う GraphKind
    var graphKind: GraphKind {
        switch self {
        case .bpHi, .bpLo: return .bp
        case .pulse:       return .pulse
        case .temp:        return .temp
        case .weight:      return .weight
        case .bodyFat:     return .bodyFat
        case .skMuscle:    return .skMuscle
        }
    }
}

// MARK: - 衝突項目データ

struct ConflictItem: Identifiable {
    var id: String { field.rawValue }
    let field: ConflictField
    let prevValue: Int   // > 0 のみ
    let newValue: Int    // > 0 のみ
    var avgValue: Int { (prevValue + newValue) / 2 }
}

struct RecentConflict: Identifiable {
    let id = UUID()
    let previous: BodyRecord
    let items: [ConflictItem]
}

enum ConflictAction: Int, Hashable, CaseIterable {
    case keepBoth     = 0   // 両方残す：通常通り新規挿入
    case keepPrevious = 1   // 直前値：新しい記録を保存しない
    case useNew       = 2   // 新しい値：直前を新しい値で上書き
    case useAverage   = 3   // 平均値：直前を平均値で上書き

    var labelKey: LocalizedStringKey {
        switch self {
        case .keepBoth:     return "conflict.action.keepBoth"
        case .keepPrevious: return "conflict.action.keepPrevious"
        case .useNew:       return "conflict.action.useNew"
        case .useAverage:   return "conflict.action.useAverage"
        }
    }
}

// MARK: - シート

struct RecentConflictSheet: View {
    let conflict: RecentConflict
    let onAction: (ConflictAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: ConflictAction
    @State private var contentHeight: CGFloat = 480

    /// 値セル列の幅（文字サイズに連動して伸縮）
    @ScaledMetric(relativeTo: .body) private var colW: CGFloat = 56

    init(conflict: RecentConflict, onAction: @escaping (ConflictAction) -> Void) {
        self.conflict = conflict
        self.onAction = onAction
        let defaultRaw = AppSettings.shared.mergeDefaultAction
        _selection = State(initialValue: ConflictAction(rawValue: defaultRaw) ?? .useAverage)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Hm")
        return f
    }()

    /// 各列のハイライト状態
    private var highlightPrev:    Bool { selection == .keepPrevious || selection == .keepBoth }
    private var highlightNew:     Bool { selection == .useNew        || selection == .keepBoth }
    private var highlightAverage: Bool { selection == .useAverage }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Divider()

                // 列見出し（タップで選択切替）
                HStack(spacing: 4) {
                    Text("conflict.item")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    columnHeaderButton("conflict.previous", isOn: highlightPrev) {
                        selection = .keepPrevious
                    }
                    columnHeaderButton("conflict.new", isOn: highlightNew) {
                        selection = .useNew
                    }
                    columnHeaderButton("conflict.average", isOn: highlightAverage) {
                        selection = .useAverage
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))

                // 項目：内容に合わせて自然な高さ
                VStack(spacing: 4) {
                    ForEach(conflict.items) { item in
                        ConflictRowView(
                            item: item,
                            colW: colW,
                            highlightPrev: highlightPrev,
                            highlightNew: highlightNew,
                            highlightAverage: highlightAverage,
                            onTapPrev:    { selection = .keepPrevious },
                            onTapNew:     { selection = .useNew },
                            onTapAverage: { selection = .useAverage }
                        )
                        Divider()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)

                // セレクタ：項目の直下に配置
                // セグメント風セレクタ：列ハイライトと同じスタイル
                HStack(spacing: 6) {
                    ForEach(ConflictAction.allCases, id: \.rawValue) { action in
                        SelectorButton(
                            label: action.labelKey,
                            isOn: selection == action
                        ) {
                            selection = action
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 4)

                BeginnerHelpBanner("conflict.help", storageKey: "helpDismissed.conflict")
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                let safeArea = (UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }
                    .first?.safeAreaInsets.bottom ?? 0)
                // ナビバー44 + 内部高さ + 下部セーフエリア
                contentHeight = h + 44 + safeArea
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    // 収まる時のみタイトル表示、欠ける場合は非表示
                    ViewThatFits {
                        Text("settings.merge.window")
                            .font(.headline)
                            .lineLimit(1)
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { onAction(selection) }
                        .bold()
                }
            }
            .animation(.snappy, value: selection)
        }
        .presentationDetents([.height(contentHeight), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }

    @ViewBuilder
    private var header: some View {
        let minutes = AppSettings.shared.mergeWindowMinutes
        let msg = String(
            format: NSLocalizedString("conflict.message", comment: ""),
            minutes
        )
        VStack(spacing: 4) {
            Text(msg)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Image(systemName: conflict.previous.dateOpt.icon)
                    .foregroundStyle(.secondary)
                Text(LocalizedStringKey(conflict.previous.dateOpt.label))
                Text(Self.timeFormatter.string(from: conflict.previous.dateTime))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func columnHeaderButton(_ key: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key)
                .font(.caption.bold())
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.trailing)
                .frame(width: colW, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - セレクタボタン（列ハイライトと同じ見た目）

private struct SelectorButton: View {
    let label: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout)
                .fontWeight(isOn ? .bold : .regular)
                .foregroundStyle(isOn ? Color.accentColor : .primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isOn ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                )
                .shadow(color: isOn ? Color.accentColor.opacity(0.25) : .clear,
                        radius: isOn ? 3 : 0, y: isOn ? 1 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 衝突行

private struct ConflictRowView: View {
    let item: ConflictItem
    let colW: CGFloat
    let highlightPrev: Bool
    let highlightNew: Bool
    let highlightAverage: Bool
    let onTapPrev: () -> Void
    let onTapNew: () -> Void
    let onTapAverage: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(LocalizedStringKey(item.field.labelKey))
                .font(.callout)
                .foregroundStyle(item.field.color)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            valueButton(item.prevValue, lifted: highlightPrev, action: onTapPrev)
            valueButton(item.newValue,  lifted: highlightNew,  action: onTapNew)
            valueButton(item.avgValue,  lifted: highlightAverage, action: onTapAverage)
        }
        .font(.body.monospacedDigit())
        .padding(.vertical, 4)
    }

    private func valueButton(_ value: Int, lifted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(ValueFormatter.format(value, decimals: item.field.decimals))
                .fontWeight(lifted ? .bold : .regular)
                .foregroundStyle(lifted ? Color.accentColor : .primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: colW, alignment: .trailing)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(lifted ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .scaleEffect(lifted ? 1.08 : 1.0)
                .shadow(color: lifted ? Color.accentColor.opacity(0.25) : .clear,
                        radius: lifted ? 3 : 0, y: lifted ? 1 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
