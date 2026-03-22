// SettingsView.swift
// 設定メイン画面（旧 SettingTVC 相当）

import SwiftUI
import SwiftData

struct SettingsView: View {

    @State private var settings = AppSettings.shared
    @State private var healthKit = HealthKitService.shared
    @State private var showHKSettings = false

    private var aboutURL: URL {
        let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        let urlString = isJapanese
            ? "https://docs.azukid.com/jp/sumpo/Condition/condition.html"
            : "https://docs.azukid.com/en/sumpo/Condition/condition.html"
        return URL(string: urlString)!
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 記録
                Section(String(localized: "Settings_Record", defaultValue: "記録")) {
                    NavigationLink(String(localized: "Settings_FieldOrder", defaultValue: "項目の表示と順序")) {
                        FieldOrderSettingsView()
                    }
                    NavigationLink {
                        DateOptMatrixView()
                    } label: {
                        Text(String(localized: "Settings_DateOpt", defaultValue: "時間帯と区分の初期値"))
                    }

                    // ヘルスケア
                    if healthKit.isAvailable {
                        NavigationLink {
                            HealthKitSettingsView()
                        } label: {
                            Toggle(
                                String(localized: "Settings_HealthKit", defaultValue: "ヘルスケア連携"),
                                isOn: $settings.hkEnabled
                            )
                            .onChange(of: settings.hkEnabled) { _, enabled in
                                if enabled {
                                    Task { await healthKit.requestAuthorization() }
                                    showHKSettings = true
                                }
                            }
                        }
                    }
                }
                .onAppear { if healthKit.isAvailable { healthKit.checkAuthorization() } }
                .navigationDestination(isPresented: $showHKSettings) {
                    HealthKitSettingsView()
                }

                // MARK: - 分析
                Section(String(localized: "Settings_Graph", defaultValue: "分析")) {
                    NavigationLink(String(localized: "Settings_GraphDetail", defaultValue: "グラフ設定")) {
                        GraphSettingsView()
                    }
                    NavigationLink(String(localized: "Settings_StatDetail", defaultValue: "統計設定")) {
                        StatSettingsView()
                    }
                }

                // MARK: - アプリ情報
                Section {
                    Link(String(localized: "Settings_About", defaultValue: "このアプリについて"),
                         destination: aboutURL)
                }
            }
            .navigationTitle(String(localized: "Tab_Settings", defaultValue: "設定"))
        }
    }

}

// MARK: - 時間帯と区分の初期値マトリックス

struct DateOptMatrixView: View {
    @State private var settings = AppSettings.shared

