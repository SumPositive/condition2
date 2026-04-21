// RecordListView.swift
// 記録一覧画面（旧 E2listTVC 相当）

import SwiftUI
import SwiftData
import UIKit

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
    @State private var showExportSheet = false

    @State private var toastMessage: String? = nil
    @State private var showHKTimeoutAlert = false

    private var settings: AppSettings { AppSettings.shared }
    private var hkService: HealthKitService { HealthKitService.shared }

    // MARK: - 可視フィールドにデータがあるレコードのみ抽出
    private var visibleRecords: [BodyRecord] {
        let kinds = visibleRecordKinds
        guard !kinds.isEmpty else { return records }
        return records.filter { r in
            kinds.contains { kind in
                switch kind {
                case .bp:       return r.nBpHi_mmHg > 0 || r.nBpLo_mmHg > 0
                case .pulse:    return r.nPulse_bpm > 0
                case .temp:     return r.nTemp_10c > 0
                case .weight:   return r.nWeight_10Kg > 0
                case .bodyFat:  return r.nBodyFat_10p > 0
                case .skMuscle: return r.nSkMuscle_10p > 0
                default:        return false
                }
            }
        }
    }

    // MARK: - セクション分割（年月ごと）
    private var sections: [(yearMonth: Int, records: [BodyRecord])] {
        var dict: [Int: [BodyRecord]] = [:]
        for r in visibleRecords {
            dict[r.yearMonth, default: []].append(r)
        }
        return dict
            .sorted { $0.key > $1.key }
            .map { (yearMonth: $0.key, records: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleRecords.isEmpty {
                    ContentUnavailableView(
                        "records.empty.title",
                        systemImage: "heart.text.square",
                        description: Text("records.empty.message")
                    )
                } else {
                    listContent
                }
            }
            .navigationTitle("tab.records")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showExportSheet = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(records.isEmpty)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    #if targetEnvironment(simulator)
                    if !settings.hkDisabledByDemo {
                        Button {
                            AppSettings.shared.hkDisabledByDemo = true
                            AppSettings.shared.hkEnabled = false
                            DemoDataGenerator.generate(in: context)
                            toastMessage = String(localized: "demo.addedOneYear")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                toastMessage = nil
                            }
                        } label: {
                            Text("action.demo")
                        }
                        .tint(.orange)
                    }
                    #endif // targetEnvironment(simulator)
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
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
            .sheet(isPresented: $showExportSheet) {
                ExportSheetView(records: records, visibleKinds: visibleRecordKinds)
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
            .onChange(of: hkService.importTimedOut) { _, timedOut in
                if timedOut { showHKTimeoutAlert = true }
            }
            .alert(
                "health.error.title",
                isPresented: $showHKTimeoutAlert
            ) {
                Button("action.ok") { hkService.importTimedOut = false }
            } message: {
                Text("health.pleaseCheckThatHealthIsFunctioning")
            }
        }
    }

    // MARK: - リスト

    private var visibleRecordKinds: [GraphKind] {
        let hidden = Set(settings.hiddenFields)
        return settings.graphPanelOrder
            .compactMap { GraphKind(rawValue: $0) }
            .filter { $0.isRecordField && !hidden.contains($0.rawValue) }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            RecordColumnHeader(visibleKinds: visibleRecordKinds)
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .background(.bar)
            Divider()
            List {
                ForEach(sections, id: \.yearMonth) { section in
                    Section(header: RecordSectionHeader(yearMonth: section.yearMonth)) {
                        ForEach(section.records) { record in
                            RecordRowView(record: record, visibleKinds: visibleRecordKinds, hkEnabled: settings.hkEnabled)
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
            record.dataSource   = .hkImport
            record.nBpHi_mmHg   = v.bpHi
            record.nBpLo_mmHg   = v.bpLo
            record.nPulse_bpm   = v.pulse
            record.nTemp_10c    = v.temp
            record.nWeight_10Kg = v.weight
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
        toastMessage = String(format: String(localized: "health.importedCount"), count)
        Task {
            try? await Task.sleep(for: .seconds(3))
            toastMessage = nil
        }
    }

    // MARK: - 削除

    private func deleteRecords(in sectionRecords: [BodyRecord], offsets: IndexSet) {
        for index in offsets {
            let record = sectionRecords[index]
            context.delete(record)
        }
    }
}

// MARK: - HK トースト

struct HKToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
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
                .font(.callout.weight(.medium))
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
            .font(.footnote.bold())
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(Color(UIColor.systemBackground).padding(.top, -20))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - DEBUGサンプルデータ生成

#if DEBUG
private struct DemoDataGenerator {

    private struct Profile {
        let bpHiBase: Int; let bpHiRange: Int
        let bpLoBase: Int; let bpLoRange: Int
        let pulseBase: Int; let pulseRange: Int
        let weightBase: Int; let weightRange: Int
        let tempBase: Int; let tempRange: Int
        let bodyFatBase: Int; let bodyFatRange: Int
        let skMuscleBase: Int; let skMuscleRange: Int
    }

    private static let jaProfile = Profile(
        bpHiBase: 123, bpHiRange: 18,
        bpLoBase: 76,  bpLoRange: 12,
        pulseBase: 70, pulseRange: 14,
        weightBase: 680, weightRange: 60,
        tempBase: 364,   tempRange: 8,
        bodyFatBase: 220, bodyFatRange: 50,
        skMuscleBase: 340, skMuscleRange: 40
    )

    private static let enProfile = Profile(
        bpHiBase: 128, bpHiRange: 20,
        bpLoBase: 80,  bpLoRange: 12,
        pulseBase: 72, pulseRange: 16,
        weightBase: 900, weightRange: 80,
        tempBase: 366,   tempRange: 8,
        bodyFatBase: 265, bodyFatRange: 60,
        skMuscleBase: 305, skMuscleRange: 40
    )

    static func generate(in context: ModelContext) {
        try? context.delete(model: BodyRecord.self)

        let isJa = Locale.preferredLanguages.first?.hasPrefix("ja") ?? true
        let profile = isJa ? jaProfile : enProfile
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var rng = SystemRandomNumberGenerator()

        func rand(_ base: Int, _ range: Int, step: Int = 1) -> Int {
            let v = base + Int.random(in: 0...range, using: &rng) - range / 2
            return (v / step) * step
        }

        for dayOffset in 0..<365 {
            guard let day = cal.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let recordCount = Int.random(in: 0...9, using: &rng) < 3 ? 2 : 1

            for i in 0..<recordCount {
                let dateOpt: DateOpt
                let hour: Int
                if i == 0 {
                    let opts: [(DateOpt, Int)] = [(.wake, 7), (.rest, 20), (.down, 22)]
                    let picked = opts[Int.random(in: 0..<opts.count, using: &rng)]
                    dateOpt = picked.0; hour = picked.1
                } else {
                    dateOpt = .rest; hour = Int.random(in: 12...15, using: &rng)
                }
                let minute = Int.random(in: 0...59, using: &rng)
                guard let dt = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }

                let record = BodyRecord(dateTime: dt, dateOpt: dateOpt)
                record.nDataSource   = RecordDataSource.appInput.rawValue
                let hi = max(90,  rand(profile.bpHiBase, profile.bpHiRange, step: 2))
                let lo = max(55,  rand(profile.bpLoBase, profile.bpLoRange, step: 2))
                record.nBpHi_mmHg    = hi
                record.nBpLo_mmHg    = min(lo, hi - 20)
                record.nPulse_bpm    = max(50, rand(profile.pulseBase,    profile.pulseRange))
                record.nWeight_10Kg  = max(300, rand(profile.weightBase,  profile.weightRange, step: 5))
                record.nTemp_10c     = max(355, rand(profile.tempBase,    profile.tempRange))
                record.nBodyFat_10p  = max(100, rand(profile.bodyFatBase, profile.bodyFatRange, step: 5))
                record.nSkMuscle_10p = max(150, rand(profile.skMuscleBase,profile.skMuscleRange, step: 5))
                record.bCaution = record.nBpHi_mmHg >= 140 || record.nBpLo_mmHg >= 90
                context.insert(record)
            }
        }
        try? context.save()
    }
}
#endif

// MARK: - 列幅定義

/// 日付列の固定幅（ヘッダーと明細で共通。title2.bold "31" + spacing + icon 44pt + trailing 4pt）
private let dateColumnWidth: CGFloat = 110

private func subColumnWidths(for kind: GraphKind) -> [CGFloat] {
    switch kind {
    case .bp:       return [42, 42]
    case .pulse:    return [42]
    case .weight:   return [60]
    case .temp:     return [52]
    case .bodyFat:  return [52]
    case .skMuscle: return [52]
    default:        return []
    }
}

private func computeColumnSpacing(availableWidth: CGFloat, kinds: [GraphKind]) -> CGFloat {
    return 4
}

// MARK: - カラムヘッダー

struct RecordColumnHeader: View {
    let visibleKinds: [GraphKind]

    var body: some View {
        GeometryReader { geo in
            let measureWidth = geo.size.width - dateColumnWidth - 5
            let spacing = computeColumnSpacing(availableWidth: measureWidth, kinds: visibleKinds)
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("record.datetime")
                        .font(.caption)
                    Spacer()
                    Text("record.category")
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .frame(width: 40, alignment: .center)
                }
                .frame(width: dateColumnWidth, alignment: .leading)
                .padding(.trailing, 4)
                Rectangle()
                    .frame(width: 1, height: 16)
                    .foregroundStyle(.separator)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(Array(visibleKinds.enumerated()), id: \.element.id) { idx, kind in
                            kindHeaderItems(kind, isFirst: idx == 0)
                        }
                    }
                    .padding(.leading, 4)
                }
                .frame(height: 16)
            }
        }
        .frame(height: 16)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func kindHeaderItems(_ kind: GraphKind, isFirst: Bool) -> some View {
        if !isFirst {
            Rectangle().frame(width: 1, height: 16).foregroundStyle(.separator)
        }
        kindHeaderCells(kind)
    }

    @ViewBuilder
    private func kindHeaderCells(_ kind: GraphKind) -> some View {
        switch kind {
        case .bp:
            Text("metric.systolic.short").minimumScaleFactor(0.6).lineLimit(1).frame(width: 42)
            Text("metric.diastolic.short").minimumScaleFactor(0.6).lineLimit(1).frame(width: 42)
        case .pulse:
            Text("metric.heartRate").minimumScaleFactor(0.6).lineLimit(1).frame(width: 42)
        case .weight:
            Text("metric.weight").minimumScaleFactor(0.6).lineLimit(1).frame(width: 60)
        case .temp:
            Text("metric.bodyTemp").minimumScaleFactor(0.6).lineLimit(1).frame(width: 52)
        case .bodyFat:
            Text("metric.bodyFat.short").minimumScaleFactor(0.6).lineLimit(1).frame(width: 52)
        case .skMuscle:
            Text("metric.skeletalMuscle.short").minimumScaleFactor(0.6).lineLimit(1).frame(width: 52)
        default:
            EmptyView()
        }
    }
}

