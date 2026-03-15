// SettingsView.swift
// 設定メイン画面（旧 SettingTVC 相当）

import SwiftUI

struct SettingsView: View {

    @State private var settings = AppSettings.shared
@State private var healthKit = HealthKitService.shared
    @Environment(\.openURL) private var openURL
    @State private var showHKGuideAlert  = false

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
                        Toggle(
                            String(localized: "Settings_HealthKit", defaultValue: "ヘルスケア連携"),
                            isOn: $settings.hkEnabled
                        )
                        .onChange(of: settings.hkEnabled) { _, enabled in
                            if enabled { Task { await healthKit.requestAuthorization() } }
                            updateNeedsAutoImport()
                        }
                        if settings.hkEnabled {
                            HStack {
                                Text(String(localized: "HKSett_Status", defaultValue: "ステータス"))
                                Spacer()
                                Text(healthKit.isAuthorized
                                     ? String(localized: "HKSett_Authorized", defaultValue: "許可済み")
                                     : String(localized: "HKSett_NotAuthorized", defaultValue: "未許可"))
                                    .foregroundStyle(healthKit.isAuthorized ? Color.secondary : Color.orange)
                                Button(String(localized: "HKSett_ChangePermission", defaultValue: "許可を変更")) {
                                    if healthKit.isAuthorized {
                                        showHKGuideAlert = true
                                    } else {
                                        Task { await healthKit.requestAuthorization() }
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                            }
                            Picker(String(localized: "HKSett_Direction", defaultValue: "同期方向"),
                                   selection: Binding(
                                    get: { HKSyncDirection(rawValue: settings.hkDirection) ?? .writeOnly },
                                    set: { settings.hkDirection = $0.rawValue }
                                   )) {
                                Text(String(localized: "HKDir_Read",  defaultValue: "読み込みのみ")).tag(HKSyncDirection.readOnly)
                                Text(String(localized: "HKDir_Write", defaultValue: "書き込みのみ")).tag(HKSyncDirection.writeOnly)
                                Text(String(localized: "HKDir_Both",  defaultValue: "双方向")).tag(HKSyncDirection.both)
                            }
                            .pickerStyle(.segmented)
                            Picker(String(localized: "HKSett_Timing", defaultValue: "タイミング"),
                                   selection: Binding(
                                    get: { HKSyncTiming(rawValue: settings.hkTiming) ?? .automatic },
                                    set: { settings.hkTiming = $0.rawValue }
                                   )) {
                                Text(String(localized: "HKTiming_Manual", defaultValue: "手動")).tag(HKSyncTiming.manual)
                                Text(String(localized: "HKTiming_Auto",   defaultValue: "自動")).tag(HKSyncTiming.automatic)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                .onAppear { if healthKit.isAvailable { healthKit.checkAuthorization() } }
                .onChange(of: settings.hkDirection) { _, _ in updateNeedsAutoImport() }
                .onChange(of: settings.hkTiming)    { _, _ in updateNeedsAutoImport() }

                // MARK: - カスタマイズ
                Section(String(localized: "Settings_Graph", defaultValue: "カスタマイズ")) {
                    NavigationLink(String(localized: "Settings_GraphDetail", defaultValue: "グラフ設定")) {
                        GraphSettingsView()
                    }
                    NavigationLink(String(localized: "Settings_StatDetail", defaultValue: "統計設定")) {
                        StatSettingsView()
                    }
                }

                // MARK: - アプリ情報
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Text(String(localized: "Settings_About", defaultValue: "このアプリについて"))
                    }
                }
            }
            .navigationTitle(String(localized: "Tab_Settings", defaultValue: "設定"))
            .alert(
                String(localized: "HKGuide_Title", defaultValue: "ヘルスケアの許可を変更"),
                isPresented: $showHKGuideAlert
            ) {
                Button(String(localized: "HKGuide_Open", defaultValue: "ヘルスケアを開く")) {
                    if let url = URL(string: "x-apple-health://") {
                        openURL(url)
                    }
                }
                Button(String(localized: "Cancel", defaultValue: "キャンセル"), role: .cancel) {}
            } message: {
                Text(String(localized: "HKGuide_Message",
                            defaultValue: "ヘルスケア右上のアイコンをタップ → プライバシー → アプリ → 体調メモ を表示し、許可スイッチを操作してください"))
            }
        }
    }

    private func updateNeedsAutoImport() {
        let canImport = settings.hkEnabled &&
            (HKSyncDirection(rawValue: settings.hkDirection)?.canRead == true) &&
            HKSyncTiming(rawValue: settings.hkTiming) == .automatic
        if canImport { healthKit.needsAutoImport = true }
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
                                .font(.caption2)
                                .foregroundStyle(kind.color)
                            Text(kind.label)
                                .font(.system(size: 9))
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
                            .font(.system(size: 11).monospacedDigit())
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
                                        .font(.system(size: 9))
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
    @State private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(String(localized: "GraphSett_Display", defaultValue: "表示項目")) {
                Toggle(
                    String(localized: "GraphSett_BpMean", defaultValue: "平均血圧"),
                    isOn: $settings.graphBpMean
                )
                Toggle(
                    String(localized: "GraphSett_BpPress", defaultValue: "脈圧"),
                    isOn: $settings.graphBpPress
                )
                Toggle(
                    String(localized: "Settings_Goal", defaultValue: "目標値を表示"),
                    isOn: $settings.goalEnabled
                )
                if settings.goalEnabled {
                    NavigationLink(String(localized: "Settings_GoalDetail", defaultValue: "目標値を設定")) {
                        GoalSettingsView()
                    }
                }
            }

            Section(String(localized: "GraphSett_BMI", defaultValue: "BMI計算（身長）")) {
                HStack {
                    Text(String(localized: "GraphSett_Tall", defaultValue: "身長"))
                    Spacer()
                    TextField("170", value: $settings.graphBMITall, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("cm").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "GraphSett_Title", defaultValue: "グラフ設定"))
        .navigationBarTitleDisplayMode(.inline)
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
                    if let kind = GraphKind(rawValue: raw), kind != .bpAvg {
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
                Text(String(localized: "FieldOrder_Footer", defaultValue: "並び順はグラフと記録入力の両方に反映されます"))
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(String(localized: "Settings_FieldOrder", defaultValue: "項目の表示と順序"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 統計設定

struct StatSettingsView: View {
    @State private var settings = AppSettings.shared

    private var periodBinding: Binding<GraphPeriod> {
        Binding(
            get: { GraphPeriod(rawValue: settings.statDays) ?? .threeMonths },
            set: { settings.statDays = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section(String(localized: "StatSett_Type", defaultValue: "グラフ種類")) {
                Picker(
                    String(localized: "StatSett_TypePicker", defaultValue: "表示方式"),
                    selection: $settings.statType
                ) {
                    Text(String(localized: "StatSett_HiLo", defaultValue: "Hi-Lo分散")).tag(0)
                    Text(String(localized: "StatSett_24H",  defaultValue: "24時間分散")).tag(1)
                }
                .pickerStyle(.segmented)
            }

            Section(String(localized: "StatSett_Days", defaultValue: "集計期間")) {
                Picker("期間", selection: periodBinding) {
                    ForEach(GraphPeriod.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(String(localized: "StatSett_Options", defaultValue: "表示オプション")) {
                Toggle(
                    String(localized: "StatSett_ShowAvg", defaultValue: "平均±標準偏差"),
                    isOn: $settings.statShowAvg
                )
                Toggle(
                    String(localized: "StatSett_TimeLine", defaultValue: "時系列線"),
                    isOn: $settings.statShowTimeLine
                )
                Toggle(
                    String(localized: "StatSett_24HLine", defaultValue: "起床・就寝ライン（24時間）"),
                    isOn: $settings.statShow24HLine
                )
            }
        }
        .navigationTitle(String(localized: "StatSett_Title", defaultValue: "統計設定"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 目標値設定

struct GoalSettingsView: View {
    @State private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Goal_BP", defaultValue: "血圧・心拍数")) {
                    goalDialRow(
                        label: String(localized: "Field_BpHi", defaultValue: "上血圧"),
                        value: $settings.goalBpHi,
                        spec: MeasureRange.bpHi,
                        unit: "mmHg"
                    )
                    goalDialRow(
                        label: String(localized: "Field_BpLo", defaultValue: "下血圧"),
                        value: $settings.goalBpLo,
                        spec: MeasureRange.bpLo,
                        unit: "mmHg"
                    )
                    goalDialRow(
                        label: String(localized: "Field_Pulse", defaultValue: "心拍数"),
                        value: $settings.goalPulse,
                        spec: MeasureRange.pulse,
                        unit: "bpm"
                    )
                }
                Section(String(localized: "Goal_Body", defaultValue: "体重・体温")) {
                    goalDialRow(
                        label: String(localized: "Field_Weight", defaultValue: "体重"),
                        value: $settings.goalWeight,
                        spec: MeasureRange.weight,
                        unit: "kg",
                        decimals: 1
                    )
                    goalDialRow(
                        label: String(localized: "Field_Temp", defaultValue: "体温"),
                        value: $settings.goalTemp,
                        spec: MeasureRange.temp,
                        unit: "℃",
                        decimals: 1
                    )
                }
                Section(String(localized: "Goal_Activity", defaultValue: "活動・体組成")) {
                    goalDialRow(
                        label: String(localized: "Field_Pedo", defaultValue: "歩数"),
                        value: $settings.goalPedometer,
                        spec: MeasureRange.pedometer,
                        unit: String(localized: "Unit_Steps", defaultValue: "歩")
                    )
                    goalDialRow(
                        label: String(localized: "Field_BodyFat", defaultValue: "体脂肪率"),
                        value: $settings.goalBodyFat,
                        spec: MeasureRange.bodyFat,
                        unit: "%",
                        decimals: 1
                    )
                    goalDialRow(
                        label: String(localized: "Field_SkMuscle", defaultValue: "骨格筋率"),
                        value: $settings.goalSkMuscle,
                        spec: MeasureRange.skMuscle,
                        unit: "%",
                        decimals: 1
                    )
                }
            }
            .navigationTitle(String(localized: "Goal_Title", defaultValue: "目標値"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", defaultValue: "完了")) { dismiss() }
                }
            }
        }
    }

    private func goalDialRow(
        label: String,
        value: Binding<Int>,
        spec: MeasureSpec,
        unit: String,
        decimals: Int = 0
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(value.wrappedValue > 0 ? ValueFormatter.format(value.wrappedValue, decimals: decimals) : "-")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(value.wrappedValue > 0 ? .primary : .secondary)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            AZDialView(value: value, min: spec.min, max: spec.max, step: 1, stepperStep: 5)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - HealthKit 設定

struct HealthKitSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var hkService = HealthKitService.shared

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
                }
                if !hkService.isAuthorized {
                    Button(String(localized: "HKSett_Request", defaultValue: "アクセスを許可")) {
                        Task { await hkService.requestAuthorization() }
                    }
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(String(localized: "HKSett_Title", defaultValue: "ヘルスケア設定"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hkService.checkAuthorization() }
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
                            .font(.system(size: 60))
                            .foregroundStyle(Color.azuki)
                        Text(String(localized: "App_Name", defaultValue: "体調メモ"))
                            .font(.title2.bold())
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(AppConstants.copyright)
                            .font(.caption2)
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
