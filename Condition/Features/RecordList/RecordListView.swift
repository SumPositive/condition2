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

    @State private var toastMessage: String? = nil
    @State private var showHKTimeoutAlert = false

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
                String(localized: "HKTimeout_Title", defaultValue: "ヘルスケア連携"),
                isPresented: $showHKTimeoutAlert
            ) {
                Button("OK") { hkService.importTimedOut = false }
            } message: {
                Text(String(localized: "HKTimeout_Message", defaultValue: "ヘルスケアで「すべてのデータを表示」に異常がないか確認してください"))
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
            record.nPedometer   = v.steps
            record.nBodyFat_10p = v.bodyFat
            context.insert(record)
            addedCount += 1
        }
        if addedCount > 0 {
            try? context.save()
            enforceStepsConstraintAfterImport(in: oneYearAgo...now, context: context)
            showImportToast(count: addedCount)
        }
    }

    /// バルクインポート後、対象期間内の各日について歩数を最終時刻レコードにのみ残す
    private func enforceStepsConstraintAfterImport(in range: ClosedRange<Date>, context: ModelContext) {
        let cal = Calendar.current
        var descriptor = FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.dateTime >= range.lowerBound && $0.dateTime <= range.upperBound },
            sortBy: [SortDescriptor(\.dateTime)]
        )
        descriptor.includePendingChanges = true
        guard let allRecords = try? context.fetch(descriptor) else { return }

        // 日ごとにグループ化して最終時刻以外の歩数をゼロクリア
        let grouped = Dictionary(grouping: allRecords) { cal.startOfDay(for: $0.dateTime) }
        var changed = false
        for dayRecords in grouped.values {
            let sorted = dayRecords.sorted { $0.dateTime < $1.dateTime }
            guard let last = sorted.last else { continue }
            for record in sorted where record.persistentModelID != last.persistentModelID {
                if record.nPedometer != 0 {
                    record.nPedometer = 0
                    changed = true
                }
            }
        }
        if changed { try? context.save() }
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

// MARK: - 列幅定義

/// 日付列の固定幅（ヘッダーと明細で共通。title2.bold "31" + spacing + icon 44pt + trailing 4pt）
private let dateColumnWidth: CGFloat = 110

private func subColumnWidths(for kind: GraphKind) -> [CGFloat] {
    switch kind {
    case .bp:       return [42, 42]
    case .pulse:    return [42]
    case .weight:   return [60]
    case .temp:     return [52]
    case .pedo:     return [62]
    case .bodyFat:  return [52]
    case .skMuscle: return [52]
    default:        return []
    }
}

private func computeColumnSpacing(availableWidth: CGFloat, kinds: [GraphKind]) -> CGFloat {
    let allWidths = kinds.flatMap { subColumnWidths(for: $0) }
    let sepCount = max(0, kinds.count - 1)
    let totalFixed = allWidths.reduce(CGFloat(0), +) + CGFloat(sepCount)
    let gapCount = allWidths.count - 1 + sepCount
    guard gapCount > 0 else { return 4 }
    return max(2, (availableWidth - 4 - totalFixed) / CGFloat(gapCount))
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
                    Text("日時")
                        .font(.caption)
                    Spacer()
                    Text("区分")
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .frame(width: 44, alignment: .center)
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
            Text("上").minimumScaleFactor(0.6).lineLimit(1).frame(width: 42)
            Text("下").minimumScaleFactor(0.6).lineLimit(1).frame(width: 42)
        case .pulse:
            Text("心拍数").minimumScaleFactor(0.6).lineLimit(1).frame(width: 42)
        case .weight:
            Text("体重").minimumScaleFactor(0.6).lineLimit(1).frame(width: 60)
        case .temp:
            Text("体温").minimumScaleFactor(0.6).lineLimit(1).frame(width: 52)
        case .pedo:
            Text("歩数").minimumScaleFactor(0.6).lineLimit(1).frame(width: 62)
        case .bodyFat:
            Text("体脂肪").minimumScaleFactor(0.6).lineLimit(1).frame(width: 52)
        case .skMuscle:
            Text("骨格筋").minimumScaleFactor(0.6).lineLimit(1).frame(width: 52)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // 日付＋区分
                HStack(alignment: .bottom, spacing: 2) {
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
                        // 常に 6pt スペーサーを確保（メモあり行と位置を揃える）
                        Color.clear.frame(height: 6)
                    }
                    // 右：区分アイコン＋データソースアイコン（注意フラグは overlay）
                    VStack(spacing: 3) {
                        Image(systemName: record.dateOpt.icon)
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                            .offset(y: 8)
                        if hkEnabled {
                            Image(systemName: record.dataSource.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(record.dataSource.color)
                                .offset(x: -22)
                        }
                        // 左 VStack と同量のスペーサーで底揃え位置を一致させる
                        Color.clear.frame(height: 6)
                    }
                    .frame(width: 44, alignment: .center)
                    .overlay(alignment: .bottom) {
                        if record.bCaution {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .offset(x: hkEnabled ? -22 : 0)
                                .padding(.bottom, hkEnabled ? 22 : 0)
                        }
                    }
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
                                    .foregroundStyle(.tertiary)
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
        case .pedo:
            valueCell(record.displayPedo, width: 62, height: cellH)
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
