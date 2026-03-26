// StatisticsView.swift
// 統計画面（旧 StatisticsVC 相当）

import SwiftUI
import SwiftData
import Charts

// MARK: - チャート幅 Environment

struct ChartAvailableWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 390
}
extension EnvironmentValues {
    var chartAvailableWidth: CGFloat {
        get { self[ChartAvailableWidthKey.self] }
        set { self[ChartAvailableWidthKey.self] = newValue }
    }
}

/// 利用可能幅に応じてチャート高さを拡大する（幅が広いほど高さも増やす）
func adaptiveChartHeight(base: CGFloat, width: CGFloat) -> CGFloat {
    guard width > 390 else { return base }
    return base * (width / 390)
}

struct StatisticsView: View {

    @Query(
        filter: #Predicate<BodyRecord> { $0.dateTime < bodyRecordGoalDate },
        sort: \BodyRecord.dateTime,
        order: .reverse
    )
    private var allRecords: [BodyRecord]

    private var settings: AppSettings { AppSettings.shared }
    @State private var showSettings = false
    @State private var chartWidth: CGFloat = 390
    @State private var isExporting = false

    private var periodBinding: Binding<GraphPeriod> {
        Binding(
            get: { GraphPeriod(rawValue: settings.statDays) ?? .threeMonths },
            set: { settings.statDays = $0.rawValue }
        )
    }

    private var currentPeriod: GraphPeriod {
        GraphPeriod(rawValue: settings.statDays) ?? .threeMonths
    }