    private let kinds = DateOpt.allCases

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ヘッダー行
                HStack(spacing: 1) {
                    Spacer().frame(width: 28)
                    ForEach(kinds, id: \.rawValue) { kind in
                        VStack(spacing: 1) {
                            Image(systemName: kind.icon)
                                .font(.caption)
                                .foregroundStyle(kind.color)
                            Text(kind.label)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))

                Divider()

                // 時間行（0〜23時）
                ForEach(0..<24, id: \.self) { hour in
                    HStack(spacing: 1) {
                        Text(String(format: "%d", hour))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                            .padding(.trailing, 2)
                        ForEach(kinds, id: \.rawValue) { kind in
                            let isOn = settings.dateOptHourMap[hour] == kind.rawValue
                            ZStack {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isOn ? kind.color : Color(.systemFill))
                                if isOn {
                                    Image(systemName: kind.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .onTapGesture {
                                guard !isOn else { return }
                                settings.dateOptHourMap[hour] = kind.rawValue
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "Settings_DateOpt", defaultValue: "時間帯と区分の初期値"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - グラフ設定

struct GraphSettingsView: View {
    var isModal: Bool = false
    @State private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    private var hiddenSet: Set<Int> { Set(settings.graphHiddenPanels) }

    var body: some View {
        List {
            Section(String(localized: "GraphSett_Display", defaultValue: "補助グラフ")) {
                Toggle(
                    String(localized: "GraphSett_BpMean", defaultValue: "平均血圧（（上－下）÷3＋下）"),
                    isOn: $settings.graphBpMean
                )
                Toggle(
                    String(localized: "GraphSett_WeightMA", defaultValue: "体重移動平均（直近7件）"),
                    isOn: $settings.graphWeightMA
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(localized: "GraphSett_Tall", defaultValue: "身長（BMI 計算用）"))
                            .font(.callout)
                        Spacer()
                        NumpadValueText(value: $settings.graphBMITall, min: 100, max: 250, decimals: 0, color: .primary)
                        Text("cm")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    AZDialView(
                        value: $settings.graphBMITall,
                        min: 100,
                        max: 250,
                        step: 1,
                        stepperStep: 5
                    )
                }
                .padding(.vertical, 4)
                NavigationLink {
                    GoalSettingsView()
                } label: {
                    LabeledContent(
                        String(localized: "GraphSett_Goal", defaultValue: "目標"),
                        value: String(localized: "GraphSett_GoalAction", defaultValue: "設定")
                    )
                }
            }

            Section(String(localized: "GraphSett_DialStyle", defaultValue: "ダイアルデザイン")) {
                HStack(spacing: 12) {
                    ForEach(DialStyle.allCases, id: \.rawValue) { style in
                        let selected = settings.dialStyle == style.rawValue
                        Button {
                            settings.dialStyle = style.rawValue
                        } label: {
                            VStack(spacing: 6) {
                                AZDialBack(offset: 5, tickGap: 10, style: style)
                                    .frame(height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                                lineWidth: selected ? 2 : 1
                                            )
                                    )
                                Text(style.label)
                                    .font(.caption)
                                    .foregroundStyle(selected ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(settings.graphDisplayOrder, id: \.self) { raw in
                    if let kind = GraphKind(rawValue: raw) {
                        Toggle(isOn: Binding(
                            get: { !hiddenSet.contains(raw) },
                            set: { visible in
                                if visible {
                                    settings.graphHiddenPanels.removeAll { $0 == raw }
                                } else if !settings.graphHiddenPanels.contains(raw) {
                                    settings.graphHiddenPanels.append(raw)
                                }
                            }
                        )) {
                            Text(kind.title)
                        }
                    }
                }
                .onMove { from, to in
                    settings.graphDisplayOrder.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text(String(localized: "GraphSett_PanelOrder", defaultValue: "グラフ表示と並び順"))
            } footer: {
                Text(String(localized: "GraphSett_PanelOrder_Footer", defaultValue: "並び順はグラフに反映されます"))
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(String(localized: "GraphSett_Title", defaultValue: "グラフ設定"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

// MARK: - 項目の表示と順序

struct FieldOrderSettingsView: View {
    @State private var settings = AppSettings.shared

    private var hiddenSet: Set<Int> { Set(settings.hiddenFields) }

    var body: some View {
        List {
            Section {
                ForEach(settings.graphPanelOrder, id: \.self) { raw in
                    if let kind = GraphKind(rawValue: raw), kind.isRecordField {
                        Toggle(isOn: Binding(
                            get: { !hiddenSet.contains(raw) },
                            set: { visible in
                                if visible {
                                    settings.hiddenFields.removeAll { $0 == raw }
                                } else {
                                    if !settings.hiddenFields.contains(raw) {
                                        settings.hiddenFields.append(raw)
                                    }
                                }
                            }
                        )) {
                            Text(kind.title)
                        }
                    }
                }
                .onMove { from, to in
                    settings.graphPanelOrder.move(fromOffsets: from, toOffset: to)
                }
            } footer: {
                Text(String(localized: "FieldOrder_Footer", defaultValue: "並び順は記録入力に反映されます"))
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(String(localized: "Settings_FieldOrder", defaultValue: "項目の表示と順序"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 統計設定

struct StatSettingsView: View {
    var isModal: Bool = false
    @State private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    private var hiddenSet: Set<Int> { Set(settings.statHiddenSections) }

    var body: some View {
        List {
            Section {
                ForEach(settings.statSectionOrder, id: \.self) { raw in
                    if let section = StatSection(rawValue: raw) {
                        Toggle(isOn: Binding(
                            get: { !hiddenSet.contains(raw) },
                            set: { visible in
                                if visible {
                                    settings.statHiddenSections.removeAll { $0 == raw }
                                } else if !settings.statHiddenSections.contains(raw) {
                                    settings.statHiddenSections.append(raw)
                                }
                            }
                        )) {
                            Text(section.title)
                        }
                    }
                }
                .onMove { from, to in
                    settings.statSectionOrder.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text(String(localized: "StatSett_PanelOrder", defaultValue: "統計表示と並び順"))
            } footer: {
                Text(String(localized: "StatSett_Footer", defaultValue: "並び順は統計画面に反映されます"))
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(String(localized: "StatSett_Title", defaultValue: "統計設定"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

// MARK: - 目標値設定

struct GoalSettingsView: View {
    @State private var settings = AppSettings.shared

    @Query(
        filter: #Predicate<BodyRecord> { $0.dateTime < bodyRecordGoalDate },
        sort: \BodyRecord.dateTime,
        order: .reverse
    )
    private var records: [BodyRecord]

    private var latest: BodyRecord? { records.first }

    // 最新値（0 = 未記録）
    private var latestBpHi:    Int? { latest?.nBpHi_mmHg }
    private var latestBpLo:    Int? { latest?.nBpLo_mmHg }
    private var latestBpPp:    Int? {
        guard let hi = latest?.nBpHi_mmHg, let lo = latest?.nBpLo_mmHg,
              hi > 0, lo > 0 else { return nil }
        return hi - lo
    }
    private var latestPulse:   Int? { latest?.nPulse_bpm }
    private var latestWeight:  Int? { latest?.nWeight_10Kg }
    private var latestTemp:    Int? { latest?.nTemp_10c }
    private var latestPedo:    Int? { latest?.nPedometer }
    private var latestBodyFat: Int? { latest?.nBodyFat_10p }
    private var latestSkMuscle:Int? { latest?.nSkMuscle_10p }
    private var latestBMI:     Int? {
        guard let w = latest?.nWeight_10Kg, w > 0,
              settings.graphBMITall > 0 else { return nil }
        let hm = Double(settings.graphBMITall) / 100.0
        return Int((Double(w) / 10.0 / (hm * hm) * 10).rounded())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Goal_Title", defaultValue: "目標値")) {
                    goalDialRow(title: "上（収縮期血圧）", value: $settings.goalBpHi,      spec: MeasureRange.bpHi,      recordVal: latestBpHi,   unit: "mmHg", stepperStep: 10, color: .red)
                    goalDialRow(title: "下（拡張期血圧）", value: $settings.goalBpLo,      spec: MeasureRange.bpLo,      recordVal: latestBpLo,   unit: "mmHg", stepperStep: 5,  color: .blue)
                    goalDialRow(title: "脈圧",             value: $settings.goalBpPp,      spec: MeasureRange.bpPp,      recordVal: latestBpPp,   unit: "mmHg", stepperStep: 5,  color: .orange)
                    goalDialRow(title: "心拍数",           value: $settings.goalPulse,     spec: MeasureRange.pulse,     recordVal: latestPulse,  unit: "bpm",  stepperStep: 5,  color: .orange)
                    goalDialRow(title: "体重",             value: $settings.goalWeight,    spec: MeasureRange.weight,    recordVal: latestWeight, unit: "kg",   stepperStep: 10, decimals: 1, color: .indigo)
                    goalDialRow(title: "BMI",              value: $settings.goalBMI,       spec: MeasureRange.bmi,       recordVal: latestBMI,    unit: "",     stepperStep: 5,  decimals: 1, color: .cyan)
                    goalDialRow(title: "体温",             value: $settings.goalTemp,      spec: MeasureRange.temp,      recordVal: latestTemp,   unit: "℃",   stepperStep: 1,  decimals: 1, color: .pink)
                    goalDialRow(title: "歩数",             value: $settings.goalPedometer, spec: MeasureRange.pedometer, recordVal: latestPedo,   unit: "歩",   stepperStep: 1000, color: .green)
                    goalDialRow(title: "体脂肪率",         value: $settings.goalBodyFat,   spec: MeasureRange.bodyFat,   recordVal: latestBodyFat,unit: "%",    stepperStep: 5,  decimals: 1, color: .purple)
                    goalDialRow(title: "骨格筋率",         value: $settings.goalSkMuscle,  spec: MeasureRange.skMuscle,  recordVal: latestSkMuscle,unit: "%",   stepperStep: 5,  decimals: 1, color: .teal)
                }
            }
            .navigationTitle(String(localized: "GoalLine_Title", defaultValue: "目標設定"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func goalDialRow(
        title: String,
        value: Binding<Int>,
        spec: MeasureSpec,
        recordVal: Int?,
        unit: String,
        stepperStep: Int,
        decimals: Int = 0,
        color: Color = .primary
    ) -> some View {
        let defaultVal = (recordVal ?? 0) > 0 ? recordVal! : spec.initVal
        let enabled = Binding<Bool>(
            get: { value.wrappedValue > 0 },
            set: { on in value.wrappedValue = on ? defaultVal : 0 }
        )
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                if enabled.wrappedValue {
                    NumpadValueText(value: value, min: spec.min, max: spec.max, decimals: decimals, color: color)
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
            }
            if enabled.wrappedValue {
                AZDialView(value: value, min: spec.min, max: spec.max, step: 1, stepperStep: stepperStep, decimals: decimals)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - HealthKit 設定

struct HealthKitSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var hkService = HealthKitService.shared
    @Environment(\.openURL) private var openURL
    @State private var showGuideAlert = false

    private var directionBinding: Binding<HKSyncDirection> {
        Binding(
            get: { HKSyncDirection(rawValue: settings.hkDirection) ?? .writeOnly },
            set: { settings.hkDirection = $0.rawValue }
        )
    }
    private var timingBinding: Binding<HKSyncTiming> {
        Binding(
            get: { HKSyncTiming(rawValue: settings.hkTiming) ?? .automatic },
            set: { settings.hkTiming = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section(String(localized: "HKSett_Auth", defaultValue: "アクセス権限")) {
                HStack {
                    Text(String(localized: "HKSett_Status", defaultValue: "ステータス"))
                    Spacer()
                    Text(hkService.isAuthorized
                         ? String(localized: "HKSett_Authorized", defaultValue: "許可済み")
                         : String(localized: "HKSett_NotAuthorized", defaultValue: "未許可"))
                        .foregroundStyle(hkService.isAuthorized ? Color.secondary : Color.orange)
                    Button(String(localized: "HKSett_ChangePermission", defaultValue: "許可を変更")) {
                        if hkService.isAuthorized {
                            showGuideAlert = true
                        } else {
                            Task { await hkService.requestAuthorization() }
                        }
                    }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }

            Section(String(localized: "HKSett_Direction", defaultValue: "同期方向")) {
                Picker(String(localized: "HKSett_Direction", defaultValue: "同期方向"),
                       selection: directionBinding) {
                    Text(String(localized: "HKDir_Write", defaultValue: "書き込みのみ（アプリ → ヘルスケア）"))
                        .tag(HKSyncDirection.writeOnly)
                    Text(String(localized: "HKDir_Read", defaultValue: "読み込みのみ（ヘルスケア → アプリ）"))
                        .tag(HKSyncDirection.readOnly)
                    Text(String(localized: "HKDir_Both", defaultValue: "双方向"))
                        .tag(HKSyncDirection.both)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section(String(localized: "HKSett_Timing", defaultValue: "タイミング")) {
                Picker(String(localized: "HKSett_Timing", defaultValue: "タイミング"),
                       selection: timingBinding) {
                    Text(String(localized: "HKTiming_Auto", defaultValue: "自動（保存時 / 画面表示時）"))
                        .tag(HKSyncTiming.automatic)
                    Text(String(localized: "HKTiming_Manual", defaultValue: "手動（ボタン操作）"))
                        .tag(HKSyncTiming.manual)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                Text(String(localized: "HKSett_Note",
                            defaultValue: "連携対象：上・下血圧、心拍数、体重、体温、歩数、体脂肪率"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(String(localized: "HKSett_Note2",
                            defaultValue: "このアプリからヘルスケアのデータは変更・削除できません。常に追加されるだけです。不要なデータがあればヘルスケア側で項目毎に「すべてのデータを表示」し、編集にて削除してください"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(String(localized: "HKSett_Title", defaultValue: "ヘルスケア連携"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hkService.checkAuthorization() }
        .onChange(of: settings.hkDirection) { _, _ in updateNeedsAutoImport() }
        .onChange(of: settings.hkTiming)    { _, _ in updateNeedsAutoImport() }
        .alert(
            String(localized: "HKGuide_Title", defaultValue: "ヘルスケアの許可を変更"),
            isPresented: $showGuideAlert
        ) {
            Button(String(localized: "HKGuide_Open", defaultValue: "ヘルスケアを開く")) {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            }
            Button(String(localized: "Cancel", defaultValue: "キャンセル"), role: .cancel) {}
        } message: {
            Text(String(localized: "HKGuide_Message",
                        defaultValue: "ヘルスケア右上のアイコンをタップ → プライバシー → アプリ → 体調メモ を表示し、許可スイッチを操作してください"))
        }
    }

    private func updateNeedsAutoImport() {
        let canImport = settings.hkEnabled &&
            (HKSyncDirection(rawValue: settings.hkDirection)?.canRead == true) &&
            HKSyncTiming(rawValue: settings.hkTiming) == .automatic
        if canImport { hkService.needsAutoImport = true }
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 68))
                            .foregroundStyle(Color.azuki)
                        Text(String(localized: "App_Name", defaultValue: "体調メモ"))
                            .font(.title.bold())
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(AppConstants.copyright)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical)
            }

            Section(String(localized: "About_Support", defaultValue: "サポート")) {
                Link(
                    String(localized: "About_Website", defaultValue: "公式サイト"),
                    destination: URL(string: "https://azukid.com")!
                )
                Link(
                    String(localized: "About_Review", defaultValue: "App Store でレビュー"),
                    destination: URL(string: "https://apps.apple.com/app/id\(AppConstants.productName)")!
                )
            }
        }
        .navigationTitle(String(localized: "About_Title", defaultValue: "このアプリについて"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
