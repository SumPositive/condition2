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
                bpSection
                bodySection
                activitySection
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
                        title: String(localized: "Field_Equipment", defaultValue: "測定機器"),
                        text: $vm.sEquipment
                    )
                }

                // オプションセクション
                Section {
                    Toggle(
                        String(localized: "Field_Caution", defaultValue: "注意フラグ"),
                        isOn: $vm.bCaution
                    )
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

    @ViewBuilder
    private var dateSection: some View {
        if case .goalEdit = vm.mode { } else {
            Section {
                dateRow
                dateOptRow
            }
        }
    }

    @ViewBuilder
    private var bpSection: some View {
        Section(String(localized: "Section_BP", defaultValue: "血圧")) {
            dialRow(title: "上（収縮期血圧）", value: $vm.nBpHi_mmHg,  enabled: $vm.bpHiEnabled,      spec: MeasureRange.bpHi,   unit: "mmHg", stepperStep: 10, color: .red)
            dialRow(title: "下（拡張期血圧）", value: $vm.nBpLo_mmHg,  enabled: $vm.bpLoEnabled,      spec: MeasureRange.bpLo,   unit: "mmHg", stepperStep: 5,  color: .blue)
            dialRow(title: "脈拍",           value: $vm.nPulse_bpm,   enabled: $vm.pulseEnabled,     spec: MeasureRange.pulse,  unit: "bpm",  stepperStep: 5,  color: .orange)
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        Section(String(localized: "Section_Body", defaultValue: "体重・体温")) {
            dialRow(title: "体重", value: $vm.nWeight_10Kg, enabled: $vm.weightEnabled,    spec: MeasureRange.weight, unit: "kg", stepperStep: 10, decimals: 1, color: .indigo)
            dialRow(title: "体温", value: $vm.nTemp_10c,    enabled: $vm.tempEnabled,      spec: MeasureRange.temp,   unit: "℃", stepperStep: 1,  decimals: 1, color: .pink)
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        Section(String(localized: "Section_Activity", defaultValue: "活動・体組成")) {
            dialRow(title: "歩数",     value: $vm.nPedometer,    enabled: $vm.pedometerEnabled, spec: MeasureRange.pedometer, unit: "歩", stepperStep: 1000,           color: .green)
            dialRow(title: "体脂肪率", value: $vm.nBodyFat_10p,  enabled: $vm.bodyFatEnabled,   spec: MeasureRange.bodyFat,   unit: "%",  stepperStep: 5, decimals: 1, color: .purple)
            dialRow(title: "骨格筋率", value: $vm.nSkMuscle_10p, enabled: $vm.skMuscleEnabled,  spec: MeasureRange.skMuscle,  unit: "%",  stepperStep: 5, decimals: 1, color: .teal)
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
                Text(String(localized: "HK_Import_Footer", defaultValue: "過去1年の未読記録を読み込みます"))
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

            let hkValues = await HealthKitService.shared.readDailySamples(from: oneYearAgo, to: now)

            // 既存レコードの日付セット（過去1年）
            let descriptor = FetchDescriptor<BodyRecord>(
                predicate: #Predicate { $0.dateTime >= oneYearAgo && $0.dateTime < now }
            )
            let existing = (try? context.fetch(descriptor)) ?? []
            let existingDays = Set(existing.map { cal.startOfDay(for: $0.dateTime) })

            let appSettings = AppSettings.shared
            var addedCount = 0
            for v in hkValues {
                let day = cal.startOfDay(for: v.date)
                guard !existingDays.contains(day) else { continue }
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
                    .font(.subheadline)
                Spacer()
                if enabled.wrappedValue {
                    Text(ValueFormatter.format(value.wrappedValue, decimals: decimals))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(color)
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color.opacity(0.7))
                } else {
                    Text("－")
                        .font(.title2)
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
                    stepperStep: stepperStep
                )
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - メモ行

    private func noteRow(title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
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
