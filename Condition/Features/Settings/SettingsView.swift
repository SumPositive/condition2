// SettingsView.swift
// 設定メイン画面（旧 SettingTVC 相当）

import SwiftUI
import SwiftData
import AZDial
import StoreKit
import UniformTypeIdentifiers
import WebKit

private enum RecordJSONExportStyle: Int, CaseIterable, Identifiable {
    case compact = 0
    case pretty = 1

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .compact: return "settings.exportFormat.compact"
        case .pretty:  return "settings.exportFormat.pretty"
        }
    }

    var jsonOptions: JSONSerialization.WritingOptions {
        switch self {
        case .compact:
            return [.sortedKeys]
        case .pretty:
            return [.prettyPrinted, .sortedKeys]
        }
    }
}

struct SettingsView: View {

    @Environment(\.modelContext) private var context
    @AppStorage("settings.shareExportFormat") private var exportFormatRaw = RecordJSONExportStyle.compact.rawValue
    @State private var settings = AppSettings.shared
    @State private var healthKit = HealthKitService.shared
    @State private var showHKSettings = false
    @State private var showSafari = false
    @State private var showDialSettings = false
    @State private var showImportPicker = false
    @State private var showPruneOldRecordsConfirmSheet = false
    @State private var alertItem: SettingsAlertItem?
    @State private var isWorking = false
    @State private var progressMessage = ""
    @State private var progressHint = ""

    private var aboutURL: URL {
        let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        let urlString = isJapanese
            ? "https://docs.azukid.com/jp/sumpo/Condition/condition.html"
            : "https://docs.azukid.com/en/sumpo/Condition/condition.html"
        var components = URLComponents(string: urlString)!
        components.queryItems = [
            URLQueryItem(name: "fontScale", value: webFontScaleValue)
        ]
        return components.url!
    }

    private var webFontScaleValue: String {
        // Web側のCSSで扱いやすい3段階へ変換する。
        switch settings.fontScale {
        case .standard:
            return "standard"
        case .large:
            return "large"
        case .xLarge:
            return "xLarge"
        case .system:
            return currentSystemWebFontScaleValue
        }
    }

    private var currentSystemWebFontScaleValue: String {
        // 自動設定では現在のiOS文字サイズをWeb用の3段階へ丸める。
        switch UIApplication.shared.preferredContentSizeCategory {
        case .extraSmall, .small, .medium, .large:
            return "standard"
        case .extraLarge, .extraExtraLarge, .extraExtraExtraLarge:
            return "large"
        default:
            return "xLarge"
        }
    }