    private var targetRecords: [BodyRecord] {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -currentPeriod.rawValue,
            to: Date()
        ) ?? Date()
        return allRecords.filter { $0.dateTime >= cutoff }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allRecords.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Stat_Empty", defaultValue: "データがありません"),
                        systemImage: "chart.dots.scatter"
                    )
                } else {
                    scrollContent
                }
            }
            .overlay { if isExporting { exportingOverlay } }
            .navigationTitle(String(localized: "Tab_Statistics", defaultValue: "統計"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { @MainActor in
                            isExporting = true
                            defer { isExporting = false }
                            try? await Task.sleep(for: .milliseconds(50))
                            doExport()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(targetRecords.isEmpty || isExporting)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    StatSettingsView(isModal: true)
                }
            }
        }
    }

    private var visibleStatSections: [StatSection] {
        let hidden = Set(settings.statHiddenSections)
        return settings.statSectionOrder.compactMap { raw in
            guard !hidden.contains(raw) else { return nil }
            return StatSection(rawValue: raw)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("期間", selection: periodBinding) {
                    ForEach(GraphPeriod.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ForEach(visibleStatSections) { section in
                    statSectionView(section)
                }
            }
            .padding()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { chartWidth = $0 }
        }
        .environment(\.chartAvailableWidth, chartWidth)
    }

    @ViewBuilder
    private func statSectionView(_ section: StatSection) -> some View {
        switch section {
        case .bpJsh:          BpJshView(records: targetRecords)
        case .bpRatio:        BpJshRatioView(records: targetRecords)
        case .bpDateOptCorr:  BpDateOptCorrView(records: targetRecords)
        case .bp24h:          Bp24HChartView(records: targetRecords)
        case .weightSummary:  WeightSummaryView(records: targetRecords)
        case .tempSummary:    TempSummaryView(records: targetRecords)
        case .temp24h:        Temp24HChartView(records: targetRecords)
        case .tempHist:       TempHistogramView(records: targetRecords)
        }
    }

    // MARK: - PDF エクスポート

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                Text(String(localized: "Export_Generating", defaultValue: "PDF生成中..."))
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }


    private func doExport() {
        let pdfW = PDFPanelExporter.contentW
        let panels: [AnyView] = visibleStatSections.map { section in
            AnyView(
                statSectionView(section)
                    .environment(\.chartAvailableWidth, pdfW)
            )
        }

        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("yMd")
        let now = Date()
        let fromDate = Calendar.current.date(byAdding: .day, value: -currentPeriod.rawValue, to: now) ?? now
        let subtitle = currentPeriod.label + "  " + df.string(from: fromDate) + " 〜 " + df.string(from: now)
        let title = String(localized: "Tab_Statistics", defaultValue: "統計")

        let data = PDFPanelExporter.export(panels: panels, title: title, subtitle: subtitle)
        let tabName = String(localized: "Tab_Statistics", defaultValue: "統計")
        let dateTag = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f.string(from: Date()) }()
        guard let url = PDFPanelExporter.writeTempFile(name: "\(tabName)_\(dateTag).pdf", data: data) else { return }

        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        topVC.present(activityVC, animated: true)
    }

    private var statSummaryView: some View {
        let validBpRecords = targetRecords.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
        guard !validBpRecords.isEmpty else { return AnyView(EmptyView()) }

        let hiValues = validBpRecords.map { Double($0.nBpHi_mmHg) }
        let loValues = validBpRecords.map { Double($0.nBpLo_mmHg) }
        let hiAvg = hiValues.reduce(0, +) / Double(hiValues.count)
        let loAvg = loValues.reduce(0, +) / Double(loValues.count)
        let hiStd = standardDeviation(hiValues)
        let loStd = standardDeviation(loValues)

        return AnyView(
            VStack(spacing: 8) {
                Text(String(localized: "Stat_Summary", defaultValue: "血圧サマリー"))
                    .font(.title3)

                Grid(horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("").frame(width: 40)
                        Text(String(localized: "Stat_Avg", defaultValue: "平均")).font(.footnote).foregroundStyle(.secondary)
                        if settings.statShowAvg {
                            Text("±SD").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text(String(localized: "Stat_BpHi", defaultValue: "上")).foregroundStyle(.red)
                        Text(String(format: "%.1f", hiAvg)).font(.title2.monospacedDigit())
                        if settings.statShowAvg {
                            Text(String(format: "%.1f", hiStd)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text(String(localized: "Stat_BpLo", defaultValue: "下")).foregroundStyle(.blue)
                        Text(String(format: "%.1f", loAvg)).font(.title2.monospacedDigit())
                        if settings.statShowAvg {
                            Text(String(format: "%.1f", loStd)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let avg = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - avg, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }
}

// MARK: - JSH 血圧分布バー＋散布図

struct BpJshView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth
    @State private var showJSHInfo = false

    private var isJapanese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ja") ?? true
    }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
    }

    var body: some View {
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "Stat_JshDist_Title", defaultValue: "血圧 分布"))
                        .font(.title3)
                    Spacer()
                    Button {
                        showJSHInfo = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.title3)
                            Text(isJapanese ? "JSH基準" : "ESC/ESH 2018")
                                .font(.footnote)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showJSHInfo, arrowEdge: .bottom) {
                        if isJapanese {
                            JSHStandardsPopover()
                        } else {
                            ESHStandardsPopover()
                        }
                    }
                }
                .padding(.horizontal)

                // 散布図（上 vs 下、JSHゾーン背景＋カラードット）
                Chart {
                    // 上（収縮期）ゾーン帯：横方向
                    ForEach(bpHiZones, id: \.min) { z in
                        RectangleMark(
                            xStart: .value("", 40), xEnd: .value("", 130),
                            yStart: .value("", max(z.min, 70)),
                            yEnd:   .value("", min(z.max, 210))
                        )
                        .foregroundStyle(z.color)
                    }
                    // 下（拡張期）ゾーン帯：縦方向（上ゾーンより薄く重ねる）
                    ForEach(bpLoZones, id: \.min) { z in
                        RectangleMark(
                            xStart: .value("", max(z.min, 40)),
                            xEnd:   .value("", min(z.max, 130)),
                            yStart: .value("", 70), yEnd: .value("", 210)
                        )
                        .foregroundStyle(z.color.opacity(0.5))
                    }
                    // JSH境界ステップ線
                    jshBoundaryLines()
                    // ゾーンラベル（Y軸寄り）
                    jshZoneLabels()
                    // データ点
                    ForEach(validRecords) { r in
                        PointMark(
                            x: .value("下", r.nBpLo_mmHg),
                            y: .value("上", r.nBpHi_mmHg)
                        )
                        .foregroundStyle(DateOpt(rawValue: r.nDateOpt)?.color ?? .secondary)
                        .symbolSize(32)
                    }
                }
                .chartXScale(domain: 40...134)
                .chartYScale(domain: 70...210)
                .chartXAxis {
                    let narrow = UIScreen.main.bounds.width <= 375
                    let xValues: [Int] = narrow ? [60, 80, 100] : [60, 80, 100, 120]
                    AxisMarks(values: xValues) { value in
                        AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                let showLabel = v == 120 || (narrow && v == 100)
                                if showLabel {
                                    HStack(spacing: 2) {
                                        Text("\(v)").font(.caption)
                                        Text("下").font(.caption).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("\(v)").font(.caption)
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [80, 100, 120, 140, 160, 180, 200]) { value in
                        AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                if v == 200 {
                                    VStack(spacing: 0) {
                                        Text("上").font(.caption).foregroundStyle(.secondary)
                                        Text("\(v)").font(.caption)
                                    }
                                } else {
                                    Text("\(v)").font(.caption)
                                }
                            }
                        }
                    }
                }
                .frame(height: adaptiveChartHeight(base: 330, width: chartWidth))
                .padding(.horizontal, 4)
                .overlay {
                    if validRecords.isEmpty {
                        Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // 区分（DateOpt）凡例
                let cols = [GridItem(.fixed(90)), GridItem(.fixed(90)), GridItem(.fixed(90))]
                LazyVGrid(columns: cols, alignment: .center, spacing: 4) {
                    ForEach(DateOpt.allCases, id: \.self) { opt in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(opt.color)
                                .frame(width: 8, height: 8)
                            Image(systemName: opt.icon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(opt.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }

    private func dateOptColor(_ opt: DateOpt) -> Color { opt.color }

    @ChartContentBuilder
    private func jshBoundaryLines() -> some ChartContent {
        let bc = Color.secondary.opacity(0.45)
        let bs = StrokeStyle(lineWidth: 1)
        // 正常血圧 / 正常高値
        RuleMark(xStart: .value("", 40), xEnd: .value("", 80), y: .value("", 120))
            .foregroundStyle(bc).lineStyle(bs)
        // 正常高値 / 高値血圧（+ 正常血圧右縁）
        RuleMark(xStart: .value("", 40), xEnd: .value("", 80), y: .value("", 130))
            .foregroundStyle(bc).lineStyle(bs)
        RuleMark(x: .value("", 80), yStart: .value("", 70), yEnd: .value("", 130))
            .foregroundStyle(bc).lineStyle(bs)
        // 高値血圧 / 高血圧I度
        RuleMark(xStart: .value("", 40), xEnd: .value("", 90), y: .value("", 140))
            .foregroundStyle(bc).lineStyle(bs)
        RuleMark(x: .value("", 90), yStart: .value("", 70), yEnd: .value("", 140))
            .foregroundStyle(bc).lineStyle(bs)
        // 高血圧I度 / 高血圧II度
        RuleMark(xStart: .value("", 40), xEnd: .value("", 100), y: .value("", 160))
            .foregroundStyle(bc).lineStyle(bs)
        RuleMark(x: .value("", 100), yStart: .value("", 70), yEnd: .value("", 160))
            .foregroundStyle(bc).lineStyle(bs)
        // 高血圧II度 / 高血圧III度
        RuleMark(xStart: .value("", 40), xEnd: .value("", 110), y: .value("", 180))
            .foregroundStyle(bc).lineStyle(bs)
        RuleMark(x: .value("", 110), yStart: .value("", 70), yEnd: .value("", 180))
            .foregroundStyle(bc).lineStyle(bs)
    }

    // 各ゾーン中央にラベルを表示（Y軸寄り）
    @ChartContentBuilder
    private func jshZoneLabels() -> some ChartContent {
        let names: [String] = isJapanese
            ? ["正常血圧", "正常高値", "高値血圧", "高血圧I度", "高血圧II度", "高血圧III度"]
            : ["Optimal",  "Normal",  "High Normal", "Grade 1", "Grade 2",  "Grade 3"]
        let labels: [(name: String, color: Color, y: Int)] = [
            (names[0], Color(red: 0.20, green: 0.50, blue: 0.90),  95),
            (names[1], Color(red: 0.25, green: 0.72, blue: 0.35), 125),
            (names[2], Color(white: 0.20), 135),
            (names[3], Color(red: 1.00, green: 0.55, blue: 0.00), 150),
            (names[4], Color(red: 0.95, green: 0.25, blue: 0.00), 170),
            (names[5], Color(red: 0.80, green: 0.00, blue: 0.00), 195),
        ]
        ForEach(labels, id: \.name) { label in
            PointMark(x: .value("", 41), y: .value("", label.y))
                .symbolSize(0)
                .annotation(position: .trailing, alignment: .leading, spacing: 3) {
                    Text(label.name)
                        .font(.system(size: 10))
                        .foregroundStyle(label.color.opacity(0.85))
                }
        }
    }
}

// MARK: - JSH基準ポップアップ

private struct JSHStandardsPopover: View {
    private struct Row {
        let name: String
        let color: Color
        let criteria: String
    }
    private let rows: [Row] = [
        Row(name: "高血圧III度", color: Color(red: 0.80, green: 0.00, blue: 0.00), criteria: "上 ≥ 180 または 下 ≥ 110"),
        Row(name: "高血圧II度",  color: Color(red: 0.95, green: 0.25, blue: 0.00), criteria: "上 160-179 または 下 100-109"),
        Row(name: "高血圧I度",   color: Color(red: 1.00, green: 0.55, blue: 0.00), criteria: "上 140-159 または 下 90-99"),
        Row(name: "高値血圧",    color: Color(white: 0.55),                         criteria: "上 130-139 または 下 80-89"),
        Row(name: "正常高値",    color: Color(red: 0.25, green: 0.72, blue: 0.35), criteria: "上 120-129 かつ 下 < 80"),
        Row(name: "正常血圧",    color: Color(red: 0.20, green: 0.50, blue: 0.90), criteria: "上 < 120 かつ 下 < 80"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("JSH血圧分類基準（2019）")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.element.name) { index, row in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(row.color.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5)
                            )
                            .frame(width: 18, height: 18)
                        Text(row.name)
                            .font(.callout)
                        Spacer()
                        Text(row.criteria)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
                Spacer(minLength: 14)
            }
        }
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.sheet)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - ESC/ESH 2018 基準ポップアップ（en 用）

private struct ESHStandardsPopover: View {
    private struct Row {
        let name: String
        let color: Color
        let criteria: String
    }
    private let rows: [Row] = [
        Row(name: "Grade 3 HT",  color: Color(red: 0.80, green: 0.00, blue: 0.00), criteria: "Systolic ≥180 or Diastolic ≥110"),
        Row(name: "Grade 2 HT",  color: Color(red: 0.95, green: 0.25, blue: 0.00), criteria: "Systolic 160–179 or Diastolic 100–109"),
        Row(name: "Grade 1 HT",  color: Color(red: 1.00, green: 0.55, blue: 0.00), criteria: "Systolic 140–159 or Diastolic 90–99"),
        Row(name: "High Normal", color: Color(white: 0.55),                          criteria: "Systolic 130–139 or Diastolic 80–89"),
        Row(name: "Normal",      color: Color(red: 0.25, green: 0.72, blue: 0.35),  criteria: "Systolic 120–129 and Diastolic <80"),
        Row(name: "Optimal",     color: Color(red: 0.20, green: 0.50, blue: 0.90),  criteria: "Systolic <120 and Diastolic <80"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("ESC/ESH Hypertension Guidelines (2018)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.element.name) { index, row in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(row.color.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5)
                            )
                            .frame(width: 18, height: 18)
                        Text(row.name)
                            .font(.callout)
                        Spacer()
                        Text(row.criteria)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    if index < rows.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
                Spacer(minLength: 14)
            }
        }
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.sheet)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 血圧 JSH基準割合バー

struct BpJshRatioView: View {
    let records: [BodyRecord]

    private var isJapanese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ja") ?? true
    }

    private static let categoryColors: [Color] = [
        Color(red: 0.20, green: 0.50, blue: 0.90),
        Color(red: 0.25, green: 0.72, blue: 0.35),
        Color(white: 0.55),
        Color(red: 1.00, green: 0.55, blue: 0.00),
        Color(red: 0.95, green: 0.25, blue: 0.00),
        Color(red: 0.80, green: 0.00, blue: 0.00),
    ]

    private var categoryNames: [(name: String, color: Color)] {
        let names: [String] = isJapanese
            ? ["正常血圧", "正常高値", "高値血圧", "高血圧I度", "高血圧II度", "高血圧III度"]
            : ["Optimal",  "Normal",  "High Normal", "Grade 1", "Grade 2",  "Grade 3"]
        return zip(names, Self.categoryColors).map { ($0, $1) }
    }

    private func jshIndex(hi: Int, lo: Int) -> Int {
        if hi >= 180 || lo >= 110 { return 5 }
        if hi >= 160 || lo >= 100 { return 4 }
        if hi >= 140 || lo >= 90  { return 3 }
        if hi >= 130 || lo >= 80  { return 2 }
        if hi >= 120              { return 1 }
        return 0
    }

    private var counts: [Int] {
        let valid = records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
        var c = [Int](repeating: 0, count: 6)
        for r in valid { c[jshIndex(hi: r.nBpHi_mmHg, lo: r.nBpLo_mmHg)] += 1 }
        return c
    }

    var body: some View {
        let c = counts
        let total = c.reduce(0, +)

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Stat_JshRatio_Title", defaultValue: "血圧 JSH基準割合"))
                    .font(.title3)
                    .padding(.horizontal)

                GeometryReader { geo in
                    if total > 0 {
                        HStack(spacing: 0) {
                            ForEach(Array(categoryNames.enumerated()), id: \.offset) { i, cat in
                                if c[i] > 0 {
                                    Rectangle()
                                        .fill(cat.color)
                                        .frame(width: geo.size.width * CGFloat(c[i]) / CGFloat(total))
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                    }
                }
                .frame(height: 28)
                .padding(.horizontal)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 4
                ) {
                    ForEach(Array(categoryNames.enumerated()), id: \.offset) { i, cat in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cat.color)
                                .frame(width: 10, height: 10)
                            Text(LocalizedStringKey(cat.name)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(c[i] > 0
                                 ? String(format: "%.0f%%", Double(c[i]) / Double(total) * 100)
                                 : "-")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(c[i] > 0 ? .primary : .tertiary)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }
}

// MARK: - 血圧・区分 相関（ストリッププロット）

struct BpDateOptCorrView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth

    private struct BpPoint: Identifiable {
        let id: Int
        let category: String
        let value: Int
        let isHi: Bool
    }

    private struct CatMean: Identifiable {
        let id: String
        let category: String
        let hiAvg: Double
        let loAvg: Double
    }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
    }

    private var points: [BpPoint] {
        var result: [BpPoint] = []
        var idx = 0
        for r in validRecords {
            let cat = DateOpt(rawValue: r.nDateOpt)?.label ?? "その他"
            result.append(BpPoint(id: idx,     category: cat, value: r.nBpHi_mmHg, isHi: true))
            result.append(BpPoint(id: idx + 1, category: cat, value: r.nBpLo_mmHg, isHi: false))
            idx += 2
        }
        return result
    }

    private var means: [CatMean] {
        DateOpt.allCases.compactMap { opt in
            let filtered = validRecords.filter { $0.nDateOpt == opt.rawValue }
            guard !filtered.isEmpty else { return nil }
            let hi = Double(filtered.map { $0.nBpHi_mmHg }.reduce(0, +)) / Double(filtered.count)
            let lo = Double(filtered.map { $0.nBpLo_mmHg }.reduce(0, +)) / Double(filtered.count)
            return CatMean(id: opt.label, category: opt.label, hiAvg: hi, loAvg: lo)
        }
    }

    private var categoryOrder: [String] {
        DateOpt.allCases.map { $0.label }
    }

    private var yDomain: ClosedRange<Int> {
        guard !points.isEmpty else { return 50...180 }
        let vals = points.map { $0.value }
        let lower = max(30, (vals.min()! / 10) * 10 - 10)
        let upper = min(260, ((vals.max()! + 9) / 10) * 10 + 10)
        return lower...upper
    }

    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Stat_BpDateOptCorr_Title", defaultValue: "血圧・区分 相関"))
                    .font(.title3)
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                    BpDateOptCorrInfoPopover()
                }
                Spacer()
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red.opacity(0.8)).frame(width: 8, height: 8)
                        Text("上").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.blue.opacity(0.8)).frame(width: 8, height: 8)
                        Text("下").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)

            if points.isEmpty {
                Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                chartContent
                Text(String(localized: "Stat_DiamondMean", defaultValue: "◆ = 区分平均"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing)
            }
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chartContent: some View {
        let ms = means
        let order = categoryOrder
        return Chart {
            ForEach(points) { pt in
                PointMark(
                    x: .value("区分", pt.category),
                    y: .value("mmHg", pt.value)
                )
                .symbol(.circle)
                .symbolSize(16)
                .foregroundStyle(pt.isHi ? Color.red.opacity(0.35) : Color.blue.opacity(0.35))
            }
            ForEach(ms) { m in
                PointMark(
                    x: .value("区分", m.category),
                    y: .value("mmHg", m.hiAvg)
                )
                .symbol(.diamond)
                .symbolSize(80)
                .foregroundStyle(Color.red.opacity(0.9))

                PointMark(
                    x: .value("区分", m.category),
                    y: .value("mmHg", m.loAvg)
                )
                .symbol(.diamond)
                .symbolSize(80)
                .foregroundStyle(Color.blue.opacity(0.9))
            }
        }
        .chartXScale(domain: order)
        .chartYScale(domain: yDomain)
        .chartYAxisLabel("mmHg")
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let s = value.as(String.self) {
                        Text(s).font(.system(size: 10))
                    }
                }
            }
        }
        .frame(height: adaptiveChartHeight(base: 240, width: chartWidth))
        .padding(.horizontal)
    }
}

