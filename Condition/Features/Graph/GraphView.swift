// GraphView.swift
// グラフ画面（刷新版）

import SwiftUI
import SwiftData
import Charts

// MARK: - 表示期間

enum GraphPeriod: Int, CaseIterable {
    case week        = 7
    case month       = 30
    case threeMonths = 90
    case sixMonths   = 180
    case year        = 365

    var label: String {
        switch self {
        case .week:        return String(localized: "Period_Week",    defaultValue: "1週")
        case .month:       return String(localized: "Period_Month",   defaultValue: "1ヶ月")
        case .threeMonths: return String(localized: "Period_3Month",  defaultValue: "3ヶ月")
        case .sixMonths:   return String(localized: "Period_6Month",  defaultValue: "6ヶ月")
        case .year:        return String(localized: "Period_1Year",   defaultValue: "1年")
        }
    }

    var domainSeconds: Int { rawValue * 24 * 3600 }

    var xAxisCount: Int {
        switch self {
        case .week:        return 7
        case .month:       return 6
        case .threeMonths: return 6
        case .sixMonths:   return 6
        case .year:        return 6
        }
    }
}

// MARK: - GraphView

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
    @State private var period: GraphPeriod = .threeMonths

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
            VStack(spacing: 16) {
                // 期間ピッカー
                Picker("期間", selection: $period) {
                    ForEach(GraphPeriod.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(settings.graphPanelOrder, id: \.self) { kindRaw in
                    if let kind = GraphKind(rawValue: kindRaw) {
                        graphPanel(kind: kind)
                    }
                }

                if records.count > limitCount {
                    Button(String(localized: "Graph_LoadMore", defaultValue: "さらに読み込む")) {
                        limitCount += GraphConstants.graphPageLimit
                    }
                    .font(.subheadline)
                    .padding()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func graphPanel(kind: GraphKind) -> some View {
        switch kind {
        case .bp:
            BpChartView(records: displayRecords, period: period)
        case .bpAvg:
            if settings.graphBpMean || settings.graphBpPress {
                BpAverageChartView(records: displayRecords, period: period,
                                   showMean: settings.graphBpMean, showPP: settings.graphBpPress)
            }
        case .pulse:
            LineChartView(records: displayRecords, keyPath: \.nPulse_bpm,
                          title: kind.title, unit: "bpm", color: .orange,
                          goalValue: settings.goalPulse, period: period)
        case .temp:
            LineChartView(records: displayRecords, keyPath: \.nTemp_10c,
                          title: kind.title, unit: "℃", color: .pink,
                          goalValue: settings.goalTemp, decimals: 1, period: period)
        case .weight:
            LineChartView(records: displayRecords, keyPath: \.nWeight_10Kg,
                          title: kind.title, unit: "kg", color: .indigo,
                          goalValue: settings.goalWeight, decimals: 1, period: period)
        case .pedo:
            LineChartView(records: displayRecords, keyPath: \.nPedometer,
                          title: kind.title,
                          unit: String(localized: "Unit_Steps", defaultValue: "歩"),
                          color: .green, goalValue: settings.goalPedometer, period: period)
        case .bodyFat:
            LineChartView(records: displayRecords, keyPath: \.nBodyFat_10p,
                          title: kind.title, unit: "%", color: .purple,
                          goalValue: settings.goalBodyFat, decimals: 1, period: period)
        case .skMuscle:
            LineChartView(records: displayRecords, keyPath: \.nSkMuscle_10p,
                          title: kind.title, unit: "%", color: .teal,
                          goalValue: settings.goalSkMuscle, decimals: 1, period: period)
        }
    }
}

// MARK: - パネル共通部品

/// パネル全体のコンテナ
private struct PanelContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// 統計ラベル（ラベル: 値 の横1行）
private struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// 選択レコードの詳細行（パネル下部）
private struct SelectionDetailRow: View {
    let record: BodyRecord
    let detail: String      // 値＋単位の文字列
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: record.dateOpt.icon)
                .foregroundStyle(.secondary)
            Text(record.dateOpt.label)
                .foregroundStyle(.secondary)
            Text({
                let c = Calendar.current
                let m  = c.component(.month,  from: record.dateTime)
                let d  = c.component(.day,    from: record.dateTime)
                let h  = c.component(.hour,   from: record.dateTime)
                let mn = c.component(.minute, from: record.dateTime)
                let y  = c.component(.year,   from: record.dateTime)
                return String(format: "%d/%d/%d %d:%02d", y, m, d, h, mn)
            }())
            .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .bold()
                .foregroundStyle(color)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - JSH 血圧区分

struct BpZone {
    let min: Int; let max: Int; let color: Color
}

/// JSH 2019 基準による血圧区分カラー（上・下の高い方で分類）
func jshColor(hi: Int, lo: Int) -> Color {
    if hi >= 180 || lo >= 110 { return Color(red: 0.80, green: 0.00, blue: 0.00) }
    if hi >= 160 || lo >= 100 { return Color(red: 0.95, green: 0.25, blue: 0.00) }
    if hi >= 140 || lo >= 90  { return Color(red: 1.00, green: 0.55, blue: 0.00) }
    if hi >= 130 || lo >= 80  { return Color(red: 0.90, green: 0.78, blue: 0.00) }
    if hi >= 120              { return Color(red: 0.30, green: 0.75, blue: 0.20) }
    return Color(red: 0.05, green: 0.60, blue: 0.20)
}

let bpHiZones: [BpZone] = [
    .init(min:  80, max: 120, color: Color(red: 0.18, green: 0.65, blue: 0.28).opacity(0.08)),
    .init(min: 120, max: 130, color: Color(red: 0.45, green: 0.72, blue: 0.28).opacity(0.09)),
    .init(min: 130, max: 140, color: Color(red: 0.85, green: 0.72, blue: 0.10).opacity(0.10)),
    .init(min: 140, max: 160, color: Color.orange.opacity(0.11)),
    .init(min: 160, max: 180, color: Color(red: 0.90, green: 0.30, blue: 0.10).opacity(0.12)),
    .init(min: 180, max: 220, color: Color(red: 0.75, green: 0.10, blue: 0.10).opacity(0.14)),
]

let bpLoZones: [BpZone] = [
    .init(min:  40, max:  80, color: Color(red: 0.18, green: 0.65, blue: 0.28).opacity(0.08)),
    .init(min:  80, max:  90, color: Color(red: 0.85, green: 0.72, blue: 0.10).opacity(0.10)),
    .init(min:  90, max: 100, color: Color.orange.opacity(0.11)),
    .init(min: 100, max: 110, color: Color(red: 0.90, green: 0.30, blue: 0.10).opacity(0.12)),
    .init(min: 110, max: 140, color: Color(red: 0.75, green: 0.10, blue: 0.10).opacity(0.14)),
]

// MARK: - 血圧分布バー

/// JSH ゾーン背景 + 測定範囲カプセル + 平均マーカーを Canvas で描画する横バー
struct BpDistributionBar: View {
    let label: String
    let color: Color
    let values: [Int]
    let zones: [BpZone]
    let barMin: Int
    let barMax: Int

    private var minVal: Int? { values.min() }
    private var maxVal: Int? { values.max() }
    private var avgVal: Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(color)
                .frame(width: 14, alignment: .center)

            Canvas { ctx, size in
                let w = size.width; let h = size.height
                let span = CGFloat(barMax - barMin)
                func xf(_ v: Int) -> CGFloat { CGFloat(v - barMin) / span * w }

                // カプセル形にクリップ
                ctx.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: h / 2))

                // ゾーン背景
                for z in zones {
                    let x0 = xf(max(z.min, barMin))
                    let x1 = xf(min(z.max, barMax))
                    guard x1 > x0 else { continue }
                    ctx.fill(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: h)), with: .color(z.color))
                }

                // 測定範囲カプセル（min〜max）
                if let mn = minVal, let mx = maxVal, mx > mn {
                    let rx = xf(mn); let rw = max(6, xf(mx) - rx)
                    ctx.fill(
                        Path(roundedRect: CGRect(x: rx, y: 2, width: rw, height: h - 4), cornerRadius: (h - 4) / 2),
                        with: .color(color.opacity(0.45))
                    )
                }

                // 平均マーカー（白抜き円）
                if let avg = avgVal {
                    let cx = xf(avg); let cy = h / 2; let r: CGFloat = 5
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                             with: .color(.white))
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx - r + 1, y: cy - r + 1,
                                                      width: (r - 1) * 2, height: (r - 1) * 2)),
                               with: .color(color), lineWidth: 1.5)
                }
            }
            .frame(height: 16)
        }
    }
}