// MARK: - 行ビュー

struct RecordRowView: View {
    let record: BodyRecord
    let visibleKinds: [GraphKind]
    var hkEnabled: Bool = false

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
        f.locale = Locale.current
        f.dateFormat = "E"
        return f
    }()

    private var dayString: String {
        let s = Self.dateFormatter.string(from: record.dateTime)
        return s.count == 1 ? "\u{2007}\(s)" : s
    }

    var body: some View {
        let notes = [record.sNote1, record.sNote2].filter { !$0.isEmpty }.joined(separator: "  ")
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // 日付＋区分
                HStack(alignment: .center, spacing: 2) {
                    // 左：日付・時刻
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(dayString)
                                .font(.title2.bold().monospacedDigit())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Text(Self.weekdayFormatter.string(from: record.dateTime))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Text(Self.timeFormatter.string(from: record.dateTime))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Color.clear.frame(height: 6)
                    }
                    // 中：フラグ・データソース（center揃えで自動縦中央）
                    VStack(spacing: 1) {
                        if record.bCaution {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)
                        }
                        if hkEnabled {
                            Image(systemName: record.dataSource.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(record.dataSource.color)
                        }
                    }
                    .padding(.leading, 2)
                    // 右：区分アイコン
                    Image(systemName: record.dateOpt.icon)
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .center)
                }
                .frame(width: dateColumnWidth, alignment: .leading)
                .padding(.trailing, 4)

                // 最初の縦線の幅を確保（実線は overlay で描画）
                Color.clear.frame(width: 1)

                // 測定値＋メモ（メモは数値列と一緒にスクロール）
                GeometryReader { proxy in
                    let memoSpace: CGFloat = 6
                    let h = proxy.size.height
                    let spacing = computeColumnSpacing(availableWidth: proxy.size.width, kinds: visibleKinds)
                    let cellH = h - memoSpace
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: spacing) {
                                ForEach(Array(visibleKinds.enumerated()), id: \.element.id) { idx, kind in
                                    kindValueItems(kind, isFirst: idx == 0, cellH: cellH)
                                }
                            }
                            .padding(.leading, 4)
                            if !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .padding(.leading, 4)
                                    .padding(.top, -8)
                            }
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        // 最初の縦線のみ VStack 全高（メモ行含む）に渡って描画
        .overlay(alignment: .leading) {
            HStack(spacing: 0) {
                Color.clear.frame(width: dateColumnWidth + 4)
                Divider()
                    .padding(.vertical, 8)
                Spacer()
            }
        }
        .font(.footnote)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func kindValueItems(_ kind: GraphKind, isFirst: Bool, cellH: CGFloat) -> some View {
        if !isFirst {
            Divider().padding(.vertical, 8)
        }
        kindValueCells(kind, cellH: cellH)
    }

    @ViewBuilder
    private func kindValueCells(_ kind: GraphKind, cellH: CGFloat) -> some View {
        switch kind {
        case .bp:
            valueCell(record.displayBpHi, width: 42, height: cellH)
            valueCell(record.displayBpLo, width: 42, height: cellH)
        case .pulse:
            valueCell(record.displayPulse, width: 42, height: cellH)
        case .weight:
            valueCell(record.displayWeight, width: 60, height: cellH)
        case .temp:
            valueCell(record.displayTemp, width: 52, height: cellH)
        case .bodyFat:
            valueCell(record.displayBodyFat, width: 52, height: cellH)
        case .skMuscle:
            valueCell(record.displaySkMuscle, width: 52, height: cellH)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func valueCell(_ value: String, width: CGFloat, height: CGFloat = 32) -> some View {
        Text(value.isEmpty ? "-" : value)
            .font(.title3.monospacedDigit())
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(value.isEmpty ? Color.secondary.opacity(0.4) : .primary)
            .frame(width: width, height: height)
    }
}

// MARK: - エクスポートシート

private enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf = "export.format.pdf"
    case csv = "export.format.csv"
    case json = "export.format.json"
    var id: String { rawValue }
    var shortLabel: String {
        switch self {
        case .pdf:  return "PDF"
        case .csv:  return "CSV"
        case .json: return "JSON"
        }
    }
}

