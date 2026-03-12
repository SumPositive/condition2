// SettingsView.swift
// 設定メイン画面（旧 SettingTVC 相当）

import SwiftUI

struct SettingsView: View {

    @State private var settings = AppSettings.shared
    @State private var calendar = CalendarService.shared
    @State private var showGraphSettings = false
    @State private var showStatSettings  = false
    @State private var showCalendarSettings = false
    @State private var showGoalSettings  = false
    @State private var showAbout         = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 機能
                Section(String(localized: "Settings_Features", defaultValue: "機能")) {
                    Toggle(
                        String(localized: "Settings_Goal", defaultValue: "目標値を表示"),
                        isOn: $settings.goalEnabled
                    )
                    Toggle(
                        String(localized: "Settings_Calendar", defaultValue: "カレンダー連携"),
                        isOn: $settings.calendarEnabled
                    )
                    .onChange(of: settings.calendarEnabled) { _, enabled in
                        if enabled { Task { await calendar.requestAccess() } }
                    }
                }

                // MARK: - グラフ・統計
                Section(String(localized: "Settings_Graph", defaultValue: "グラフ・統計")) {
                    NavigationLink(String(localized: "Settings_GraphDetail", defaultValue: "グラフ設定")) {
                        GraphSettingsView()
                    }
                    NavigationLink(String(localized: "Settings_StatDetail", defaultValue: "統計設定")) {
                        StatSettingsView()
                    }
                }

                // MARK: - 目標値
                if settings.goalEnabled {
                    Section {
                        NavigationLink(String(localized: "Settings_GoalDetail", defaultValue: "目標値を設定")) {
                            GoalSettingsView()
                        }
                    }
                }

                // MARK: - カレンダー
                if settings.calendarEnabled {
                    Section(String(localized: "Settings_CalendarSection", defaultValue: "カレンダー")) {
                        NavigationLink(String(localized: "Settings_CalendarDetail", defaultValue: "カレンダーを選択")) {
                            CalendarSettingsView()
                        }
                        if !settings.calendarTitle.isEmpty {
                            HStack {
                                Text(String(localized: "Settings_CalendarSelected", defaultValue: "選択中"))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(settings.calendarTitle)
                            }
                        }
                    }
                }

                // MARK: - 時刻設定（DateOpt 自動判定）
                Section(String(localized: "Settings_DateOpt", defaultValue: "測定時刻設定")) {
                    hourPicker(
                        label: String(localized: "DateOpt_Wake", defaultValue: "起床時"),
                        value: $settings.wakeHour
                    )
                    hourPicker(
                        label: String(localized: "DateOpt_Down", defaultValue: "就寝前"),
                        value: $settings.downHour
                    )
                    hourPicker(
                        label: String(localized: "DateOpt_Sleep", defaultValue: "就寝時"),
                        value: $settings.sleepHour
                    )
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
        }
    }

    private func hourPicker(label: String, value: Binding<Int>) -> some View {
        Picker(label, selection: value) {
            ForEach(0..<24, id: \.self) { h in
                Text(String(format: "%d時", h)).tag(h)
            }
        }
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

// MARK: - 統計設定

struct StatSettingsView: View {
    @State private var settings = AppSettings.shared

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
                Stepper(
                    "\(settings.statDays) 日間",
                    value: $settings.statDays,
                    in: 1...GraphConstants.statDaysMax,
                    step: 1
                )
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
                Section(String(localized: "Goal_BP", defaultValue: "血圧・脈拍")) {
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
                        label: String(localized: "Field_Pulse", defaultValue: "脈拍"),
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

// MARK: - カレンダー設定

struct CalendarSettingsView: View {
    @State private var calService = CalendarService.shared
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            if calService.availableCalendars.isEmpty {
                Section {
                    Text(String(localized: "Calendar_NoAccess", defaultValue: "カレンダーへのアクセスが許可されていません"))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Calendar_Request", defaultValue: "アクセスを許可")) {
                        Task { await calService.requestAccess() }
                    }
                }
            } else {
                Section(String(localized: "Calendar_Select", defaultValue: "カレンダーを選択")) {
                    ForEach(calService.availableCalendars, id: \.calendarIdentifier) { cal in
                        HStack {
                            Circle()
                                .fill(Color(cgColor: cal.cgColor))
                                .frame(width: 12, height: 12)
                            Text(cal.title)
                            Spacer()
                            if settings.calendarID == cal.calendarIdentifier {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            settings.calendarID    = cal.calendarIdentifier
                            settings.calendarTitle = cal.title
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Calendar_Title", defaultValue: "カレンダー選択"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await calService.requestAccess() }
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
                        Text(String(localized: "App_Name", defaultValue: "健康日記"))
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