// MARK: - 血圧・区分 相関 説明ポップアップ

private struct BpDateOptCorrInfoPopover: View {
    private var isJapanese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ja") ?? true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(isJapanese ? "相関図の見方" : "How to Read This Chart")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        isJapanese
                            ? "各区分（起床・安静など）ごとに血圧値を縦に並べて表示します"
                            : "Blood pressure values are plotted vertically for each category (e.g. morning, rest)",
                        systemImage: "circle.fill"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    Label(
                        isJapanese ? "小さな円が個別の測定値です"
                                   : "Small circles represent individual measurements",
                        systemImage: "circle"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    Label(
                        isJapanese ? "ダイヤモンド◆がその区分の平均値です"
                                   : "Diamond ◆ marks the category average",
                        systemImage: "diamond.fill"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    Label(
                        isJapanese
                            ? "区分間で◆の高さを比べると、時間帯による血圧の傾向がわかります"
                            : "Comparing ◆ heights across categories reveals time-of-day BP patterns",
                        systemImage: "arrow.left.arrow.right"
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.red.opacity(0.8)).frame(width: 10, height: 10)
                        Text(isJapanese ? "赤 = 上（収縮期血圧）" : "Red = Systolic (Upper)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(Color.blue.opacity(0.8)).frame(width: 10, height: 10)
                        Text(isJapanese ? "青 = 下（拡張期血圧）" : "Blue = Diastolic (Lower)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - 血圧 24時間散布図（旧 statDispersal24Hour 相当）

struct Bp24HChartView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth
    private var settings: AppSettings { AppSettings.shared }

    private var validRecords: [(hour: Int, hi: Int, lo: Int)] {
        let cal = Calendar(identifier: .gregorian)
        return records
            .filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
            .map { r in
                let h = cal.component(.hour, from: r.dateTime)
                return (hour: h, hi: r.nBpHi_mmHg, lo: r.nBpLo_mmHg)
            }
    }

    /// データに合わせた Y 軸範囲（10mmHg グリッドに揃え、上下にパディング）
    private var yDomain: ClosedRange<Int> {
        guard !validRecords.isEmpty else { return 50...180 }
        let allValues = validRecords.flatMap { [$0.lo, $0.hi] }
        let dataMin = allValues.min()!
        let dataMax = allValues.max()!
        let lower = max(30, (dataMin / 10) * 10 - 10)
        let upper = min(260, ((dataMax + 9) / 10) * 10 + 10)
        return lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Stat_24H_Title", defaultValue: "血圧 24時間分布"))
                .font(.title3)
                .padding(.horizontal)

            Chart {
                ForEach(Array(validRecords.enumerated()), id: \.offset) { _, item in
                    PointMark(
                        x: .value("時刻", item.hour),
                        y: .value("上血圧", item.hi)
                    )
                    .foregroundStyle(.red.opacity(0.6))
                    .symbolSize(35)

                    PointMark(
                        x: .value("時刻", item.hour),
                        y: .value("下血圧", item.lo)
                    )
                    .foregroundStyle(.blue.opacity(0.6))
                    .symbolSize(35)
                }

                // 時刻ライン（設定時刻に垂直線）
                if settings.statShow24HLine {
                    RuleMark(x: .value("起床", settings.wakeHour))
                        .foregroundStyle(.green.opacity(0.4))
                    RuleMark(x: .value("就寝", settings.sleepHour))
                        .foregroundStyle(.purple.opacity(0.4))
                }
            }
            .chartXScale(domain: 0...23)
            .chartYScale(domain: yDomain)
            .chartXAxisLabel(String(localized: "Stat_Hour", defaultValue: "時刻"))
            .chartYAxisLabel(String(localized: "Stat_mmHg", defaultValue: "mmHg"))
            .frame(height: adaptiveChartHeight(base: 220, width: chartWidth))
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 体重 サマリー

struct WeightSummaryView: View {
    let records: [BodyRecord]

    private var weightRecords: [BodyRecord] {
        records.filter { $0.nWeight_10Kg > 0 }.sorted { $0.dateTime < $1.dateTime }
    }

    var body: some View {
        let recs = weightRecords
        let values = recs.map { Double($0.nWeight_10Kg) / 10.0 }
        let avg = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
        let minVal = values.min() ?? 0.0
        let maxVal = values.max() ?? 0.0
        let change = values.count >= 2 ? values.last! - values.first! : 0.0

        return VStack(spacing: 8) {
            Text(String(localized: "Stat_WeightSummary_Title", defaultValue: "体重 サマリー"))
                .font(.title3)

            if values.isEmpty {
                Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text(String(localized: "Stat_Avg", defaultValue: "平均"))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(String(localized: "Stat_Min", defaultValue: "最小"))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(String(localized: "Stat_Max", defaultValue: "最大"))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(String(localized: "Stat_Change", defaultValue: "変化"))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("").frame(width: 24)
                    }
                    GridRow {
                        Text(String(format: "%.1f", avg)).font(.title2.monospacedDigit())
                        Text(String(format: "%.1f", minVal)).font(.title2.monospacedDigit())
                        Text(String(format: "%.1f", maxVal)).font(.title2.monospacedDigit())
                        HStack(spacing: 2) {
                            Image(systemName: change > 0.05 ? "arrow.up" : change < -0.05 ? "arrow.down" : "minus")
                                .foregroundStyle(change > 0.05 ? .red : change < -0.05 ? .blue : .secondary)
                                .font(.footnote)
                            Text(String(format: "%.1f", abs(change)))
                                .font(.title2.monospacedDigit())
                                .foregroundStyle(change > 0.05 ? .red : change < -0.05 ? .blue : .secondary)
                        }
                        Text("kg").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 体温 サマリー

struct TempSummaryView: View {
    let records: [BodyRecord]

    private var settings: AppSettings { AppSettings.shared }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let avg = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - avg, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }

    var body: some View {
        let values = records.filter { $0.nTemp_10c > 0 }.map { Double($0.nTemp_10c) / 10.0 }
        let avg = values.isEmpty ? 0.0 : values.reduce(0, +) / Double(values.count)
        let sd = standardDeviation(values)
        let minVal = values.min() ?? 0.0
        let maxVal = values.max() ?? 0.0

        return VStack(spacing: 8) {
            Text(String(localized: "Stat_TempSummary_Title", defaultValue: "体温 サマリー"))
                .font(.title3)

            if values.isEmpty {
                Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text(String(localized: "Stat_Avg", defaultValue: "平均"))
                            .font(.footnote).foregroundStyle(.secondary)
                        if settings.statShowAvg {
                            Text("±SD").font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(String(localized: "Stat_Min", defaultValue: "最小"))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(String(localized: "Stat_Max", defaultValue: "最大"))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("").frame(width: 24)
                    }
                    GridRow {
                        Text(String(format: "%.1f", avg)).font(.title2.monospacedDigit())
                        if settings.statShowAvg {
                            Text(String(format: "%.2f", sd)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(String(format: "%.1f", minVal)).font(.title2.monospacedDigit())
                        Text(String(format: "%.1f", maxVal)).font(.title2.monospacedDigit())
                        Text("°C").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 体温 24時間分布

struct Temp24HChartView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth

    private var validRecords: [(hour: Int, temp: Double)] {
        let cal = Calendar(identifier: .gregorian)
        return records
            .filter { $0.nTemp_10c > 0 }
            .map { r in
                let h = cal.component(.hour, from: r.dateTime)
                return (hour: h, temp: Double(r.nTemp_10c) / 10.0)
            }
    }

    /// データに合わせた Y 軸範囲（0.5℃ グリッドに揃え、上下にパディング）
    private var yDomain: ClosedRange<Double> {
        guard !validRecords.isEmpty else { return 35.5...37.5 }
        let temps = validRecords.map { $0.temp }
        let dataMin = temps.min()!
        let dataMax = temps.max()!
        let lower = (dataMin * 2).rounded(.down) / 2 - 0.5
        let upper = (dataMax * 2).rounded(.up)   / 2 + 0.5
        return max(34.0, lower)...min(42.0, upper)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Stat_Temp24H_Title", defaultValue: "体温 24時間分布"))
                .font(.title3)
                .padding(.horizontal)

            Chart {
                ForEach(Array(validRecords.enumerated()), id: \.offset) { _, item in
                    PointMark(
                        x: .value("時刻", item.hour),
                        y: .value("体温", item.temp)
                    )
                    .foregroundStyle(Color.pink.opacity(0.6))
                    .symbolSize(35)
                }
            }
            .chartXScale(domain: 0...23)
            .chartYScale(domain: yDomain)
            .chartXAxisLabel(String(localized: "Stat_Hour", defaultValue: "時刻"))
            .chartYAxisLabel(String(localized: "Stat_Celsius", defaultValue: "°C"))
            .frame(height: adaptiveChartHeight(base: 220, width: chartWidth))
            .padding(.horizontal)
            .overlay {
                if validRecords.isEmpty {
                    Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 体温分布ヒストグラム

struct TempHistogramView: View {
    let records: [BodyRecord]

    @Environment(\.chartAvailableWidth) private var chartWidth

    private struct Bin: Identifiable {
        let lower: Double
        let count: Int
        var id: Double { lower }
        var color: Color {
            if lower < 36.0 { return .blue }
            if lower < 37.0 { return .green }
            if lower < 37.5 { return Color(red: 1.0, green: 0.7, blue: 0.0) }
            return .orange
        }
    }

    private var bins: [Bin] {
        let values = records.compactMap { $0.nTemp_10c > 0 ? $0.nTemp_10c : nil }
        return stride(from: 350, to: 410, by: 2).map { lo in
            Bin(lower: Double(lo) / 10.0, count: values.filter { $0 >= lo && $0 < lo + 2 }.count)
        }
    }

    private var hasData: Bool { bins.contains { $0.count > 0 } }

    private var xDomain: ClosedRange<Double> {
        let active = bins.filter { $0.count > 0 }.map(\.lower)
        guard let lo = active.min(), let hi = active.max() else { return 35.0...38.0 }
        // ビン幅 0.2 の 2 本分マージンを加え、0.5 刻みで丸める
        let domLo = (((lo - 0.4) * 2).rounded(.down) / 2)
        let domHi = (((hi + 0.6) * 2).rounded(.up)   / 2)
        return domLo...domHi
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Stat_TempHist_Title", defaultValue: "体温 分布"))
                .font(.title3)
                .padding(.horizontal)
            if hasData {
                chartContent
            } else {
                Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var chartContent: some View {
        VStack(spacing: 8) {
            Chart(bins) { bin in
                RectangleMark(
                    xStart: .value("temp", bin.lower),
                    xEnd: .value("temp", bin.lower + 0.2),
                    yStart: .value("count", 0),
                    yEnd: .value("count", bin.count)
                )
                .foregroundStyle(bin.color.opacity(0.8))
            }
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: 0.5)) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisTick()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.1f", v)).font(.caption)
                        }
                    }
                }
            }
            .chartXAxisLabel("°C")
            .chartYAxisLabel(String(localized: "Stat_Count", defaultValue: "件数"))
            .frame(height: adaptiveChartHeight(base: 180, width: chartWidth))
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.fixed(130)), GridItem(.fixed(130))], alignment: .center) {
                legendItem(color: .blue,
                           label: String(localized: "Stat_TempHist_Low",    defaultValue: "低体温 (<36°C)"))
                legendItem(color: .green,
                           label: String(localized: "Stat_TempHist_Normal", defaultValue: "正常 (36–37°C)"))
                legendItem(color: Color(red: 1.0, green: 0.7, blue: 0.0),
                           label: String(localized: "Stat_TempHist_Low37",  defaultValue: "微熱 (37–37.5°C)"))
                legendItem(color: .orange,
                           label: String(localized: "Stat_TempHist_Fever",  defaultValue: "発熱 (≥37.5°C)"))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.8)).frame(width: 10, height: 10)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
