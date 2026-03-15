// RecordListView.swift
// 記録一覧画面（旧 E2listTVC 相当）

import SwiftUI
import SwiftData

struct RecordListView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(
        filter: #Predicate<BodyRecord> { $0.dateTime < bodyRecordGoalDate },
        sort: \BodyRecord.dateTime,
        order: .reverse
    )
    private var records: [BodyRecord]

    @State private var editTarget: BodyRecord? = nil
    @State private var showAddSheet = false
    @State private var showGoalSheet = false
    @State private var toastMessage: String? = nil

    private var settings: AppSettings { AppSettings.shared }
    private var hkService: HealthKitService { HealthKitService.shared }

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
                RecordEditView(mode: .addNew) { count in
                    showImportToast(count: count)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await autoImportFromHealthKitIfNeeded() }
                }
            }
            .onAppear {
                if hkService.needsAutoImport {
                    hkService.needsAutoImport = false
                    Task { await autoImportFromHealthKitIfNeeded() }
                }
            }
            .sheet(item: $editTarget) { record in
                RecordEditView(mode: .edit(record))
            }
            .sheet(isPresented: $showGoalSheet) {
                GoalSettingsView()
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if !hkService.importProgress.isEmpty {
                        HKProgressView(message: hkService.importProgress)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if let msg = toastMessage {
                        HKToastView(message: msg)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 24)
            }
            .animation(.easeInOut(duration: 0.3), value: toastMessage)
            .animation(.easeInOut(duration: 0.3), value: hkService.importProgress)
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

    // MARK: - HealthKit 自動インポート

    private func autoImportFromHealthKitIfNeeded() async {
        guard !hkService.isImporting,
              settings.hkEnabled,
              (HKSyncDirection(rawValue: settings.hkDirection)?.canRead) == true,
              HKSyncTiming(rawValue: settings.hkTiming) == .automatic
        else { return }
        hkService.isImporting = true
        defer { hkService.isImporting = false }

        let cal = Calendar.current
        let now = Date()
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 24 * 3600)

        let hkValues = await hkService.readSamples(
            from: oneYearAgo, to: now,
            hiddenFields: Set(settings.hiddenFields)
        )
        guard !hkValues.isEmpty else { return }

        let descriptor = FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.dateTime >= oneYearAgo && $0.dateTime < now }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        func roundToMinute(_ d: Date) -> Date {
            let secs = d.timeIntervalSinceReferenceDate
            return Date(timeIntervalSinceReferenceDate: (secs / 60).rounded(.down) * 60)
        }
        let existingTimes = Set(existing.map { roundToMinute($0.dateTime) })

        var addedCount = 0
        for v in hkValues {
            guard !existingTimes.contains(roundToMinute(v.date)) else { continue }
            let record = BodyRecord(dateTime: v.date, dateOpt: settings.autoDateOpt(for: v.date))
            record.nBpHi_mmHg   = v.bpHi
            record.nBpLo_mmHg   = v.bpLo
            record.nPulse_bpm   = v.pulse
            record.nTemp_10c    = v.temp
            record.nWeight_10Kg = v.weight
            record.nPedometer   = v.steps
            record.nBodyFat_10p = v.bodyFat
            context.insert(record)
            addedCount += 1
        }
        if addedCount > 0 {
            try? context.save()
            showImportToast(count: addedCount)
        }
    }

    private func showImportToast(count: Int) {
        guard count > 0 else { return }
        toastMessage = String(format: String(localized: "HK_Toast_Imported",
                                             defaultValue: "ヘルスケアから %d 件取得しました"), count)
        Task {
            try? await Task.sleep(for: .seconds(3))
            toastMessage = nil
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

// MARK: - HK トースト

struct HKToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75), in: Capsule())
    }
}

// MARK: - HK 進捗インジケーター

struct HKProgressView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.75), in: Capsule())
    }
}

// MARK: - セクションヘッダー

struct RecordSectionHeader: View {
    let yearMonth: Int

    private var text: String {
        let year  = yearMonth / 100
        let month = yearMonth % 100
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        guard let date = Calendar.current.date(from: comps) else {
            return String(format: "%d/%02d", year, month)
        }
        let fmt = DateFormatter()
        fmt.dateFormat = DateFormatter.dateFormat(fromTemplate: "yMMMM", options: 0, locale: Locale.current)
        return fmt.string(from: date)
    }

    var body: some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
    }
}

// MARK: - 列幅定義

/// 日付列の固定幅（ヘッダーと明細で共通。title3.bold "31" + spacing + icon 36pt + trailing 4pt）
private let dateColumnWidth: CGFloat = 80

