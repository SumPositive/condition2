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

    var body: some View {
        HStack(spacing: 4) {
            // 日付
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.dateFormatter.string(from: record.dateTime))
                    .font(.title3.bold())
                    .foregroundStyle(record.bCaution ? .red : .primary)
                Text(Self.timeFormatter.string(from: record.dateTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(record.dateOpt.shortLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, alignment: .leading)

            Divider()

            // 測定値グリッド
            Grid(horizontalSpacing: 4, verticalSpacing: 0) {
                GridRow {
                    valueCell(record.displayBpHi,   label: "上")
                    valueCell(record.displayBpLo,   label: "下")
                    valueCell(record.displayPulse,  label: "脈")
                    valueCell(record.displayWeight, label: "体重")
                    valueCell(record.displayTemp,   label: "体温")
                }
                GridRow {
                    valueCell(record.displayPedo,      label: "歩")
                    valueCell(record.displayBodyFat,   label: "脂")
                    valueCell(record.displaySkMuscle,  label: "筋")
                    Color.clear.gridCellColumns(2)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func valueCell(_ value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value.isEmpty ? "-" : value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(value.isEmpty ? Color.secondary.opacity(0.4) : .primary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 30)
    }
}
