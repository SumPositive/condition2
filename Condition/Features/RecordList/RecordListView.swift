// RecordListView.swift
// 記録一覧画面（旧 E2listTVC 相当）

import SwiftUI
import SwiftData

struct RecordListView: View {

    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<BodyRecord> { $0.dateTime < bodyRecordGoalDate },
        sort: \BodyRecord.dateTime,
        order: .reverse
    )
    private var records: [BodyRecord]

    @State private var editTarget: BodyRecord? = nil
    @State private var showAddSheet = false
    @State private var showGoalSheet = false

    private var settings: AppSettings { AppSettings.shared }

    // MARK: - セクション分割（年月ごと）
    private var sections: [(yearMonth: Int, records: [BodyRecord])] {
        var dict: [Int: [BodyRecord]] = [:]
        for r in records {
            dict[r.yearMonth, default: []].append(r)
        }
        return dict
            .sorted { $0.key > $1.key }
            .map { (yearMonth: $0.key, records: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        String(localized: "List_Empty", defaultValue: "記録がありません"),
                        systemImage: "heart.text.square",
                        description: Text(String(localized: "List_Empty_Hint", defaultValue: "+ ボタンで記録を追加してください"))
                    )
                } else {
                    listContent
                }
            }
            .navigationTitle(String(localized: "Tab_List", defaultValue: "記録"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
                if settings.goalEnabled {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(String(localized: "Goal", defaultValue: "目標")) {
                            showGoalSheet = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                RecordEditView(mode: .addNew)
            }
            .sheet(item: $editTarget) { record in
                RecordEditView(mode: .edit(record))
            }
            .sheet(isPresented: $showGoalSheet) {
                GoalSettingsView()
            }
        }
    }

    // MARK: - リスト

    private var listContent: some View {
        VStack(spacing: 0) {
            RecordColumnHeader()
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .background(.bar)
            Divider()
            List {
                ForEach(sections, id: \.yearMonth) { section in
                    Section(header: RecordSectionHeader(yearMonth: section.yearMonth)) {
                        ForEach(section.records) { record in
                            RecordRowView(record: record)
                                .contentShape(Rectangle())
                                .onTapGesture { editTarget = record }
                                .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                        }
                        .onDelete { offsets in
                            deleteRecords(in: section.records, offsets: offsets)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - 削除

    private func deleteRecords(in sectionRecords: [BodyRecord], offsets: IndexSet) {
        for index in offsets {
            let record = sectionRecords[index]
            // カレンダーイベントも削除
            if !record.sEventID.isEmpty {
                CalendarService.shared.deleteEvent(eventID: record.sEventID)
            }
            context.delete(record)
        }
    }
}

// MARK: - セクションヘッダー

struct RecordSectionHeader: View {
    let yearMonth: Int

    private var text: String {
        let year  = yearMonth / 100
        let month = yearMonth % 100
        return String(format: "%d年%d月", year, month)
    }

    var body: some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
    }
}

// MARK: - 列幅定義

/// 日付列の固定幅（ヘッダーと明細で共通。title3.bold "31" + spacing + icon 24pt + trailing 4pt）
private let dateColumnWidth: CGFloat = 64

private let recordColumns: [(label: String, width: CGFloat)] = [
    ("上",   28),
    ("下",   28),
    ("脈拍", 28),
    ("体重", 44),
    ("体温", 36),
    ("歩数", 36),
    ("体脂肪", 36),
    ("骨格筋", 36),
]

// MARK: - カラムヘッダー

struct RecordColumnHeader: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private func colWidth(_ index: Int) -> CGFloat {
        let w = recordColumns[index].width
        return verticalSizeClass == .compact ? w * 2 : w
    }

    var body: some View {
        HStack(spacing: 0) {
            // 日時＋区分ヘッダー（明細と同じ固定幅）
            HStack(spacing: 2) {
                Text("日時")
                    .fixedSize()
                Text("区分")
                    .frame(width: 24, alignment: .center)
            }
            .frame(width: dateColumnWidth, alignment: .leading)
            .padding(.trailing, 4)
            Rectangle()
                .frame(width: 1, height: 14)
                .foregroundStyle(.separator)
            // 明細と同じ動的スペーシング
            GeometryReader { proxy in
                let compact = verticalSizeClass == .compact
                let cellTotal = recordColumns.reduce(0.0) { $0 + $1.width } * (compact ? 2.0 : 1.0)
                let spacing = max(-4, (proxy.size.width - 4 - cellTotal - 2) / 9)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        Text(recordColumns[0].label).frame(width: colWidth(0))
                        Text(recordColumns[1].label).frame(width: colWidth(1))
                        Text(recordColumns[2].label).frame(width: colWidth(2))
                        Rectangle().frame(width: 1, height: 14).foregroundStyle(.separator)
                        Text(recordColumns[3].label).frame(width: colWidth(3))
                        Text(recordColumns[4].label).frame(width: colWidth(4))
                        Rectangle().frame(width: 1, height: 14).foregroundStyle(.separator)
                        Text(recordColumns[5].label).frame(width: colWidth(5))
                        Text(recordColumns[6].label).frame(width: colWidth(6))
                        Text(recordColumns[7].label).frame(width: colWidth(7))
                    }
                    .padding(.leading, 4)
                }
            }
            .frame(height: 14)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

// MARK: - 行ビュー

struct RecordRowView: View {
    let record: BodyRecord

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "E"
        return f
    }()

    private var dayString: String {
        let s = Self.dateFormatter.string(from: record.dateTime)
        return s.count == 1 ? "\u{2007}\(s)" : s
    }

    var body: some View {
        HStack(spacing: 0) {
            // 日付＋区分
            HStack(alignment: .bottom, spacing: 2) {
                // 左：日付・時刻
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(dayString)
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(record.bCaution ? .red : .primary)
                        Text(Self.weekdayFormatter.string(from: record.dateTime))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(Self.timeFormatter.string(from: record.dateTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // 右：アイコン＋区分ラベル（ラベルを時刻行と揃える）
                VStack(spacing: 1) {
                    Image(systemName: record.dateOpt.icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(record.dateOpt.label)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 24, alignment: .center)
            }
            .frame(width: dateColumnWidth, alignment: .leading)
            .padding(.trailing, 4)

            Divider()
                .padding(.vertical, 8)

            // 測定値（行全体の高さを使い、縦線を外側と揃える）
            GeometryReader { proxy in
                let h = proxy.size.height
                let compact = verticalSizeClass == .compact
                let cellTotal = recordColumns.reduce(0.0) { $0 + $1.width } * (compact ? 2.0 : 1.0)
                let spacing = max(-4, (proxy.size.width - 4 - cellTotal - 2) / 9)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        valueCell(record.displayBpHi,     width: recordColumns[0].width, height: h)
                        valueCell(record.displayBpLo,     width: recordColumns[1].width, height: h)
                        valueCell(record.displayPulse,    width: recordColumns[2].width, height: h)
                        Divider().padding(.vertical, 8)
                        valueCell(record.displayWeight,   width: recordColumns[3].width, height: h)
                        valueCell(record.displayTemp,     width: recordColumns[4].width, height: h)
                        Divider().padding(.vertical, 8)
                        valueCell(record.displayPedo,     width: recordColumns[5].width, height: h)
                        valueCell(record.displayBodyFat,  width: recordColumns[6].width, height: h)
                        valueCell(record.displaySkMuscle, width: recordColumns[7].width, height: h)
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .font(.caption)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func valueCell(_ value: String, width: CGFloat, height: CGFloat = 32) -> some View {
        Text(value.isEmpty ? "-" : value)
            .font(.caption.monospacedDigit())
            .foregroundStyle(value.isEmpty ? Color.secondary.opacity(0.4) : .primary)
            .fixedSize(horizontal: true, vertical: false)
            .scaleEffect(x: verticalSizeClass == .compact ? 2.0 : 1.0, y: 2.0, anchor: .center)
            .frame(width: verticalSizeClass == .compact ? width * 2 : width, height: height)
    }
}
