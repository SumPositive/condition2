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

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 期間ピッカー
                Picker("期間", selection: periodBinding) {
                    ForEach(GraphPeriod.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // JSH 血圧分布
                BpJshView(records: targetRecords)

                // JSH基準割合バー
                BpJshRatioView(records: targetRecords)

                // 区分別（DateOpt）平均値
                BpDateOptAverageView(records: targetRecords)

}
            .padding()
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
        guard !validRecords.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "Stat_JshDist_Title", defaultValue: "血圧分布"))
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

// MARK: - JSH基準割合バー

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
        guard total > 0 else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Stat_JshRatio_Title", defaultValue: "JSH基準割合"))
                    .font(.headline)
                    .padding(.horizontal)

                GeometryReader { geo in
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
        guard !data.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "Stat_DateOptAvg_Title", defaultValue: "区分別平均血圧"))
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