// MARK: - 共通 X 軸モディファイア

private extension View {
    /// 横スクロール可能なX軸。初期表示・期間変更時に最新日が右端になるよう設定する。
    /// - Parameters:
    ///   - oldestDate: データの最古日時。スクロール域の左端に使用。nil の場合は期間分のみ。
    func standardXAxis(period: GraphPeriod, scrollPosition: Binding<Date>, oldestDate: Date? = nil) -> some View {
        let now = Date()
        // スクロール域: 最古データ（最大1年前）〜現在。これにより確実にスクロール可能になる。
        let maxLookback = now.addingTimeInterval(-730 * 24 * 3600)
        let domainStart = oldestDate.map { max($0, maxLookback) } ?? now.addingTimeInterval(-TimeInterval(period.domainSeconds))
        let scrollDomain = domainStart...now

        return self
            .chartXScale(domain: scrollDomain)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: period.domainSeconds)
            .chartScrollPosition(x: scrollPosition)
            .onAppear {
                scrollPosition.wrappedValue = now.addingTimeInterval(-TimeInterval(period.domainSeconds))
            }
            .onChange(of: period) { _, newPeriod in
                scrollPosition.wrappedValue = Date().addingTimeInterval(-TimeInterval(newPeriod.domainSeconds))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: period.xAxisCount)) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            let m = Calendar.current.component(.month, from: date)
                            let d = Calendar.current.component(.day, from: date)
                            Text("\(m)/\(d)").font(.caption2)
                        }
                    }
                }
            }
    }
}