nonisolated(unsafe) private let recordColumns: [(label: LocalizedStringKey, width: CGFloat)] = [
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
    var showActivity: Bool = true
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private func colWidth(_ index: Int) -> CGFloat {
        let w = recordColumns[index].width
        return verticalSizeClass == .compact ? w * 2 : w
    }

    var body: some View {
        GeometryReader { geo in
            // 縦向き時: 体温までで画面幅をちょうど使い切るスペーシングを計算
            // measureAreaWidth = 全体幅 - 日付列(68) - trailing(4) - 縦線(1)
            let compact = verticalSizeClass == .compact
            let measureWidth = geo.size.width - dateColumnWidth - 5
            // 固定幅: 上28+下28+脈28+内縦線1+体重44+体温36=165, leading4, 5ギャップ
            let spacing: CGFloat = compact ? 4 : max(4, (measureWidth - 4 - 165) / 5)
            HStack(spacing: 0) {
                // 日時＋区分ヘッダー（明細と同じ固定幅）
                HStack(spacing: 0) {
                    Text("日時")
                        .font(.caption2)
                    Spacer()
                    Text("区分")
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .frame(width: 36, alignment: .center)
                }
                .frame(width: dateColumnWidth, alignment: .leading)
                .padding(.trailing, 4)
                Rectangle()
                    .frame(width: 1, height: 14)
                    .foregroundStyle(.separator)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        Text(recordColumns[0].label).minimumScaleFactor(0.6).lineLimit(1).frame(width: colWidth(0))
                        Text(recordColumns[1].label).minimumScaleFactor(0.6).lineLimit(1).frame(width: colWidth(1))
                        Text(recordColumns[2].label).minimumScaleFactor(0.6).lineLimit(1).frame(width: colWidth(2))
                        Rectangle().frame(width: 1, height: 14).foregroundStyle(.separator)
                        Text(recordColumns[3].label).minimumScaleFactor(0.6).lineLimit(1).frame(width: colWidth(3))
                        Text(recordColumns[4].label).minimumScaleFactor(0.6).lineLimit(1).frame(width: colWidth(4))
                        if showActivity {
                            Rectangle().frame(width: 1, height: 14).foregroundStyle(.separator)
                            Text(recordColumns[5].label).minimumScaleFactor(0.6).lineLimit(1).frame(width: colWidth(5))
                            Text(recordColumns[6].label).minimumScaleFactor(0.6).lineLimit(1).frame(width: colWidth(6))
                            Text(recordColumns[7].label).minimumScaleFactor(0.6).lineLimit(1).frame(width: colWidth(7))
                        }
                    }
                    .padding(.leading, 4)
                }
                .frame(height: 14)
            }
        }
        .frame(height: 14)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

// MARK: - 行ビュー

struct RecordRowView: View {
    let record: BodyRecord
    var showActivity: Bool = true

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
        let notes = [record.sNote1, record.sNote2].filter { !$0.isEmpty }.joined(separator: "  ")
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                // 日付＋区分
                HStack(alignment: .bottom, spacing: 2) {

                    // 左：日付・時刻
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(dayString)
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(record.bCaution ? .red : .primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Text(Self.weekdayFormatter.string(from: record.dateTime))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Text(Self.timeFormatter.string(from: record.dateTime))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // 右：アイコン＋区分ラベル
                    VStack(spacing: 1) {
                        Image(systemName: record.dateOpt.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(record.dateOpt.label)
                            .font(.system(size: 9))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 36, alignment: .center)
                }
                .frame(width: dateColumnWidth, alignment: .leading)
                .padding(.trailing, 4)

                // 最初の縦線の幅を確保（実線は overlay で描画）
                Color.clear.frame(width: 1)

                // 測定値（計測行の高さのみ）
                // h = 計測行のみ → 2・3本目縦線はメモ行に入らない
                GeometryReader { proxy in
                    let h = proxy.size.height
                    // 縦向き時: proxy.size.width = 計測エリア幅（日付列・縦線除く）
                    // 固定幅: 上28+下28+脈28+内縦線1+体重44+体温36=165, leading4, 5ギャップ
                    let compact = verticalSizeClass == .compact
                    let spacing: CGFloat = compact ? 4 : max(4, (proxy.size.width - 4 - 165) / 5)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            valueCell(record.displayBpHi,     width: recordColumns[0].width, height: h)
                            valueCell(record.displayBpLo,     width: recordColumns[1].width, height: h)
                            valueCell(record.displayPulse,    width: recordColumns[2].width, height: h)
                            Divider().padding(.vertical, 8)
                            valueCell(record.displayWeight,   width: recordColumns[3].width, height: h)
                            valueCell(record.displayTemp,     width: recordColumns[4].width, height: h)
                            if showActivity {
                                Divider().padding(.vertical, 8)
                                valueCell(record.displayPedo,     width: recordColumns[5].width, height: h)
                                valueCell(record.displayBodyFat,  width: recordColumns[6].width, height: h)
                                valueCell(record.displaySkMuscle, width: recordColumns[7].width, height: h)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            // メモ（あるときのみ）日時・区分列を避けて計測エリア側から表示
            if !notes.isEmpty {
                HStack(spacing: 0) {
                    Color.clear.frame(width: dateColumnWidth + 5)
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.leading, 4)
                }
            }
        }
        // 最初の縦線のみ VStack 全高（メモ行含む）に渡って描画
        .overlay(alignment: .leading) {
            HStack(spacing: 0) {
                Color.clear.frame(width: dateColumnWidth + 4)
                Rectangle()
                    .frame(width: 1)
                    .foregroundStyle(.separator)
                    .padding(.vertical, 8)
                Spacer()
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