    private var exportFormat: RecordJSONExportStyle {
        RecordJSONExportStyle(rawValue: exportFormatRaw) ?? .compact
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 記録
                Section("tab.records") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("settings.openNewRecordOnForeground", isOn: $settings.openNewRecordOnForeground)
                        if settings.userLevel == .beginner {
                            Text("settings.help.openNewRecordOnForeground")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(
                                    "health.integration",
                                    isOn: $settings.hkEnabled
                                )
                                .onChange(of: settings.hkEnabled) { _, enabled in
                                    if enabled {
                                        Task { await healthKit.requestAuthorization() }
                                        showHKSettings = true
                                        healthKit.needsAutoImport = true
                                    } else {
                                        healthKit.clearLastAutoImportAt()
                                    }
                                }

                                if settings.userLevel == .beginner {
                                    // 初心者向けに、削除が連携されない点を明示する。
                                    Text("health.integrationHelp")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
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
                        HStack(spacing: 8) {
                            Text("settings.userLevel")
                                .font(.subheadline)
                            Picker("settings.userLevel", selection: $settings.userLevel) {
                                ForEach(AppUserLevel.allCases) { level in
                                    Text(LocalizedStringKey(level.titleKey)).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        if settings.userLevel == .beginner {
                            Text("settings.help.userLevel")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("appearance.mode")
                            .font(.subheadline)
                        Picker("appearance.mode", selection: $settings.appearanceMode) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("settings.fontScale")
                                .font(.subheadline)
                            Picker("settings.fontScale", selection: $settings.fontScale) {
                                ForEach(AppFontScale.allCases) { scale in
                                    Text(LocalizedStringKey(scale.titleKey)).tag(scale)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        if settings.userLevel == .beginner {
                            Text("settings.help.fontScale")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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

                // MARK: - 共有
                Section("settings.panel.share") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            exportRecordsJSON()
                        } label: {
                            Label("settings.share.exportRecords", systemImage: "square.and.arrow.up")
                        }

                        if settings.userLevel != .beginner {
                            HStack(spacing: 8) {
                                Spacer(minLength: 40)
                                Text("settings.exportFormat.title")
                                    .font(.subheadline)
                                Picker("settings.exportFormat.title", selection: $exportFormatRaw) {
                                    ForEach(RecordJSONExportStyle.allCases) { style in
                                        Text(LocalizedStringKey(style.titleKey)).tag(style.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        if settings.userLevel == .beginner {
                            Text("settings.help.exportRecords")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showImportPicker = true
                        } label: {
                            Label("settings.share.importRecords", systemImage: "square.and.arrow.down")
                        }

                        if settings.userLevel == .beginner {
                            Text("settings.help.importRecords")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showPruneOldRecordsConfirmSheet = true
                        } label: {
                            Label("settings.share.pruneOldRecords", systemImage: "trash")
                        }

                        if settings.userLevel == .beginner {
                            Text("settings.help.pruneOldRecords")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
            .scrollIndicators(.hidden)
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
        .sheet(isPresented: $showPruneOldRecordsConfirmSheet) {
            PruneOldRecordsConfirmSheet {
                pruneOldRecords()
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importRecordsJSON(from: url)
            case .failure(let error):
                alertItem = .raw(title: String(localized: "settings.share.errorTitle"), message: error.localizedDescription)
            }
        }
        .alert(item: $alertItem) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .cancel(Text("action.ok"))
            )
        }
        .overlay {
            if isWorking {
                progressOverlay
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

    private func exportRecordsJSON() {
        Task { @MainActor in
            isWorking = true
            progressMessage = String(localized: "settings.share.exportPreparing")
            progressHint = String(localized: "settings.share.exportHint")
            await Task.yield()
            defer { isWorking = false }

            let descriptor = FetchDescriptor<BodyRecord>(
                predicate: #Predicate { $0.dateTime < bodyRecordGoalDate },
                sortBy: [SortDescriptor(\BodyRecord.dateTime)]
            )
            let records = (try? context.fetch(descriptor)) ?? []
        let data = makeExportJSON(records: records, style: exportFormat)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "Condition_\(formatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
                try data.write(to: url, options: Data.WritingOptions.atomic)
                progressMessage = String(localized: "settings.share.exportOpening")
                await Task.yield()
                presentShareSheet(url: url)
            } catch {
                alertItem = .raw(title: String(localized: "settings.share.errorTitle"), message: error.localizedDescription)
            }
        }
    }

    private func importRecordsJSON(from url: URL) {
        Task { @MainActor in
            isWorking = true
            progressMessage = String(localized: "settings.share.importPreparing")
            progressHint = String(localized: "settings.share.importHint")
            await Task.yield()
            defer { isWorking = false }

            let startedAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if startedAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let envelope = try decoder.decode(RecordImportEnvelope.self, from: data)
                let result = try mergeImportedRecords(envelope.records)
                alertItem = .raw(
                    title: String(localized: "settings.share.importDoneTitle"),
                    message: String(
                        format: String(localized: "settings.share.importDoneMessage"),
                        result.inserted,
                        result.updated
                    )
                )
            } catch {
                alertItem = .raw(title: String(localized: "settings.share.errorTitle"), message: error.localizedDescription)
            }
        }
    }

    private func pruneOldRecords() {
        Task { @MainActor in
            isWorking = true
            progressMessage = String(localized: "settings.share.prunePreparing")
            progressHint = String(localized: "settings.share.pruneHint")
            await Task.yield()
            defer { isWorking = false }

            let cutoff = Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? Date()
            let descriptor = FetchDescriptor<BodyRecord>(
                predicate: #Predicate { $0.dateTime < cutoff && $0.dateTime < bodyRecordGoalDate }
            )
            let targets = (try? context.fetch(descriptor)) ?? []

            for record in targets {
                context.delete(record)
            }

            do {
                try context.save()
                alertItem = .raw(
                    title: String(localized: "settings.share.pruneDoneTitle"),
                    message: String(format: String(localized: "settings.share.pruneDoneMessage"), targets.count)
                )
            } catch {
                alertItem = .raw(title: String(localized: "settings.share.errorTitle"), message: error.localizedDescription)
            }
        }
    }

    private func presentShareSheet(url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            alertItem = .raw(
                title: String(localized: "settings.share.errorTitle"),
                message: String(localized: "settings.share.presenterUnavailable")
            )
            try? FileManager.default.removeItem(at: url)
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        topVC.present(activityVC, animated: true)
    }

    private func makeExportJSON(records: [BodyRecord], style: RecordJSONExportStyle) -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]

        var result: [[String: Any]] = []
        for record in records {
            var object: [String: Any] = [
                "dateTime": iso.string(from: record.dateTime),
                "condition": NSLocalizedString(record.dateOpt.label, comment: ""),
                "conditionRaw": record.nDateOpt,
                "dataSourceRaw": record.nDataSource,
                "cautionFlag": record.bCaution,
                "memo1": record.sNote1,
                "memo2": record.sNote2,
                "device": record.sEquipment,
            ]
            if 0 < record.nBpHi_mmHg { object["bpSystolic"] = record.nBpHi_mmHg }
            if 0 < record.nBpLo_mmHg { object["bpDiastolic"] = record.nBpLo_mmHg }
            if 0 < record.nPulse_bpm { object["heartRate"] = record.nPulse_bpm }
            if 0 < record.nTemp_10c { object["bodyTemp"] = Double(record.nTemp_10c) / 10.0 }
            if 0 < record.nWeight_10Kg { object["weight"] = Double(record.nWeight_10Kg) / 10.0 }
            if 0 < record.nBodyFat_10p { object["bodyFat"] = Double(record.nBodyFat_10p) / 10.0 }
            if 0 < record.nSkMuscle_10p { object["skeletalMuscle"] = Double(record.nSkMuscle_10p) / 10.0 }
            result.append(object)
        }

        let envelope: [String: Any] = [
            "exportDate": iso.string(from: Date()),
            "records": result,
        ]

        return (try? JSONSerialization.data(withJSONObject: envelope, options: style.jsonOptions)) ?? Data()
    }

    private func mergeImportedRecords(_ importedRecords: [RecordImportRecord]) throws -> (inserted: Int, updated: Int) {
        let descriptor = FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.dateTime < bodyRecordGoalDate }
        )
        let existingRecords = try context.fetch(descriptor)
        var existingByDate: [Date: BodyRecord] = [:]
        for record in existingRecords {
            existingByDate[record.dateTime] = record
        }

        var inserted = 0
        var updated = 0
        for imported in importedRecords {
            guard let date = imported.parsedDate else { continue }
            let record: BodyRecord
            if let existing = existingByDate[date] {
                record = existing
                updated += 1
            } else {
                record = BodyRecord(dateTime: date, dateOpt: imported.dateOpt ?? .rest)
                context.insert(record)
                existingByDate[date] = record
                inserted += 1
            }

            record.dateTime = date
            record.dateOpt = imported.dateOpt ?? .rest
            record.dataSource = imported.dataSource ?? .appInput
            record.bCaution = imported.cautionFlag ?? false
            record.sNote1 = imported.memo1 ?? ""
            record.sNote2 = imported.memo2 ?? ""
            record.sEquipment = imported.device ?? ""
            record.nBpHi_mmHg = imported.bpSystolic ?? 0
            record.nBpLo_mmHg = imported.bpDiastolic ?? 0
            record.nPulse_bpm = imported.heartRate ?? 0
            record.nTemp_10c = imported.bodyTemp.map { Int(($0 * 10).rounded()) } ?? 0
            record.nWeight_10Kg = imported.weight.map { Int(($0 * 10).rounded()) } ?? 0
            record.nBodyFat_10p = imported.bodyFat.map { Int(($0 * 10).rounded()) } ?? 0
            record.nSkMuscle_10p = imported.skeletalMuscle.map { Int(($0 * 10).rounded()) } ?? 0
        }

        try context.save()
        return (inserted, updated)
    }

    private var progressOverlay: some View {
        ZStack {
            // 入出力処理中は背面操作を受け付けない
            Color.black.opacity(0.24)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                Text(progressMessage)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(progressHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
        }
    }

}

private extension SettingsView {
    struct SettingsAlertItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String

        static func raw(title: String, message: String) -> SettingsAlertItem {
            SettingsAlertItem(title: title, message: message)
        }
    }
}

private struct RecordImportEnvelope: Decodable {
    let records: [RecordImportRecord]
}

private struct RecordImportRecord: Decodable {
    let dateTime: String
    let condition: String?
    let conditionRaw: Int?
    let dataSourceRaw: Int?
    let cautionFlag: Bool?
    let memo1: String?
    let memo2: String?
    let device: String?
    let bpSystolic: Int?
    let bpDiastolic: Int?
    let heartRate: Int?
    let bodyTemp: Double?
    let weight: Double?
    let bodyFat: Double?
    let skeletalMuscle: Double?

    var parsedDate: Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return iso.date(from: dateTime)
    }

    var dateOpt: DateOpt? {
        if let conditionRaw {
            return DateOpt(rawValue: conditionRaw)
        }
        guard let condition else { return nil }
        if let exact = DateOpt.allCases.first(where: { $0.label == condition }) {
            return exact
        }
        return DateOpt.allCases.first {
            NSLocalizedString($0.label, comment: "") == condition
        }
    }

    var dataSource: RecordDataSource? {
        guard let dataSourceRaw else { return nil }
        return RecordDataSource(rawValue: dataSourceRaw)
    }
}

// MARK: - 古い記録整理の確認シート

private struct PruneOldRecordsConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("settings.share.pruneConfirmTitle")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)

                    Text("settings.share.pruneConfirmMessage")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 14) {
                        Button(role: .destructive) {
                            dismiss()
                            onConfirm()
                        } label: {
                            Text("action.delete")
                        }
                        .buttonStyle(.bordered)

                        Button("action.cancel") {
                            dismiss()
                        }
                        .font(.title3.weight(.bold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
        let closeImage = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(scale: .large)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: closeImage,
            style: .plain,
            target: self,
            action: #selector(doneTapped)
        )

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
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        let content = NavigationView {
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
        if settings.fontScale.followsSystem {
            content
        } else {
            content.dynamicTypeSize(settings.fontScale.dynamicTypeSize)
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
        .scrollIndicators(.hidden)
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
        .scrollIndicators(.hidden)
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
        .scrollIndicators(.hidden)
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
        .scrollIndicators(.hidden)
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
            .scrollIndicators(.hidden)
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

    private var importStartDate: Date {
        let now = Date()
        let cal = Calendar.current
        if hkService.lastAutoImportAt == nil {
            return cal.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 24 * 3600)
        }
        return cal.date(byAdding: .day, value: -15, to: now) ?? now.addingTimeInterval(-15 * 24 * 3600)
    }

    private var directionHelpKey: String {
        switch directionBinding.wrappedValue {
        case .writeOnly:
            return "health.writeOnlyHelp"
        case .readOnly:
            return "health.readOnlyHelp"
        case .both:
            return "health.bothHelp"
        }
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

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("health.writableFields")
                        Spacer()
                        Text(hkService.authorizedShareFieldsText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("health.writableFields")
                        Text(hkService.authorizedShareFieldsText)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if settings.userLevel == .beginner {
                    // 読み込み対象は HealthKit のプライバシー制限で個別取得できない。
                    Text("health.readableFieldsPrivacyHelp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

                if settings.userLevel == .beginner {
                    // 選択した連携方向ごとの動作を初心者向けに補足する。
                    Text(LocalizedStringKey(directionHelpKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("health.syncDetails") {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("health.importStartDate")
                        Spacer()
                        Text(importStartDate, format: .dateTime.year().month().day())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        resetImportDateButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("health.importStartDate")
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(importStartDate, format: .dateTime.year().month().day())
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Spacer()
                            resetImportDateButton
                        }
                    }
                }

                if settings.userLevel == .beginner {
                    // 読み込み範囲の自動短縮と、必要時の再読み込み方法を説明する。
                    Text("health.importStartDateHelp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Text("health.thisAppCannotModifyOrDelete")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollIndicators(.hidden)
        .navigationTitle("health.integration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hkService.checkAuthorization() }
        .onChange(of: settings.hkDirection) { _, _ in updateNeedsAutoImport() }
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
            (HKSyncDirection(rawValue: settings.hkDirection)?.canRead == true)
        if canImport { hkService.needsAutoImport = true }
    }

    private var resetImportDateButton: some View {
        Button("health.resetOneYear") {
            hkService.clearLastAutoImportAt()
            updateNeedsAutoImport()
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
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
        .scrollIndicators(.hidden)
        .navigationTitle("app.about")
        .navigationBarTitleDisplayMode(.inline)
    }
}