private struct ExportSheetView: View {
    let records: [BodyRecord]
    let visibleKinds: [GraphKind]
    @Environment(\.dismiss) private var dismiss
    private let cal = Calendar.current

    @State private var fromDate: Date
    @State private var toDate: Date = Date()
    @State private var format: ExportFormat = .pdf
    @State private var ascending: Bool = false
    @State private var isGenerating = false

    init(records: [BodyRecord], visibleKinds: [GraphKind]) {
        self.records = records
        self.visibleKinds = visibleKinds
        _fromDate = State(initialValue: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date())
    }

    private var targetRecords: [BodyRecord] {
        let start = cal.startOfDay(for: fromDate)
        let end   = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: toDate)) ?? toDate
        return records.filter { $0.dateTime >= start && $0.dateTime < end }
                      .sorted { ascending ? $0.dateTime < $1.dateTime : $0.dateTime > $1.dateTime }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("filter.period") {
                    DatePicker("filter.start",
                               selection: $fromDate, in: ...toDate,
                               displayedComponents: .date)
                    DatePicker("filter.end",
                               selection: $toDate, in: fromDate...,
                               displayedComponents: .date)
                }
                Section("export.format") {
                    Picker("", selection: $format) {
                        ForEach(ExportFormat.allCases) { f in
                            Text(LocalizedStringKey(f.rawValue)).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    Picker("sort.title", selection: $ascending) {
                        Text("sort.descendingNewest").tag(false)
                        Text("sort.ascendingOldest").tag(true)
                    }
                }
                Section {
                    HStack {
                        Text("export.targetCount")
                        Spacer()
                        Text(String(format: String(localized: "format.recordCount"), targetRecords.count))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("export.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await generateAndShare() }
                    } label: {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Text("action.export").bold()
                        }
                    }
                    .disabled(targetRecords.isEmpty || isGenerating)
                }
            }
            .overlay { if isGenerating { exportingOverlay } }
        }
    }

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                Text(String(format: String(localized: "export.generating"), format.shortLabel))
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @MainActor
    private func generateAndShare() async {
        isGenerating = true
        try? await Task.sleep(for: .milliseconds(50))
        let items = buildShareItems()
        guard !items.isEmpty else { isGenerating = false; return }

        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { isGenerating = false; return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        isGenerating = false
        topVC.present(activityVC, animated: true)
    }

    @MainActor
    private func buildShareItems() -> [Any] {
        let appName = String(localized: "app.name")
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        let dateTag = f.string(from: Date())
        switch format {
        case .json:
            let json = generateJSON()
            if let url = tempFile(name: "\(appName)_\(dateTag).json", data: json) { return [url] }
            return []
        case .csv:
            let csv = generateCSV()
            if let data = csv.data(using: .utf8),
               let url = tempFile(name: "\(appName)_\(dateTag).csv", data: data) { return [url] }
            return []
        case .pdf:
            let pdfData = generatePDF()
            if let url = tempFile(name: "\(appName)_\(dateTag).pdf", data: pdfData) { return [url] }
            return []
        }
    }

    private func tempFile(name: String, data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - JSON（表示項目のみ）

    private func generateJSON() -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                             .withColonSeparatorInTime, .withTimeZone]

        var result: [[String: Any]] = []
        for r in targetRecords {
            var obj: [String: Any] = [
                "dateTime":  iso.string(from: r.dateTime),
                "condition": NSLocalizedString(r.dateOpt.label, comment: ""),
            ]
            for kind in visibleKinds {
                switch kind {
                case .bp:
                    if r.nBpHi_mmHg > 0 { obj["bpSystolic"]  = r.nBpHi_mmHg }
                    if r.nBpLo_mmHg > 0 { obj["bpDiastolic"] = r.nBpLo_mmHg }
                case .pulse:
                    if r.nPulse_bpm > 0 { obj["heartRate"] = r.nPulse_bpm }
                case .temp:
                    if r.nTemp_10c > 0 { obj["bodyTemp"] = Double(r.nTemp_10c) / 10.0 }
                case .weight:
                    if r.nWeight_10Kg > 0 { obj["weight"] = Double(r.nWeight_10Kg) / 10.0 }
                case .bodyFat:
                    if r.nBodyFat_10p > 0 { obj["bodyFat"] = Double(r.nBodyFat_10p) / 10.0 }
                case .skMuscle:
                    if r.nSkMuscle_10p > 0 { obj["skeletalMuscle"] = Double(r.nSkMuscle_10p) / 10.0 }
                default: break
                }
            }
            if r.bCaution         { obj["cautionFlag"] = true }
            if !r.sNote1.isEmpty  { obj["memo1"]  = r.sNote1 }
            if !r.sNote2.isEmpty  { obj["memo2"]  = r.sNote2 }
            if !r.sEquipment.isEmpty { obj["device"] = r.sEquipment }
            result.append(obj)
        }
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let envelope: [String: Any] = [
            "exportDate": df.string(from: Date()),
            "records": result,
        ]
        return (try? JSONSerialization.data(withJSONObject: envelope,
                                           options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: - CSV（Excel 互換・UTF-8 BOM付き）

    private func generateCSV() -> String {
        func escape(_ s: String) -> String {
            guard s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") else { return s }
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }

        let L = { NSLocalizedString($0, comment: "") }
        var headers = [
            escape(L("record.datetime")),
            escape(L("record.category")),
        ]
        for kind in visibleKinds {
            switch kind {
            case .bp:
                headers.append(escape(L("metric.systolic.mmHg")))
                headers.append(escape(L("metric.diastolic.mmHg")))
            case .pulse:    headers.append(escape(L("metric.heartRate.bpm")))
            case .temp:     headers.append(escape(L("metric.bodyTemp.celsius")))
            case .weight:   headers.append(escape(L("metric.weight.kg")))
            case .bodyFat:  headers.append(escape(L("metric.bodyFat.percent")))
            case .skMuscle: headers.append(escape(L("metric.skeletalMuscle.percent")))
            default: break
            }
        }
        headers += [
            escape(L("record.cautionFlag")),
            escape(L("record.memo1")),
            escape(L("record.memo2")),
            escape(L("record.device")),
        ]

        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("yMdEEEEEHmm")

        var rows: [String] = [headers.joined(separator: ",")]
        for r in targetRecords {
            var fields = [escape(df.string(from: r.dateTime)), escape(NSLocalizedString(r.dateOpt.label, comment: ""))]
            for kind in visibleKinds {
                switch kind {
                case .bp:
                    fields.append(r.nBpHi_mmHg > 0 ? "\(r.nBpHi_mmHg)" : "")
                    fields.append(r.nBpLo_mmHg > 0 ? "\(r.nBpLo_mmHg)" : "")
                case .pulse:
                    fields.append(r.nPulse_bpm > 0 ? "\(r.nPulse_bpm)" : "")
                case .temp:
                    fields.append(r.nTemp_10c > 0 ? String(format: "%.1f", Double(r.nTemp_10c) / 10.0) : "")
                case .weight:
                    fields.append(r.nWeight_10Kg > 0 ? String(format: "%.1f", Double(r.nWeight_10Kg) / 10.0) : "")
                case .bodyFat:
                    fields.append(r.nBodyFat_10p > 0 ? String(format: "%.1f", Double(r.nBodyFat_10p) / 10.0) : "")
                case .skMuscle:
                    fields.append(r.nSkMuscle_10p > 0 ? String(format: "%.1f", Double(r.nSkMuscle_10p) / 10.0) : "")
                default: break
                }
            }
            fields += [r.bCaution ? "1" : "", escape(r.sNote1), escape(r.sNote2), escape(r.sEquipment)]
            rows.append(fields.joined(separator: ","))
        }

        // UTF-8 BOM を先頭に付加することで Excel が文字化けなく開ける
        return "\u{FEFF}" + rows.joined(separator: "\r\n")
    }

    // MARK: - PDF（A4 改ページ対応）

    @MainActor
    private func generatePDF() -> Data {
        let pages = paginateRecords(targetRecords)
        var mediaBox = CGRect(x: 0, y: 0, width: PDFLayout.pageW, height: PDFLayout.pageH)
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        for (i, pageRecords) in pages.enumerated() {
            let view = ExportPDFPageView(
                records: pageRecords, visibleKinds: visibleKinds,
                fromDate: fromDate, toDate: toDate,
                pageNumber: i + 1, totalPages: pages.count, isFirstPage: i == 0
            )
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: PDFLayout.pageW, height: PDFLayout.pageH)
            ctx.beginPDFPage(nil)
            renderer.render { _, renderFn in renderFn(ctx) }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return pdfData as Data
    }

    private func paginateRecords(_ records: [BodyRecord]) -> [[BodyRecord]] {
        var pages: [[BodyRecord]] = []
        var current: [BodyRecord] = []
        var remaining = PDFLayout.usableH(isFirst: true)

        for r in records {
            let h = PDFLayout.estimatedRowH(r)
            if current.isEmpty || remaining >= h {
                current.append(r)
                remaining -= h
            } else {
                pages.append(current)
                current = [r]
                remaining = PDFLayout.usableH(isFirst: false) - h
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages.isEmpty ? [[]] : pages
    }
}

// MARK: - PDF レイアウト定数

private enum PDFLayout {
    static let pageW:     CGFloat = 595
    static let pageH:     CGFloat = 842
    static let margin:    CGFloat = 16
    static let contentW:  CGFloat = pageW - margin * 2   // 563
    static let dateColW:  CGFloat = 138
    static var optColW:   CGFloat {
        Locale.current.language.languageCode?.identifier == "ja" ? 44 : 82
    }
    static let notesW:    CGFloat = contentW - dateColW  // 425
    static let rowH:      CGFloat = 22
    static let memoLineH: CGFloat = 14
    static let divH:      CGFloat = 1
    static let titleH:    CGFloat = 46
    static let colHeadH:  CGFloat = 22
    static let footerH:   CGFloat = 18

    static func usableH(isFirst: Bool) -> CGFloat {
        pageH - margin * 2
            - (isFirst ? titleH : 0)
            - colHeadH - divH - footerH
    }

    static func estimatedRowH(_ r: BodyRecord) -> CGFloat {
        let notes = [r.sNote1, r.sNote2].filter { !$0.isEmpty }.joined(separator: "  ")
        guard !notes.isEmpty else { return rowH + divH }
        let charsPerLine = 38
        let lines = max(1, (notes.count + charsPerLine - 1) / charsPerLine)
        return rowH + CGFloat(lines) * memoLineH + 3 + divH
    }
}

// MARK: - PDF ページビュー

private struct ExportPDFPageView: View {
    let records: [BodyRecord]
    let visibleKinds: [GraphKind]
    let fromDate: Date
    let toDate: Date
    let pageNumber: Int
    let totalPages: Int
    let isFirstPage: Bool

    private static let dtdf: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMdEEEEEHmm")
        return f
    }()
    private static let datedf: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirstPage {
                HStack(alignment: .top) {
                    Text("app.name")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Self.datedf.string(from: fromDate)
                             + String(localized: "format.range.separator")
                             + Self.datedf.string(from: toDate))
                        Text(NSLocalizedString("export.created", comment: "")
                             + " " + Self.datedf.string(from: Date()))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
            pdfHeaderRow
            Divider().background(Color.gray)
            ForEach(records) { record in
                pdfDataRow(record)
                Divider()
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text("\(pageNumber) / \(totalPages)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(PDFLayout.margin)
        .frame(width: PDFLayout.pageW, height: PDFLayout.pageH, alignment: .topLeading)
        .background(Color.white)
    }

    private var pdfHeaderRow: some View {
        HStack(spacing: 0) {
            Text("record.datetime")
                .frame(width: PDFLayout.dateColW, alignment: .leading).padding(3)
            Text("record.category")
                .frame(width: PDFLayout.optColW, alignment: .center).padding(3)
            ForEach(visibleKinds, id: \.rawValue) { kind in
                ForEach(Array(pdfColumnHeaders(kind).enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: pdfCellWidth(kind), alignment: .center)
                        .padding(3)
                }
            }
        }
        .font(.caption.bold())
        .background(Color(UIColor.systemGray5))
    }

    private func pdfDataRow(_ r: BodyRecord) -> some View {
        let notes = [r.sNote1, r.sNote2].filter { !$0.isEmpty }.joined(separator: "  ")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(Self.dtdf.string(from: r.dateTime))
                    .lineLimit(1)
                    .frame(width: PDFLayout.dateColW, alignment: .leading).padding(3)
                Text(NSLocalizedString(r.dateOpt.label, comment: ""))
                    .lineLimit(1)
                    .frame(width: PDFLayout.optColW, alignment: .center).padding(3)
                ForEach(visibleKinds, id: \.rawValue) { kind in
                    ForEach(Array(pdfCellValues(r, kind).enumerated()), id: \.offset) { _, value in
                        Text(value.isEmpty ? "-" : value)
                            .frame(width: pdfCellWidth(kind), alignment: .trailing)
                            .padding(3)
                            .foregroundStyle(value.isEmpty ? Color.secondary.opacity(0.4) : .primary)
                    }
                }
            }
            if !notes.isEmpty {
                // 明示的な幅指定でメモ列を固定し列ズレを防ぐ
                Text(notes)
                    .foregroundStyle(.secondary)
                    .frame(width: PDFLayout.notesW - 6, alignment: .leading)
                    .padding(.leading, PDFLayout.dateColW + 3)
                    .padding(.trailing, 3)
                    .padding(.bottom, 3)
            }
        }
        .font(.caption)
    }

    private func pdfColumnHeaders(_ kind: GraphKind) -> [String] {
        switch kind {
        case .bp:
            return [NSLocalizedString("metric.systolic.mmHg.short", comment: ""),
                    NSLocalizedString("metric.diastolic.mmHg.short", comment: "")]
        case .pulse:    return [NSLocalizedString("metric.heartRate.bpm.short", comment: "")]
        case .temp:     return [NSLocalizedString("metric.bodyTemp.celsius", comment: "")]
        case .weight:   return [NSLocalizedString("metric.weight.kg", comment: "")]
        case .bodyFat:  return [NSLocalizedString("metric.bodyFat.percent.short", comment: "")]
        case .skMuscle: return [NSLocalizedString("metric.skeletalMuscle.percent.short", comment: "")]
        default:        return []
        }
    }

    private func pdfCellValues(_ r: BodyRecord, _ kind: GraphKind) -> [String] {
        switch kind {
        case .bp:       return [r.displayBpHi, r.displayBpLo]
        case .pulse:    return [r.displayPulse]
        case .temp:     return [r.displayTemp]
        case .weight:   return [r.displayWeight]
        case .bodyFat:  return [r.displayBodyFat]
        case .skMuscle: return [r.displaySkMuscle]
        default:        return []
        }
    }

    private func pdfCellWidth(_ kind: GraphKind) -> CGFloat {
        switch kind {
        case .bp:       return 46
        case .pulse:    return 44
        case .temp:     return 44
        case .weight:   return 48
        case .bodyFat:  return 50
        case .skMuscle: return 50
        default:        return 0
        }
    }
}
