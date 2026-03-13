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
                StatSettingsView()
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

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
    }

    var body: some View {
        guard !validRecords.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Stat_JshDist_Title", defaultValue: "血圧分布（JSH基準）"))
                    .font(.headline)
                    .padding(.horizontal)

                // JSH 区分凡例
                let jshLegend: [(name: String, color: Color)] = [
                    ("正常血圧",   Color(red: 0.05, green: 0.60, blue: 0.20)),
                    ("正常高値",   Color(red: 0.30, green: 0.75, blue: 0.20)),
                    ("高値血圧",   Color(red: 0.90, green: 0.78, blue: 0.00)),
                    ("高血圧I度",  Color(red: 1.00, green: 0.55, blue: 0.00)),
                    ("高血圧II度", Color(red: 0.95, green: 0.25, blue: 0.00)),
                    ("高血圧III度",Color(red: 0.80, green: 0.00, blue: 0.00)),
                ]
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 4) {
                    ForEach(jshLegend, id: \.name) { item in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(item.color)
                                .frame(width: 12, height: 12)
                            Text(item.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
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
                    // データ点
                    ForEach(validRecords) { r in
                        PointMark(
                            x: .value("下", r.nBpLo_mmHg),
                            y: .value("上", r.nBpHi_mmHg)
                        )
                        .foregroundStyle(jshColor(hi: r.nBpHi_mmHg, lo: r.nBpLo_mmHg))
                        .symbolSize(32)
                    }
                }
                .chartXScale(domain: 40...130)
                .chartYScale(domain: 70...210)
                .chartXAxisLabel(String(localized: "Stat_BpLo", defaultValue: "下（拡張期）mmHg"))
                .chartYAxisLabel(String(localized: "Stat_BpHi", defaultValue: "上（収縮期）mmHg"))
                .chartXAxis {
                    AxisMarks(values: [60, 80, 100, 120]) { value in
                        AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                        AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)").font(.caption2) } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [80, 100, 120, 140, 160, 180, 200]) { value in
                        AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                        AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)").font(.caption2) } }
                    }
                }
                .frame(height: 220)
                .padding(.horizontal)

                // 区分（DateOpt）凡例
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 4) {
                    ForEach(DateOpt.allCases, id: \.self) { opt in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(dateOptColor(opt))
                                .frame(width: 10, height: 10)
                            Text(opt.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
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

    private func dateOptColor(_ opt: DateOpt) -> Color {
        switch opt {
        case .wake:         return .green
        case .rest:         return .blue
        case .down:         return .orange
        case .sleep:        return .purple
        case .preExercise:  return .teal
        case .postExercise: return .red
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
