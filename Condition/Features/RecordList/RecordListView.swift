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
    var body: some View {
        HStack(spacing: 4) {
            Text("日時")
                .frame(width: 44, alignment: .leading)
            Rectangle()
                .frame(width: 1, height: 14)
                .foregroundStyle(.separator)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Text(recordColumns[0].label).frame(width: recordColumns[0].width)
                    Text(recordColumns[1].label).frame(width: recordColumns[1].width)
                    Text(recordColumns[2].label).frame(width: recordColumns[2].width)
                    Rectangle().frame(width: 1, height: 14).foregroundStyle(.separator)
                    Text(recordColumns[3].label).frame(width: recordColumns[3].width)
                    Text(recordColumns[4].label).frame(width: recordColumns[4].width)
                    Rectangle().frame(width: 1, height: 14).foregroundStyle(.separator)
                    Text(recordColumns[5].label).frame(width: recordColumns[5].width)
                    Text(recordColumns[6].label).frame(width: recordColumns[6].width)
                    Text(recordColumns[7].label).frame(width: recordColumns[7].width)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

// MARK: - 行ビュー

struct RecordRowView: View {
    let record: BodyRecord

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

    var body: some View {
        HStack(spacing: 4) {
            // 日付
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Self.dateFormatter.string(from: record.dateTime))
                        .font(.title3.bold())
                        .foregroundStyle(record.bCaution ? .red : .primary)
                    Text(Self.weekdayFormatter.string(from: record.dateTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(Self.timeFormatter.string(from: record.dateTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(record.dateOpt.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, alignment: .leading)

            Divider()

            // 測定値（1行・横スクロール対応）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    valueCell(record.displayBpHi,     width: recordColumns[0].width)
                    valueCell(record.displayBpLo,     width: recordColumns[1].width)
                    valueCell(record.displayPulse,    width: recordColumns[2].width)
                    Divider()
                    valueCell(record.displayWeight,   width: recordColumns[3].width)
                    valueCell(record.displayTemp,     width: recordColumns[4].width)
                    Divider()
                    valueCell(record.displayPedo,     width: recordColumns[5].width)
                    valueCell(record.displayBodyFat,  width: recordColumns[6].width)
                    valueCell(record.displaySkMuscle, width: recordColumns[7].width)
                }
            }
        }
        .font(.caption)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func valueCell(_ value: String, width: CGFloat) -> some View {
        Text(value.isEmpty ? "-" : value)
            .font(.caption.monospacedDigit())
            .foregroundStyle(value.isEmpty ? Color.secondary.opacity(0.4) : .primary)
            .fixedSize(horizontal: true, vertical: false)
            .scaleEffect(x: 1.0, y: 2.0, anchor: .center)
            .frame(width: width, height: 32)
    }
}
