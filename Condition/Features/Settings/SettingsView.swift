// SettingsView.swift
// 設定メイン画面（旧 SettingTVC 相当）

import SwiftUI
import SwiftData
import AZDial
import StoreKit
import WebKit

struct SettingsView: View {

    @State private var settings = AppSettings.shared
    @State private var healthKit = HealthKitService.shared
    @State private var showHKSettings = false
    @State private var showSafari = false
    @State private var showDialSettings = false

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
                Section("tab.records") {
                    NavigationLink("settings.fieldOrder") {
                        FieldOrderSettingsView()
                    }
                    NavigationLink {
                        DateOptMatrixView()
                    } label: {
                        Text("settings.dateCategoryDefaults")
                    }

                    // ヘルスケア
                    if healthKit.isAvailable && !settings.hkDisabledByDemo {
                        NavigationLink {
                            HealthKitSettingsView()
                        } label: {
                            Toggle(
                                "health.integration",
                                isOn: $settings.hkEnabled
                            )
                            .onChange(of: settings.hkEnabled) { _, enabled in
                                if enabled {
                                    Task { await healthKit.requestAuthorization() }
                                    showHKSettings = true
                                    healthKit.needsAutoImport = true
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
                Section("settings.analysis") {
                    NavigationLink("graph.settings") {
                        GraphSettingsView()
                    }
                    NavigationLink("statistics.settings") {
                        StatSettingsView()
                    }
                }

                // MARK: - 表示
                Section("settings.display") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("appearance.mode")
                            .font(.callout)
                        Picker("", selection: $settings.appearanceMode) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Button {
                        showDialSettings = true
                    } label: {
                        LabeledContent(
                            "settings.dialSettings",
                            value: DialStyle.builtin(id: settings.dialStyle)?.label ?? DialStyle.shape.label
                        )
                    }
                }

                // MARK: - アプリ情報
                Section {
                    Button("app.about") {
                        showSafari = true
                    }
                }

                // MARK: - 開発者を応援
                Section {
                    SupportDeveloperView()
                }

                // MARK: - バージョン
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
                Text(String(format: String(localized: "format.version"), version, build))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .navigationTitle("tab.settings")
        }
        .sheet(isPresented: $showSafari) {
            SafariView(url: aboutURL)
        }
        .sheet(isPresented: $showDialSettings) {
            NavigationStack {
                AZDialSettingsView(
                    tuning: $settings.dialTuning,
                    style: dialStyleBinding,
                    configuration: dialSettingsConfiguration
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("action.done") {
                            showDialSettings = false
                        }
                    }
                }
            }
        }
    }

    private var dialStyleBinding: Binding<DialStyle> {
        Binding(
            get: { DialStyle.builtin(id: settings.dialStyle) ?? .shape },
            set: { settings.dialStyle = $0.id }
        )
    }

    private var dialSettingsConfiguration: AZDialSettingsConfiguration {
        AZDialSettingsConfiguration(
            title: "settings.dialSettings",
            localizationBundle: .main
        )
    }

}

// MARK: - SafariView

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = WebViewController(url: url)
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

private class WebViewController: UIViewController, WKNavigationDelegate {
    private let url: URL
    private var webView: WKWebView!

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped))

        webView = WKWebView()
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        webView.load(URLRequest(url: url))
    }

    @objc private func doneTapped() { dismiss(animated: true) }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              url.host?.contains("apps.apple.com") == true else {
            return .allow
        }
#if targetEnvironment(simulator)
        let alert = UIAlertController(title: nil,
                                      message: String(localized: "error.simulatorCannotOpen"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
        present(alert, animated: true)
#else
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
#endif
        return .cancel
    }
}

// MARK: - 開発者を応援

private struct SupportDeveloperView: View {
    @State private var store = TipStore.shared
    @State private var showTip = false
    @State private var showAd = false
    @State private var showAdThankYou = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("support.title")
                    .font(.body.weight(.medium))
            } icon: {
                Image(systemName: "heart.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
                    .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.periodic(delay: 0.0)))
            }

            Button {
                showTip = true
            } label: {
                Text("support.tip")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .sheet(isPresented: $showTip) {
                TipSheetView()
            }

            Button {
                showAd = true
            } label: {
                Text("support.watchAd")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brown)
            .sheet(isPresented: $showAd) {
                AdMobAdSheetView {
                    showAdThankYou = true
                }
            }
        }
        .padding(.vertical, 4)
        .task { await store.loadProducts() }
        .alert(
            "support.thanks.title",
            isPresented: $showAdThankYou
        ) {
            Button("action.ok") {}
        } message: {
            Text("support.thankYouForWatchingTheAd")
        }
    }
}

