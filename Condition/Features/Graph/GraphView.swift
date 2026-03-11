// GraphView.swift
// グラフ画面（旧 GraphVC 相当）

import SwiftUI
import SwiftData
import Charts

struct GraphView: View {

    @Query(
        filter: #Predicate<BodyRecord> { $0.dateTime < bodyRecordGoalDate },
        sort: \BodyRecord.dateTime,
        order: .reverse
    )
    private var records: [BodyRecord]

    private var settings: AppSettings { AppSettings.shared }

    @State private var showSettings = false
    @State private var limitCount = GraphConstants.graphPageLimit

    private var displayRecords: [BodyRecord] {
        Array(records.prefix(limitCount))
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Graph_Empty", defaultValue: "データがありません"),
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                } else {
                    scrollContent
                }
            }
            .navigationTitle(String(localized: "Tab_Graph", defaultValue: "グラフ"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                GraphSettingsView()
            }
        }
    }

    private var scrollContent: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 16) {
                ForEach(settings.graphPanelOrder, id: \.self) { kindRaw in
                    if let kind = GraphKind(rawValue: kindRaw) {
                        graphPanel(kind: kind)
                    }
                }
                // もっと表示
                if records.count > limitCount {
                    Button(String(localized: "Graph_LoadMore", defaultValue: "さらに読み込む")) {
                        limitCount += GraphConstants.graphPageLimit
                    }
                    .padding()
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func graphPanel(kind: GraphKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.title)
                .font(.headline)
                .padding(.horizontal)

            switch kind {
            case .bp:
                BpChartView(records: displayRecords)
                    .frame(height: 160)
            case .bpAvg:
                if settings.graphBpMean || settings.graphBpPress {
                    BpAverageChartView(records: displayRecords)
                        .frame(height: 120)
                }
            case .pulse:
                LineChartView(records: displayRecords, keyPath: \.nPulse_bpm, unit: "bpm", color: .orange, goalValue: settings.goalPulse)
                    .frame(height: 120)
            case .temp:
                LineChartView(records: displayRecords, keyPath: \.nTemp_10c, unit: "℃", color: .red, goalValue: settings.goalTemp, decimals: 1)
                    .frame(height: 120)
            case .weight:
                LineChartView(records: displayRecords, keyPath: \.nWeight_10Kg, unit: "kg", color: .blue, goalValue: settings.goalWeight, decimals: 1)
                    .frame(height: 120)
            case .pedo:
                LineChartView(records: displayRecords, keyPath: \.nPedometer, unit: String(localized: "Unit_Steps", defaultValue: "歩"), color: .green, goalValue: settings.goalPedometer)
                    .frame(height: 120)
            case .bodyFat:
                LineChartView(records: displayRecords, keyPath: \.nBodyFat_10p, unit: "%", color: .purple, goalValue: settings.goalBodyFat, decimals: 1)
                    .frame(height: 120)
            case .skMuscle:
                LineChartView(records: displayRecords, keyPath: \.nSkMuscle_10p, unit: "%", color: .teal, goalValue: settings.goalSkMuscle, decimals: 1)
                    .frame(height: 120)
            }
        }
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 血圧グラフ（Hi-Lo縦棒 + 折れ線）

struct BpChartView: View {
    let records: [BodyRecord]

    private var settings: AppSettings { AppSettings.shared }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }

    var body: some View {
        Chart {
            // Hi-Lo縦棒
            ForEach(validRecords) { r in
                BarMark(
                    x: .value("日時", r.dateTime),
                    yStart: .value("下", r.nBpLo_mmHg),
                    yEnd: .value("上", r.nBpHi_mmHg)
                )
                .foregroundStyle(.gray.opacity(0.3))
                .cornerRadius(2)
            }
            // 上血圧折れ線
            ForEach(validRecords) { r in
                LineMark(
                    x: .value("日時", r.dateTime),
                    y: .value("上", r.nBpHi_mmHg)
                )
                .foregroundStyle(.red)
                .symbol(.circle)
                .symbolSize(30)
            }
            // 下血圧折れ線
            ForEach(validRecords) { r in
                LineMark(
                    x: .value("日時", r.dateTime),
                    y: .value("下", r.nBpLo_mmHg)
                )
                .foregroundStyle(.blue)
                .symbol(.circle)
                .symbolSize(30)
            }
            // 目標値ライン
            if settings.goalBpHi > 0 {
                RuleMark(y: .value("目標上", settings.goalBpHi))
                    .foregroundStyle(.red.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            if settings.goalBpLo > 0 {
                RuleMark(y: .value("目標下", settings.goalBpLo))
                    .foregroundStyle(.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - 平均血圧・脈圧グラフ

struct BpAverageChartView: View {
    let records: [BodyRecord]

    private var settings: AppSettings { AppSettings.shared }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }

    var body: some View {
        Chart {
            if settings.graphBpMean {
                // 平均血圧 = (BpHi + BpLo * 2) / 3
                ForEach(validRecords) { r in
                    let mean = (r.nBpHi_mmHg + r.nBpLo_mmHg * 2) / 3
                    LineMark(
                        x: .value("日時", r.dateTime),
                        y: .value("平均血圧", mean),
                        series: .value("type", "mean")
                    )
                    .foregroundStyle(.purple)
                }
            }
            if settings.graphBpPress {
                // 脈圧 = BpHi - BpLo
                ForEach(validRecords) { r in
                    let pp = r.nBpHi_mmHg - r.nBpLo_mmHg
                    LineMark(
                        x: .value("日時", r.dateTime),
                        y: .value("脈圧", pp),
                        series: .value("type", "pp")
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
        .chartScrollableAxes(.horizontal)
        .padding(.horizontal)
    }
}

// MARK: - 汎用折れ線グラフ

struct LineChartView: View {
    let records: [BodyRecord]
    let keyPath: KeyPath<BodyRecord, Int>
    let unit: String
    let color: Color
    let goalValue: Int
    var decimals: Int = 0

    private var validRecords: [BodyRecord] {
        records.filter { $0[keyPath: keyPath] > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }

    var body: some View {
        Chart {
            ForEach(validRecords) { r in
                LineMark(
                    x: .value("日時", r.dateTime),
                    y: .value(unit, r[keyPath: keyPath])
                )
                .foregroundStyle(color)
                .symbol(.circle)
                .symbolSize(25)
            }
            if goalValue > 0 {
                RuleMark(y: .value("目標", goalValue))
                    .foregroundStyle(color.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text(ValueFormatter.format(v, decimals: decimals))
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}
