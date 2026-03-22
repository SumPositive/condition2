// RecordEditView.swift
// 記録編集画面（旧 E2editTVC 相当）

import SwiftUI
import SwiftData
import HealthKit

struct RecordEditView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var vm: RecordEditViewModel
    @State private var showDatePicker = false
    @State private var showDeleteAlert = false

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMdEjmm")
        return f
    }()

    private var settings: AppSettings { AppSettings.shared }
    private var hkService: HealthKitService { HealthKitService.shared }

    private var hkDirection: HKSyncDirection {
        HKSyncDirection(rawValue: settings.hkDirection) ?? .writeOnly
    }
    private var hkTiming: HKSyncTiming {
        HKSyncTiming(rawValue: settings.hkTiming) ?? .automatic
    }

    private var isNewRecord: Bool {
        if case .addNew = vm.mode { return true }
        return false
    }

    private var title: String {
        switch vm.mode {
        case .addNew:    return String(localized: "Edit_Title_Add",  defaultValue: "新規記録")
        case .edit:      return String(localized: "Edit_Title_Edit", defaultValue: "記録編集")
        case .goalEdit:  return String(localized: "Edit_Title_Goal", defaultValue: "目標値")
        }
    }

    private let onHKImported: ((Int) -> Void)?

    init(mode: EditMode, onHKImported: ((Int) -> Void)? = nil) {
        _vm = State(initialValue: RecordEditViewModel(mode: mode))
        self.onHKImported = onHKImported
    }

    var body: some View {
        NavigationStack {
            Form {
                hkImportSection
                dateSection
                Section(String(localized: "Section_Measure", defaultValue: "計測値")) {
                    ForEach(orderedRecordFields, id: \.rawValue) { kind in
                        fieldRow(for: kind)
                    }
                }
                healthKitSection

                // メモセクション
                Section(String(localized: "Section_Note", defaultValue: "メモ")) {
                    noteRow(
                        title: String(localized: "Field_Note1", defaultValue: "メモ1"),
                        text: $vm.sNote1
                    )
                    noteRow(
                        title: String(localized: "Field_Note2", defaultValue: "メモ2"),
                        text: $vm.sNote2
                    )
                    noteRow(
                        title: String(localized: "Field_Equipment", defaultValue: "計測機器"),
                        text: $vm.sEquipment
                    )
                }

                // オプションセクション
                Section {
                    Toggle(isOn: $vm.bCaution) {
                        HStack(spacing: 6) {
                            if vm.bCaution {
                                Image(systemName: "flag.fill")
                                    .foregroundStyle(.orange)
                            }
                            Text(String(localized: "Field_Caution", defaultValue: "注意フラグ"))
                        }
                    }
                }

                // 削除ボタン（編集時のみ）
                if case .edit(let record) = vm.mode {
                    Section {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label(
                                String(localized: "Delete_Record", defaultValue: "この記録を削除"),
                                systemImage: "trash"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .alert(
                        String(localized: "Delete_Confirm", defaultValue: "この記録を削除しますか？"),
                        isPresented: $showDeleteAlert
                    ) {
                        Button(String(localized: "Delete", defaultValue: "削除"), role: .destructive) {
                            try? vm.delete(record: record, context: context)
                            dismiss()
                        }
                        Button(String(localized: "Cancel", defaultValue: "キャンセル"), role: .cancel) {}
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", defaultValue: "保存")) {
                        saveAndDismiss()
                    }
                    .disabled(!vm.isModified && !isNewRecord)
                    .bold()
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", defaultValue: "キャンセル")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(date: $vm.dateTime) {
                    vm.onDateChanged()
                }
            }
            .onAppear {
                if isNewRecord {
                    vm.loadPreviousValues(context: context)
                }
            }
            .onChange(of: vm.bCaution)      { _, _ in vm.isModified = true }
            .onChange(of: vm.nBpHi_mmHg)   { _, _ in vm.isModified = true }
            .onChange(of: vm.nBpLo_mmHg)   { _, _ in vm.isModified = true }
            .onChange(of: vm.nPulse_bpm)    { _, _ in vm.isModified = true }
            .onChange(of: vm.nWeight_10Kg)  { _, _ in vm.isModified = true }
            .onChange(of: vm.nTemp_10c)     { _, _ in vm.isModified = true }
            .onChange(of: vm.nPedometer)    { _, _ in vm.isModified = true }
            .onChange(of: vm.nBodyFat_10p)  { _, _ in vm.isModified = true }
            .onChange(of: vm.nSkMuscle_10p) { _, _ in vm.isModified = true }
        }
    }

    // MARK: - セクション分割ヘルパー

    /// 設定の順序と非表示設定に従った表示フィールド一覧
    private var orderedRecordFields: [GraphKind] {
        let hidden = Set(settings.hiddenFields)
        return settings.graphPanelOrder
            .compactMap { GraphKind(rawValue: $0) }
            .filter { $0.isRecordField && !hidden.contains($0.rawValue) }
    }

    @ViewBuilder
    private func fieldRow(for kind: GraphKind) -> some View {
        switch kind {
        case .bp:
            dialRow(title: "上（収縮期血圧）", value: $vm.nBpHi_mmHg, enabled: $vm.bpHiEnabled, spec: MeasureRange.bpHi, unit: "mmHg", stepperStep: 10, color: .red)
            dialRow(title: "下（拡張期血圧）", value: $vm.nBpLo_mmHg, enabled: $vm.bpLoEnabled, spec: MeasureRange.bpLo, unit: "mmHg", stepperStep: 5,  color: .blue)
        case .pulse:
            dialRow(title: "心拍数", value: $vm.nPulse_bpm, enabled: $vm.pulseEnabled, spec: MeasureRange.pulse, unit: "bpm", stepperStep: 5, color: .orange)
        case .weight:
            dialRow(title: "体重", value: $vm.nWeight_10Kg, enabled: $vm.weightEnabled, spec: MeasureRange.weight, unit: "kg", stepperStep: 10, decimals: 1, color: .indigo)
        case .temp:
            dialRow(title: "体温", value: $vm.nTemp_10c, enabled: $vm.tempEnabled, spec: MeasureRange.temp, unit: "℃", stepperStep: 1, decimals: 1, color: .pink)
        case .pedo:
            dialRow(title: "歩数", value: $vm.nPedometer, enabled: $vm.pedometerEnabled, spec: MeasureRange.pedometer, unit: "歩", stepperStep: 1000, color: .green)
        case .bodyFat:
            dialRow(title: "体脂肪率", value: $vm.nBodyFat_10p, enabled: $vm.bodyFatEnabled, spec: MeasureRange.bodyFat, unit: "%", stepperStep: 5, decimals: 1, color: .purple)
        case .skMuscle:
            dialRow(title: "骨格筋率", value: $vm.nSkMuscle_10p, enabled: $vm.skMuscleEnabled, spec: MeasureRange.skMuscle, unit: "%", stepperStep: 5, decimals: 1, color: .teal)
        case .bpAvg, .bmi, .weightChange:
            EmptyView()
        }
    }

    @ViewBuilder
    private var dateSection: some View {
        if case .goalEdit = vm.mode { } else {
            if case .edit = vm.mode, settings.hkEnabled {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: vm.dataSource.icon)
                            .foregroundStyle(vm.dataSource.color)
                        Text(vm.dataSource.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                dateRow
                dateOptRow
            }
        }
    }

    // MARK: - HealthKit 取得ボタン（先頭・新規追加かつ手動のみ）

    @ViewBuilder
    private var hkImportSection: some View {
        if isNewRecord && settings.hkEnabled && hkDirection.canRead && hkTiming == .manual {
            Section {
                Button {
                    bulkImportFromHealthKit()
                } label: {
                    HStack {
                        Label(
                            String(localized: "HK_Import", defaultValue: "ヘルスケアから取得"),
                            systemImage: "arrow.down.heart"
                        )
                        Spacer()
                        if vm.isLoadingFromHK {
                            ProgressView()
                        }
                    }
                }
                .disabled(vm.isLoadingFromHK)
            } footer: {
                if vm.isLoadingFromHK, !hkService.importProgress.isEmpty {
                    Text(hkService.importProgress)
                } else {
                    Text(String(localized: "HK_Import_Footer", defaultValue: "過去1年の未読記録を読み込みます"))
                }
            }
        }
    }

    private func bulkImportFromHealthKit() {
        vm.isLoadingFromHK = true
        Task {
            defer { vm.isLoadingFromHK = false }
            let cal = Calendar.current
            let now = Date()
            let oneYearAgo = cal.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 24 * 3600)

            let appSettings = AppSettings.shared
            let hkValues = await HealthKitService.shared.readSamples(
                from: oneYearAgo, to: now,
                hiddenFields: Set(appSettings.hiddenFields)
            )

            // 既存レコードの時刻セット（過去1年、分単位）
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
                let record = BodyRecord(dateTime: v.date, dateOpt: appSettings.autoDateOpt(for: v.date))
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
            try? context.save()
            let count = addedCount
            dismiss()
            onHKImported?(count)
        }
    }

    // MARK: - HealthKit セクション（書き込み手動のみ）

    @ViewBuilder
    private var healthKitSection: some View {
        let showWrite = settings.hkEnabled && hkDirection.canWrite && hkTiming == .manual
        if showWrite {
            Section(String(localized: "HK_Section", defaultValue: "ヘルスケア")) {
                Button {
                    vm.writeToHealthKit()
                } label: {
                    Label(
                        String(localized: "HK_Export", defaultValue: "ヘルスケアへ書き込み"),
                        systemImage: "arrow.up.heart"
                    )
                }
            }
        }
    }

    // MARK: - 日時行

    private var dateRow: some View {
        Button {
            showDatePicker = true
        } label: {
            HStack {
                Text(String(localized: "Field_DateTime", defaultValue: "日時"))
                    .foregroundStyle(.primary)
                Spacer()
                Text(Self.dateTimeFormatter.string(from: vm.dateTime))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateOptRow: some View {
        Picker(selection: $vm.dateOpt) {
            ForEach(DateOpt.allCases, id: \.self) { opt in
                Label(opt.label, systemImage: opt.icon).tag(opt)
            }
        } label: {
            Text(String(localized: "Field_DateOpt", defaultValue: "区分"))
        }
        .onChange(of: vm.dateOpt) { _, _ in vm.isModified = true }
    }

    // MARK: - ダイアル行

    @ViewBuilder
    private func dialRow(
        title: LocalizedStringKey,
        value: Binding<Int>,
        enabled: Binding<Bool>,
        spec: MeasureSpec,
        unit: LocalizedStringKey,
        stepperStep: Int,
        decimals: Int = 0,
        color: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                if enabled.wrappedValue {
                    Text(ValueFormatter.format(value.wrappedValue, decimals: decimals))
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(color)
                    Text(unit)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(color.opacity(0.7))
                } else {
                    Text("－")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                }
                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .onChange(of: enabled.wrappedValue) { _, _ in vm.isModified = true }
            }
            if enabled.wrappedValue {
                AZDialView(
                    value: value,
                    min: spec.min,
                    max: spec.max,
                    step: 1,
                    stepperStep: stepperStep,
                    decimals: decimals
                )
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - メモ行

    private func noteRow(title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.callout)
            TextField("", text: text)
                .multilineTextAlignment(.trailing)
                .onChange(of: text.wrappedValue) { _, _ in vm.isModified = true }
        }
    }

    // MARK: - 保存

    private func saveAndDismiss() {
        do {
            try vm.save(context: context)
            dismiss()
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 日付ピッカーシート

struct DatePickerSheet: View {
    @Binding var date: Date
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "",
                selection: $date,
                in: ...BodyRecord.maxInputDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
            .navigationTitle(String(localized: "DatePicker_Title", defaultValue: "日時を選択"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", defaultValue: "完了")) {
                        onChanged()
                        dismiss()
                    }
                }
            }
        }
    }
}