private struct TipSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = TipStore.shared
    @State private var showThankYou = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.pink)
                    .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.periodic(delay: 0.0)))

                Text("support.yourSupportHelpsKeepThisApp")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if store.isLoadingProducts {
                    ProgressView()
                } else if store.products.isEmpty {
                    Text("text.notAvailableAtThisTime")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        ForEach(store.products, id: \.id) { product in
                            Button {
                                Task {
                                    if await store.purchase(product) {
                                        showThankYou = true
                                    }
                                }
                            } label: {
                                Text(product.displayPrice)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pink)
                            .disabled(store.isPurchasing)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("support.tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .alert(
                "support.thanks.title",
                isPresented: $showThankYou
            ) {
                Button("action.ok") { dismiss() }
            } message: {
                Text("support.thankYouForYourSupportWe")
            }
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
                            Text(LocalizedStringKey(kind.label))
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
        .navigationTitle("settings.dateCategoryDefaults")
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
            Section("settings.helperGraphs") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("metric.heightForBMI")
                            .font(.callout)
                        Spacer()
                        NumpadValueText(value: $settings.graphBMITall, min: 100, max: 250, decimals: 0, color: .primary)
                        Text("unit.cm")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    AZDialView(
                        value: $settings.graphBMITall,
                        min: 100,
                        max: 250,
                        step: 1,
                        stepperStep: 5,
                        style: DialStyle.builtin(id: settings.dialStyle) ?? .shape,
                        tuning: settings.dialTuning
                    )
                }
                .padding(.vertical, 4)
                NavigationLink {
                    GoalSettingsView()
                } label: {
                    Text("goal.line")
                }
            }

            Section {
                ForEach(settings.graphDisplayOrder, id: \.self) { raw in
                    if let kind = GraphKind(rawValue: raw) {
                        graphDisplayOrderRow(kind: kind, raw: raw)
                    }
                }
                .onMove { from, to in
                    settings.graphDisplayOrder.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text("graph.displayOrder")
            } footer: {
                Text("chart.orderIsReflectedInGraphView")
            }
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("graph.settings")
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

    @ViewBuilder
    private func graphDisplayOrderRow(kind: GraphKind, raw: Int) -> some View {
        let hasChildSettings = kind == .bp || kind == .weight
        VStack(alignment: .leading, spacing: hasChildSettings ? 4 : 0) {
            HStack {
                Toggle(isOn: graphPanelVisibleBinding(raw: raw)) {
                    Text(LocalizedStringKey(kind.title))
                }
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
            }

            if kind == .bp {
                childGraphVisibilityRow(
                    isVisible: $settings.graphBpMean,
                    titleKey: "metric.meanBloodPressure"
                )
            }
            if kind == .weight {
                childGraphVisibilityRow(
                    isVisible: $settings.graphWeightMA,
                    titleKey: "metric.weightMovingAverage"
                )
            }
        }
        .padding(.top, hasChildSettings ? 4 : 0)
        .padding(.bottom, hasChildSettings ? 0 : 0)
    }

    private func childGraphVisibilityRow(isVisible: Binding<Bool>, titleKey: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye" : "eye.slash")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isVisible.wrappedValue ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(titleKey)
            Text(titleKey)
                .font(.callout)
            Spacer()
        }
        .padding(.leading, 28)
    }

    private func graphPanelVisibleBinding(raw: Int) -> Binding<Bool> {
        Binding(
            get: { !hiddenSet.contains(raw) },
            set: { visible in
                if visible {
                    settings.graphHiddenPanels.removeAll { $0 == raw }
                } else if !settings.graphHiddenPanels.contains(raw) {
                    settings.graphHiddenPanels.append(raw)
                }
            }
        )
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
                            Text(LocalizedStringKey(kind.title))
                        }
                    }
                }
                .onMove { from, to in
                    settings.graphPanelOrder.move(fromOffsets: from, toOffset: to)
                }
            } footer: {
                Text("settings.orderIsReflectedInRecordInput")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("settings.fieldOrder")
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
                            Text(LocalizedStringKey(section.title))
                        }
                    }
                }
                .onMove { from, to in
                    settings.statSectionOrder.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text("statistics.displayOrder")
            } footer: {
                Text("stat.orderIsReflectedInStatisticsView")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("statistics.settings")
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
                Section("goal.values") {
                    goalDialRow(title: "metric.systolic.long", value: $settings.goalBpHi,      spec: MeasureRange.bpHi,      recordVal: latestBpHi,   unit: "unit.mmHg", stepperStep: 10, color: .red)
                    goalDialRow(title: "metric.diastolic.long", value: $settings.goalBpLo,      spec: MeasureRange.bpLo,      recordVal: latestBpLo,   unit: "unit.mmHg", stepperStep: 5,  color: .blue)
                    goalDialRow(title: "metric.pulsePressure",             value: $settings.goalBpPp,      spec: MeasureRange.bpPp,      recordVal: latestBpPp,   unit: "unit.mmHg", stepperStep: 5,  color: .orange)
                    goalDialRow(title: "metric.heartRate",           value: $settings.goalPulse,     spec: MeasureRange.pulse,     recordVal: latestPulse,  unit: "unit.bpm",  stepperStep: 5,  color: .orange)
                    goalDialRow(title: "metric.weight",             value: $settings.goalWeight,    spec: MeasureRange.weight,    recordVal: latestWeight, unit: "unit.kg",   stepperStep: 10, decimals: 1, color: .indigo)
                    goalDialRow(title: "metric.bmi",              value: $settings.goalBMI,       spec: MeasureRange.bmi,       recordVal: latestBMI,    unit: "",     stepperStep: 5,  decimals: 1, color: .cyan)
                    goalDialRow(title: "metric.bodyTemp",             value: $settings.goalTemp,      spec: MeasureRange.temp,      recordVal: latestTemp,   unit: "unit.celsius",   stepperStep: 1,  decimals: 1, color: .pink)
                    goalDialRow(title: "metric.bodyFat",         value: $settings.goalBodyFat,   spec: MeasureRange.bodyFat,   recordVal: latestBodyFat,unit: "%",    stepperStep: 5,  decimals: 1, color: .purple)
                    goalDialRow(title: "metric.skeletalMuscle",         value: $settings.goalSkMuscle,  spec: MeasureRange.skMuscle,  recordVal: latestSkMuscle,unit: "%",   stepperStep: 5,  decimals: 1, color: .teal)
                }
            }
            .navigationTitle("goal.settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func goalDialRow(
        title: LocalizedStringKey,
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
                    Text(LocalizedStringKey(unit))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(color.opacity(0.7))
                } else {
                    Text("placeholder.none")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                }
                Toggle("", isOn: enabled)
                    .labelsHidden()
            }
            if enabled.wrappedValue {
                AZDialView(
                    value: value,
                    min: spec.min,
                    max: spec.max,
                    step: 1,
                    stepperStep: stepperStep,
                    decimals: decimals,
                    style: DialStyle.builtin(id: AppSettings.shared.dialStyle) ?? .shape,
                    tuning: AppSettings.shared.dialTuning
                )
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
            Section("health.permissions") {
                HStack {
                    Text("text.status")
                    Spacer()
                    Text(hkService.isAuthorized
                         ? "health.authorized"
                         : "health.unauthorized")
                        .foregroundStyle(hkService.isAuthorized ? Color.secondary : Color.orange)
                    Button("action.changePermission") {
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

            Section("health.syncDirection") {
                Picker("health.syncDirection",
                       selection: directionBinding) {
                    Text("health.direction.writeOnly")
                        .tag(HKSyncDirection.writeOnly)
                    Text("health.direction.readOnly")
                        .tag(HKSyncDirection.readOnly)
                    Text("health.direction.both")
                        .tag(HKSyncDirection.both)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("health.timing") {
                Picker("health.timing",
                       selection: timingBinding) {
                    Text("health.timing.auto")
                        .tag(HKSyncTiming.automatic)
                    Text("health.timing.manual")
                        .tag(HKSyncTiming.manual)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                Text("metric.syncedSystolicDiastolicBpHeartRate")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("health.thisAppCannotModifyOrDelete")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("health.integration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hkService.checkAuthorization() }
        .onChange(of: settings.hkDirection) { _, _ in updateNeedsAutoImport() }
        .onChange(of: settings.hkTiming)    { _, _ in updateNeedsAutoImport() }
        .alert(
            "health.changePermission",
            isPresented: $showGuideAlert
        ) {
            Button("health.open") {
                if let url = URL(string: "x-apple-health://") { openURL(url) }
            }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("health.tapTheIconAtTheTop")
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
                        Text("app.name")
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

            Section("text.support") {
                Link(
                    "app.website",
                    destination: URL(string: "https://azukid.com")!
                )
                Link(
                    "action.reviewAppStore",
                    destination: URL(string: "https://apps.apple.com/app/id\(AppConstants.productName)")!
                )
            }
        }
        .navigationTitle("app.about")
        .navigationBarTitleDisplayMode(.inline)
    }
}
