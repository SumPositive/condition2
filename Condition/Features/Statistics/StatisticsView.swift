// StatisticsView.swift
// 統計画面（旧 StatisticsVC 相当）

import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {

    @Query(
        filter: #Predicate<BodyRecord> { $0.dateTime < bodyRecordGoalDate },
        sort: \BodyRecord.dateTime,
        order: .reverse
    )
    private var allRecords: [BodyRecord]

    private var settings: AppSettings { AppSettings.shared }
    @State private var showSettings = false

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
            .navigationTitle(String(localized: "Tab_Statistics", defaultValue: "統計"))
            .toolbar {
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
        }
    }

    @ViewBuilder
    private func statSectionView(_ section: StatSection) -> some View {
        switch section {
        case .bpJsh:          BpJshView(records: targetRecords)
        case .bpRatio:        BpJshRatioView(records: targetRecords)
        case .bpDateOptAvg:   BpDateOptAverageView(records: targetRecords)
        case .bp24h:          Bp24HChartView(records: targetRecords)
        case .weightSummary:  WeightSummaryView(records: targetRecords)
        case .weightWeekly:   WeightWeeklyChartView(records: targetRecords)
        case .tempSummary:    TempSummaryView(records: targetRecords)
        case .tempDateOptAvg: TempDateOptAverageView(records: targetRecords)
        case .tempHist:       TempHistogramView(records: targetRecords)
        }
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
                    .font(.headline)

                Grid(horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("").frame(width: 40)
                        Text(String(localized: "Stat_Avg", defaultValue: "平均")).font(.caption).foregroundStyle(.secondary)
                        if settings.statShowAvg {
                            Text("±SD").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text(String(localized: "Stat_BpHi", defaultValue: "上")).foregroundStyle(.red)
                        Text(String(format: "%.1f", hiAvg)).font(.title3.monospacedDigit())
                        if settings.statShowAvg {
                            Text(String(format: "%.1f", hiStd)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text(String(localized: "Stat_BpLo", defaultValue: "下")).foregroundStyle(.blue)
                        Text(String(format: "%.1f", loAvg)).font(.title3.monospacedDigit())
                        if settings.statShowAvg {
                            Text(String(format: "%.1f", loStd)).font(.caption).foregroundStyle(.secondary)
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

    @State private var showJSHInfo = false

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
    }

    var body: some View {
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "Stat_JshDist_Title", defaultValue: "血圧 分布"))
                        .font(.headline)
                    Spacer()
                    Button {
                        showJSHInfo = true
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "info.circle")
                            Text("JSH基準")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showJSHInfo, arrowEdge: .bottom) {
                        JSHStandardsPopover()
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
                .chartXScale(domain: 40...130)
                .chartYScale(domain: 70...210)
                .chartXAxis {
                    AxisMarks(values: [60, 80, 100, 120]) { value in
                        AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                if v == 120 {
                                    HStack(spacing: 2) {
                                        Text("\(v)").font(.caption2)
                                        Text("下").font(.caption2).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("\(v)").font(.caption2)
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
                                        Text("上").font(.caption2).foregroundStyle(.secondary)
                                        Text("\(v)").font(.caption2)
                                    }
                                } else {
                                    Text("\(v)").font(.caption2)
                                }
                            }
                        }
                    }
                }
                .frame(height: 330)
                .padding(.horizontal, 4)
                .overlay {
                    if validRecords.isEmpty {
                        Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                            .font(.subheadline)
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
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(opt.label)
                                .font(.caption2)
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
        let labels: [(name: String, color: Color, y: Int)] = [
            ("正常血圧",    Color(red: 0.20, green: 0.50, blue: 0.90),  95),
            ("正常高値",    Color(red: 0.25, green: 0.72, blue: 0.35), 125),
            ("高値血圧",    Color(white: 0.20), 135),
            ("高血圧I度",   Color(red: 1.00, green: 0.55, blue: 0.00), 150),
            ("高血圧II度",  Color(red: 0.95, green: 0.25, blue: 0.00), 170),
            ("高血圧III度", Color(red: 0.80, green: 0.00, blue: 0.00), 195),
        ]
        ForEach(labels, id: \.name) { label in
            PointMark(x: .value("", 41), y: .value("", label.y))
                .symbolSize(0)
                .annotation(position: .trailing, alignment: .leading, spacing: 3) {
                    Text(label.name)
                        .font(.system(size: 9))
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
                    .font(.caption.weight(.semibold))
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
                            .font(.subheadline)
                        Spacer()
                        Text(row.criteria)
                            .font(.caption.monospacedDigit())
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
        .presentationCompactAdaptation(.popover)
    }
}

// MARK: - 血圧 JSH基準割合バー

struct BpJshRatioView: View {
    let records: [BodyRecord]

    private static let jshCategories: [(name: String, color: Color)] = [
        ("正常血圧",    Color(red: 0.20, green: 0.50, blue: 0.90)),
        ("正常高値",    Color(red: 0.25, green: 0.72, blue: 0.35)),
        ("高値血圧",    Color(white: 0.55)),
        ("高血圧I度",   Color(red: 1.00, green: 0.55, blue: 0.00)),
        ("高血圧II度",  Color(red: 0.95, green: 0.25, blue: 0.00)),
        ("高血圧III度", Color(red: 0.80, green: 0.00, blue: 0.00)),
    ]

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
                    .font(.headline)
                    .padding(.horizontal)

                GeometryReader { geo in
                    if total > 0 {
                        HStack(spacing: 0) {
                            ForEach(Array(Self.jshCategories.enumerated()), id: \.offset) { i, cat in
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
                    ForEach(Array(Self.jshCategories.enumerated()), id: \.offset) { i, cat in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cat.color)
                                .frame(width: 10, height: 10)
                            Text(LocalizedStringKey(cat.name)).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(c[i] > 0
                                 ? String(format: "%.0f%%", Double(c[i]) / Double(total) * 100)
                                 : "-")
                                .font(.caption2.monospacedDigit())
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

// MARK: - 区分別（DateOpt）平均値

struct BpDateOptAverageView: View {
    let records: [BodyRecord]

    private struct OptAvg {
        let opt: DateOpt
        let hiAvg: Double
        let loAvg: Double
    }

    private let barMin = 40.0
    private let barMax = 200.0

    private var data: [OptAvg] {
        DateOpt.allCases.compactMap { opt in
            let filtered = records.filter {
                $0.nDateOpt == opt.rawValue && $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0
            }
            guard !filtered.isEmpty else { return nil }
            let hiAvg = Double(filtered.map { $0.nBpHi_mmHg }.reduce(0, +)) / Double(filtered.count)
            let loAvg = Double(filtered.map { $0.nBpLo_mmHg }.reduce(0, +)) / Double(filtered.count)
            return OptAvg(opt: opt, hiAvg: hiAvg, loAvg: loAvg)
        }
    }

    var body: some View {
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "Stat_DateOptAvg_Title", defaultValue: "血圧 区分別平均"))
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.red.opacity(0.8)).frame(width: 10, height: 10)
                            Text("上").font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.8)).frame(width: 10, height: 10)
                            Text("下").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 8) {
                    if data.isEmpty {
                        Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    ForEach(data, id: \.opt) { item in
                        HStack(alignment: .center, spacing: 8) {
                            Label(item.opt.label, systemImage: item.opt.icon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                                .lineLimit(1)

                            VStack(spacing: 3) {
                                barView(value: item.hiAvg, color: .red)
                                barView(value: item.loAvg, color: .blue)
                            }

                            VStack(spacing: 3) {
                                Text(String(format: "%.0f", item.hiAvg))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.red)
                                    .frame(height: 14)
                                Text(String(format: "%.0f", item.loAvg))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.blue)
                                    .frame(height: 14)
                            }
                            .frame(width: 28, alignment: .trailing)
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

    private func barView(value: Double, color: Color) -> some View {
        let ratio = CGFloat((value - barMin) / (barMax - barMin))
        return Color.secondary.opacity(0.1)
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.8))
                        .frame(width: max(4, geo.size.width * ratio))
                }
            }
    }
}

// MARK: - 血圧 24時間散布図（旧 statDispersal24Hour 相当）

struct Bp24HChartView: View {
    let records: [BodyRecord]

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Stat_24H_Title", defaultValue: "血圧 24時間分散"))
                .font(.headline)
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
            .chartXAxisLabel(String(localized: "Stat_Hour", defaultValue: "時刻"))
            .chartYAxisLabel(String(localized: "Stat_mmHg", defaultValue: "mmHg"))
            .frame(height: 220)
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
                .font(.headline)

            if values.isEmpty {
                Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("").frame(width: 32)
                        Text(String(localized: "Stat_Avg", defaultValue: "平均"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(localized: "Stat_Min", defaultValue: "最小"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(localized: "Stat_Max", defaultValue: "最大"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(localized: "Stat_Change", defaultValue: "変化"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("kg").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f", avg)).font(.title3.monospacedDigit())
                        Text(String(format: "%.1f", minVal)).font(.title3.monospacedDigit())
                        Text(String(format: "%.1f", maxVal)).font(.title3.monospacedDigit())
                        HStack(spacing: 2) {
                            Image(systemName: change > 0.05 ? "arrow.up" : change < -0.05 ? "arrow.down" : "minus")
                                .foregroundStyle(change > 0.05 ? .red : change < -0.05 ? .blue : .secondary)
                                .font(.caption)
                            Text(String(format: "%.1f", abs(change)))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(change > 0.05 ? .red : change < -0.05 ? .blue : .secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 体重 週次平均バーチャート

struct WeightWeeklyChartView: View {
    let records: [BodyRecord]

    private struct WeekAvg: Identifiable {
        let weekStart: Date
        let avg: Double
        var id: Date { weekStart }
    }

    private var weeklyData: [WeekAvg] {
        let cal = Calendar(identifier: .iso8601)
        var groups: [Date: [Double]] = [:]
        for r in records where r.nWeight_10Kg > 0 {
            guard let interval = cal.dateInterval(of: .weekOfYear, for: r.dateTime) else { continue }
            groups[interval.start, default: []].append(Double(r.nWeight_10Kg) / 10.0)
        }
        return groups
            .map { WeekAvg(weekStart: $0.key, avg: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Stat_WeightWeekly_Title", defaultValue: "体重 週次平均"))
                .font(.headline)
                .padding(.horizontal)

            let data = weeklyData
            if data.isEmpty {
                Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("週", item.weekStart, unit: .weekOfYear),
                        y: .value("kg", item.avg)
                    )
                    .foregroundStyle(Color.blue.opacity(0.7))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxisLabel("kg")
                .frame(height: 200)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
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
                .font(.headline)

            if values.isEmpty {
                Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("").frame(width: 32)
                        Text(String(localized: "Stat_Avg", defaultValue: "平均"))
                            .font(.caption).foregroundStyle(.secondary)
                        if settings.statShowAvg {
                            Text("±SD").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(String(localized: "Stat_Min", defaultValue: "最小"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(localized: "Stat_Max", defaultValue: "最大"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("°C").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.1f", avg)).font(.title3.monospacedDigit())
                        if settings.statShowAvg {
                            Text(String(format: "%.2f", sd)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(String(format: "%.1f", minVal)).font(.title3.monospacedDigit())
                        Text(String(format: "%.1f", maxVal)).font(.title3.monospacedDigit())
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 体温 区分別平均

struct TempDateOptAverageView: View {
    let records: [BodyRecord]

    private struct OptAvg: Identifiable {
        let opt: DateOpt
        let avg: Double
        var id: DateOpt { opt }
    }

    private let barMin = 35.0
    private let barMax = 38.5

    private var data: [OptAvg] {
        DateOpt.allCases.compactMap { opt in
            let filtered = records.filter { $0.nDateOpt == opt.rawValue && $0.nTemp_10c > 0 }
            guard !filtered.isEmpty else { return nil }
            let avg = Double(filtered.map { $0.nTemp_10c }.reduce(0, +)) / Double(filtered.count) / 10.0
            return OptAvg(opt: opt, avg: avg)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Stat_TempDateOptAvg_Title", defaultValue: "体温 区分別平均"))
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                if data.isEmpty {
                    Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                ForEach(data) { item in
                    HStack(alignment: .center, spacing: 8) {
                        Label(item.opt.label, systemImage: item.opt.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                            .lineLimit(1)
                        barView(value: item.avg, color: item.opt.color)
                        Text(String(format: "%.1f", item.avg))
                            .font(.caption2.monospacedDigit())
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func barView(value: Double, color: Color) -> some View {
        let ratio = CGFloat((value - barMin) / (barMax - barMin))
        return Color.secondary.opacity(0.1)
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.8))
                        .frame(width: max(4, geo.size.width * ratio))
                }
            }
    }
}

// MARK: - 体温分布ヒストグラム

struct TempHistogramView: View {
    let records: [BodyRecord]

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Stat_TempHist_Title", defaultValue: "体温 分布"))
                .font(.headline)
                .padding(.horizontal)
            if hasData {
                chartContent
            } else {
                Text(String(localized: "Stat_NoData", defaultValue: "期間内にデータがありません"))
                    .font(.subheadline)
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
            .chartXAxisLabel("°C")
            .chartYAxisLabel(String(localized: "Stat_Count", defaultValue: "件数"))
            .frame(height: 180)
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
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