// MARK: - 血圧グラフパネル

struct BpChartView: View {
    let records: [BodyRecord]
    let period: GraphPeriod

    private var settings: AppSettings { AppSettings.shared }
    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }
    private var periodStart: Date {
        Calendar.current.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }
    private var periodRecords: [BodyRecord] { validRecords.filter { $0.dateTime >= periodStart } }

    private var selectedRecord: BodyRecord? {
        guard let date = selectedDate else { return nil }
        return validRecords.min(by: {
            abs($0.dateTime.timeIntervalSince(date)) < abs($1.dateTime.timeIntervalSince(date))
        })
    }

    private var avgHi: Int? {
        let v = periodRecords.map(\.nBpHi_mmHg); guard !v.isEmpty else { return nil }
        return Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
    }
    private var avgLo: Int? {
        let v = periodRecords.map(\.nBpLo_mmHg); guard !v.isEmpty else { return nil }
        return Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
    }

    var body: some View {
        PanelContainer {
            // ヘッダー
            HStack(alignment: .firstTextBaseline) {
                Text(GraphKind.bp.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let hi = avgHi, let lo = avgLo {
                    StatCell(label: "平均", value: "\(hi)／\(lo)")
                }
                if let mnHi = periodRecords.map(\.nBpHi_mmHg).min(),
                   let mxHi = periodRecords.map(\.nBpHi_mmHg).max(),
                   let mnLo = periodRecords.map(\.nBpLo_mmHg).min(),
                   let mxLo = periodRecords.map(\.nBpLo_mmHg).max() {
                    StatCell(label: "範囲", value: "\(mnHi)–\(mxHi)／\(mnLo)–\(mxLo)")
                }
                Text("mmHg").font(.subheadline.weight(.semibold)).foregroundStyle(.red)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // チャート
            Chart {
                // 上〜下の帯
                ForEach(validRecords) { r in
                    AreaMark(
                        x: .value("日時", r.dateTime),
                        yStart: .value("下", r.nBpLo_mmHg),
                        yEnd:   .value("上", r.nBpHi_mmHg)
                    )
                    .foregroundStyle(Color.purple.opacity(0.08))
                    .interpolationMethod(.catmullRom)
                }
                // 上ライン
                ForEach(validRecords) { r in
                    LineMark(x: .value("日時", r.dateTime), y: .value("上", r.nBpHi_mmHg),
                             series: .value("系列", "上"))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
                ForEach(validRecords) { r in
                    PointMark(x: .value("日時", r.dateTime), y: .value("上", r.nBpHi_mmHg))
                        .foregroundStyle(r.dateTime == selectedRecord?.dateTime ? .red : .red.opacity(0.5))
                        .symbolSize(r.dateTime == selectedRecord?.dateTime ? 80 : 18)
                }
                // 下ライン
                ForEach(validRecords) { r in
                    LineMark(x: .value("日時", r.dateTime), y: .value("下", r.nBpLo_mmHg),
                             series: .value("系列", "下"))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
                ForEach(validRecords) { r in
                    PointMark(x: .value("日時", r.dateTime), y: .value("下", r.nBpLo_mmHg))
                        .foregroundStyle(r.dateTime == selectedRecord?.dateTime ? .blue : .blue.opacity(0.5))
                        .symbolSize(r.dateTime == selectedRecord?.dateTime ? 80 : 18)
                }
                // 平均血圧ライン (MAP = (上 + 2×下) / 3)
                ForEach(validRecords) { r in
                    let map = (r.nBpHi_mmHg + 2 * r.nBpLo_mmHg) / 3
                    LineMark(x: .value("日時", r.dateTime), y: .value("平均血圧", map),
                             series: .value("系列", "平均血圧"))
                        .foregroundStyle(.purple)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                        .interpolationMethod(.catmullRom)
                }
                // 選択ルール
                if let sel = selectedRecord {
                    RuleMark(x: .value("選択", sel.dateTime))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                // 目標ライン
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
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)").font(.caption2) } }
                }
            }
            .chartXSelection(value: $selectedDate)
            .standardXAxis(period: period, scrollPosition: $scrollPosition, oldestDate: validRecords.first?.dateTime)
            .frame(height: 150)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // 選択詳細
            if let r = selectedRecord {
                Divider()
                let map = (r.nBpHi_mmHg + 2 * r.nBpLo_mmHg) / 3
                SelectionDetailRow(
                    record: r,
                    detail: "\(r.nBpHi_mmHg)／\(r.nBpLo_mmHg)  平均 \(map) mmHg",
                    color: .red
                )
            }

        }
    }
}

// MARK: - 平均血圧・脈圧グラフパネル

struct BpAverageChartView: View {
    let records: [BodyRecord]
    let period: GraphPeriod
    let showMean: Bool
    let showPP: Bool

    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()

    private var periodStart: Date {
        Calendar.current.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }

    private var selectedRecord: BodyRecord? {
        guard let date = selectedDate else { return nil }
        return validRecords.min(by: {
            abs($0.dateTime.timeIntervalSince(date)) < abs($1.dateTime.timeIntervalSince(date))
        })
    }

    private var meanValues: [(record: BodyRecord, value: Int)] {
        validRecords.map { r in (r, (r.nBpHi_mmHg + r.nBpLo_mmHg * 2) / 3) }
    }
    private var ppValues: [(record: BodyRecord, value: Int)] {
        validRecords.map { r in (r, r.nBpHi_mmHg - r.nBpLo_mmHg) }
    }

    private var latestMean: Int? { meanValues.last?.value }
    private var latestPP: Int?   { ppValues.last?.value }

    var body: some View {
        PanelContainer {
            // ヘッダー
            HStack(alignment: .top) {
                Text(GraphKind.bpAvg.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 16) {
                    if showMean, let v = latestMean {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(v)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.purple)
                            Text("平均血圧 mmHg").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if showPP, let v = latestPP {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(v)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                            Text("脈圧 mmHg").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Chart {
                if showMean {
                    ForEach(meanValues, id: \.record.dateTime) { item in
                        AreaMark(x: .value("日時", item.record.dateTime), y: .value("平均血圧", item.value))
                            .foregroundStyle(LinearGradient(colors: [.purple.opacity(0.2), .purple.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(meanValues, id: \.record.dateTime) { item in
                        LineMark(x: .value("日時", item.record.dateTime), y: .value("平均血圧", item.value),
                                 series: .value("type", "mean"))
                            .foregroundStyle(.purple)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(meanValues, id: \.record.dateTime) { item in
                        PointMark(x: .value("日時", item.record.dateTime), y: .value("平均血圧", item.value))
                            .foregroundStyle(item.record.dateTime == selectedRecord?.dateTime ? .purple : .purple.opacity(0.5))
                            .symbolSize(item.record.dateTime == selectedRecord?.dateTime ? 60 : 16)
                    }
                }
                if showPP {
                    ForEach(ppValues, id: \.record.dateTime) { item in
                        LineMark(x: .value("日時", item.record.dateTime), y: .value("脈圧", item.value),
                                 series: .value("type", "pp"))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(ppValues, id: \.record.dateTime) { item in
                        PointMark(x: .value("日時", item.record.dateTime), y: .value("脈圧", item.value))
                            .foregroundStyle(item.record.dateTime == selectedRecord?.dateTime ? .orange : .orange.opacity(0.5))
                            .symbolSize(item.record.dateTime == selectedRecord?.dateTime ? 60 : 16)
                    }
                }
                if let sel = selectedRecord {
                    RuleMark(x: .value("選択", sel.dateTime))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)").font(.caption2) } }
                }
            }
            .chartXSelection(value: $selectedDate)
            .standardXAxis(period: period, scrollPosition: $scrollPosition, oldestDate: validRecords.first?.dateTime)
            .frame(height: 120)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            if let r = selectedRecord {
                Divider()
                let mean = (r.nBpHi_mmHg + r.nBpLo_mmHg * 2) / 3
                let pp   = r.nBpHi_mmHg - r.nBpLo_mmHg
                var detail: String {
                    var parts: [String] = []
                    if showMean { parts.append("平均 \(mean)") }
                    if showPP   { parts.append("脈圧 \(pp)") }
                    return parts.joined(separator: "  ") + " mmHg"
                }
                SelectionDetailRow(record: r, detail: detail, color: .primary)
            }
        }
    }
}

// MARK: - 汎用折れ線グラフパネル

struct LineChartView: View {
    let records: [BodyRecord]
    let keyPath: KeyPath<BodyRecord, Int>
    let title: String
    let unit: String
    let color: Color
    let goalValue: Int
    var decimals: Int = 0
    let period: GraphPeriod

    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()

    private var selectedRecord: BodyRecord? {
        guard let date = selectedDate else { return nil }
        return validRecords.min(by: {
            abs($0.dateTime.timeIntervalSince(date)) < abs($1.dateTime.timeIntervalSince(date))
        })
    }

    private var validRecords: [BodyRecord] {
        records.filter { $0[keyPath: keyPath] > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }
    private var periodStart: Date {
        Calendar.current.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }
    private var periodRecords: [BodyRecord] { validRecords.filter { $0.dateTime >= periodStart } }

    private var avgValue: Int? {
        let v = periodRecords.map { $0[keyPath: keyPath] }
        guard !v.isEmpty else { return nil }
        return Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
    }
    private var minValue: Int? { periodRecords.map { $0[keyPath: keyPath] }.min() }
    private var maxValue: Int? { periodRecords.map { $0[keyPath: keyPath] }.max() }

    private func fmt(_ v: Int) -> String { ValueFormatter.format(v, decimals: decimals) }

    var body: some View {
        PanelContainer {
            // ヘッダー
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let avg = avgValue {
                    StatCell(label: "平均", value: "\(fmt(avg))")
                }
                if let mn = minValue, let mx = maxValue {
                    StatCell(label: "範囲", value: "\(fmt(mn))–\(fmt(mx))")
                }
                Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // チャート
            Chart {
                // エリア
                ForEach(validRecords) { r in
                    AreaMark(
                        x: .value("日時", r.dateTime),
                        y: .value(unit, r[keyPath: keyPath])
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [color.opacity(0.25), color.opacity(0.0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                }
                // ライン
                ForEach(validRecords) { r in
                    LineMark(
                        x: .value("日時", r.dateTime),
                        y: .value(unit, r[keyPath: keyPath])
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                // ポイント
                ForEach(validRecords) { r in
                    PointMark(
                        x: .value("日時", r.dateTime),
                        y: .value(unit, r[keyPath: keyPath])
                    )
                    .foregroundStyle(r.dateTime == selectedRecord?.dateTime ? color : color.opacity(0.5))
                    .symbolSize(r.dateTime == selectedRecord?.dateTime ? 70 : 16)
                }
                // 選択ルール
                if let sel = selectedRecord {
                    RuleMark(x: .value("選択", sel.dateTime))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                // 目標ライン
                if goalValue > 0 {
                    RuleMark(y: .value("目標", goalValue))
                        .foregroundStyle(color.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(String(localized: "Graph_Goal", defaultValue: "目標"))
                                .font(.caption2)
                                .foregroundStyle(color.opacity(0.7))
                                .padding(.trailing, 4)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(fmt(v)).font(.caption2)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .standardXAxis(period: period, scrollPosition: $scrollPosition, oldestDate: validRecords.first?.dateTime)
            .frame(height: 120)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // 選択詳細
            if let r = selectedRecord {
                Divider()
                SelectionDetailRow(
                    record: r,
                    detail: "\(fmt(r[keyPath: keyPath])) \(unit)",
                    color: color
                )
            }
        }
    }
}
