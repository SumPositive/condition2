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
                NavigationStack {
                    GraphSettingsView(isModal: true)
                }
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

                let hidden = Set(settings.hiddenFields)
                ForEach(settings.graphPanelOrder.filter { !hidden.contains($0) }, id: \.self) { kindRaw in
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
            // 脈圧は常に血圧の直後に表示（パネル順序に依存しない）
            if settings.graphBpPress {
                BpPpChartView(records: displayRecords, period: period)
            }
        case .bpAvg:
            EmptyView() // 脈圧は .bp の直後で描画済み
        case .pulse:
            LineChartView(records: displayRecords, keyPath: \.nPulse_bpm,
                          title: kind.title, unit: "bpm", color: .orange,
                          goalValue: settings.goalPulse, period: period,
                          tightDomain: true)
        case .temp:
            LineChartView(records: displayRecords, keyPath: \.nTemp_10c,
                          title: kind.title, unit: "℃", color: .pink,
                          goalValue: settings.goalTemp, decimals: 1, period: period,
                          tightDomain: true)
        case .weight:
            LineChartView(records: displayRecords, keyPath: \.nWeight_10Kg,
                          title: kind.title, unit: "kg", color: .indigo,
                          goalValue: settings.goalWeight, decimals: 1, period: period,
                          tightDomain: true)
            if settings.graphBMI && settings.graphBMITall > 0 {
                BMIChartView(records: displayRecords, heightCm: settings.graphBMITall, period: period)
            }
        case .pedo:
            LineChartView(records: displayRecords, keyPath: \.nPedometer,
                          title: kind.title,
                          unit: String(localized: "Unit_Steps", defaultValue: "歩"),
                          color: .green, goalValue: settings.goalPedometer, period: period,
                          tightDomain: true)
        case .bodyFat:
            LineChartView(records: displayRecords, keyPath: \.nBodyFat_10p,
                          title: kind.title, unit: "%", color: .purple,
                          goalValue: settings.goalBodyFat, decimals: 1, period: period,
                          tightDomain: true)
        case .skMuscle:
            LineChartView(records: displayRecords, keyPath: \.nSkMuscle_10p,
                          title: kind.title, unit: "%", color: .teal,
                          goalValue: settings.goalSkMuscle, decimals: 1, period: period,
                          tightDomain: true)
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
    let label: LocalizedStringKey
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
            Text(record.dateOpt.label)
            Text({
                let c = Calendar.current
                let m  = c.component(.month,  from: record.dateTime)
                let d  = c.component(.day,    from: record.dateTime)
                let h  = c.component(.hour,   from: record.dateTime)
                let mn = c.component(.minute, from: record.dateTime)
                let y  = c.component(.year,   from: record.dateTime)
                return String(format: "%d/%d/%d %d:%02d", y, m, d, h, mn)
            }())
            .foregroundStyle(color.opacity(0.7))
            Spacer()
            Text(detail)
                .bold()
        }
        .foregroundStyle(color)
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - JSH 血圧区分

struct BpZone {
    let min: Int; let max: Int; let color: Color
}

// MARK: - BMI区分（日本肥満学会 JASSO基準）

struct BMIZone {
    let min: Double; let max: Double; let color: Color; let swatch: Color; let label: String
}

let bmiZones: [BMIZone] = [
    .init(min:  0.0, max: 18.5, color: Color(red: 0.30, green: 0.60, blue: 0.95).opacity(0.13), swatch: Color(red: 0.30, green: 0.60, blue: 0.95), label: "低体重"),
    .init(min: 18.5, max: 25.0, color: Color(red: 0.18, green: 0.65, blue: 0.28).opacity(0.11), swatch: Color(red: 0.18, green: 0.65, blue: 0.28), label: "普通体重"),
    .init(min: 25.0, max: 30.0, color: Color(red: 0.90, green: 0.75, blue: 0.10).opacity(0.13), swatch: Color(red: 0.90, green: 0.75, blue: 0.10), label: "肥満度1"),
    .init(min: 30.0, max: 35.0, color: Color(red: 0.95, green: 0.45, blue: 0.10).opacity(0.14), swatch: Color(red: 0.95, green: 0.45, blue: 0.10), label: "肥満度2"),
    .init(min: 35.0, max: 60.0, color: Color(red: 0.80, green: 0.10, blue: 0.10).opacity(0.15), swatch: Color(red: 0.80, green: 0.10, blue: 0.10), label: "肥満度3以上"),
]

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
    /// タップのみで日付を選択／解除する（ドラッグは横スクロールへ通過させる）
    func tapToSelectDay(_ selectedDate: Binding<Date?>, validDays: Set<Date>) -> some View {
        chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { tap in
                    let tapX = tap.location.x
                    let tolerancePx: CGFloat = 44  // タップ許容範囲（ポイント）
                    // タップ位置に最も近い有効日をピクセル距離で探す
                    let nearest = validDays.compactMap { day -> (Date, CGFloat)? in
                        guard let x = proxy.position(forX: day) else { return nil }
                        return (day, abs(x - tapX))
                    }.min(by: { $0.1 < $1.1 })
                    guard let (day, distance) = nearest, distance <= tolerancePx else {
                        selectedDate.wrappedValue = nil   // 許容範囲外 → 選択解除
                        return
                    }
                    if let sel = selectedDate.wrappedValue,
                       Calendar.current.isDate(sel, inSameDayAs: day) {
                        selectedDate.wrappedValue = nil   // 同じ日を再タップ → 解除
                    } else {
                        selectedDate.wrappedValue = day
                    }
                }
        }
    }

    /// 横スクロール可能なX軸。初期表示・期間変更時に最新日が右端になるよう設定する。
    /// - Parameters:
    ///   - oldestDate: データの最古日時。スクロール域の左端に使用。nil の場合は期間分のみ。
    func standardXAxis(period: GraphPeriod, scrollPosition: Binding<Date>, oldestDate: Date? = nil) -> some View {
        let now = Date()
        // スクロール域: 最古データ（最大1年前）〜現在。これにより確実にスクロール可能になる。
        let maxLookback = now.addingTimeInterval(-730 * 24 * 3600)
        let rawStart = oldestDate.map { max($0, maxLookback) } ?? now.addingTimeInterval(-TimeInterval(period.domainSeconds))
        let domainStart = min(rawStart.addingTimeInterval(-2 * 24 * 3600), now)
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

// MARK: - 日次集計ヘルパー構造体

private struct DailyBpAvg: Identifiable {
    let date: Date
    let mean: Double
    let pp: Double
    var id: Date { date }
}

private struct DailyLineValue: Identifiable {
    let date: Date
    let avg: Double
    var id: Date { date }
}

// MARK: - 血圧グラフパネル

private struct DailyBp: Identifiable {
    let date: Date   // start of day
    let hi: Double
    let lo: Double
    var map: Double { (hi + 2 * lo) / 3 }
    var pp:  Double { hi - lo }
    var id: Date { date }
}

struct BpChartView: View {
    let records: [BodyRecord]
    let period: GraphPeriod

    private let cal = Calendar.current
    private var settings: AppSettings { AppSettings.shared }
    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }
    private var periodStart: Date {
        cal.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }
    private var periodRecords: [BodyRecord] { validRecords.filter { $0.dateTime >= periodStart } }

    private func dayStart(_ date: Date) -> Date { cal.startOfDay(for: date) }

    private var dailyAverages: [DailyBp] {
        let grouped = Dictionary(grouping: validRecords) { dayStart($0.dateTime) }
        return grouped.map { date, recs in
            let hi = Double(recs.map(\.nBpHi_mmHg).reduce(0, +)) / Double(recs.count)
            let lo = Double(recs.map(\.nBpLo_mmHg).reduce(0, +)) / Double(recs.count)
            return DailyBp(date: date, hi: hi, lo: lo)
        }.sorted { $0.date < $1.date }
    }

    private var selectedDayRecords: [BodyRecord] {
        guard let date = selectedDate else { return [] }
        let target = dayStart(date)
        return validRecords.filter { dayStart($0.dateTime) == target }
    }

    private var avgHi: Int? {
        let v = periodRecords.map(\.nBpHi_mmHg); guard !v.isEmpty else { return nil }
        return Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
    }
    private var avgLo: Int? {
        let v = periodRecords.map(\.nBpLo_mmHg); guard !v.isEmpty else { return nil }
        return Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
    }

    private var avgMap: Int? {
        guard let hi = avgHi, let lo = avgLo else { return nil }
        return (hi + 2 * lo) / 3
    }
    private var avgPP: Int? {
        guard let hi = avgHi, let lo = avgLo else { return nil }
        return hi - lo
    }

    // Y軸タイトドメイン用（過去1年の上最大・下最小）
    private var yearRecords: [BodyRecord] {
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return validRecords.filter { $0.dateTime >= oneYearAgo }
    }
    private var yearMaxHi: Int? { yearRecords.map(\.nBpHi_mmHg).max() }
    private var yearMinLo: Int? { yearRecords.map(\.nBpLo_mmHg).min() }

    var body: some View {
        PanelContainer {
            // ヘッダー
            HStack(alignment: .firstTextBaseline) {
                Text(GraphKind.bp.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if settings.graphBpMean, let map = avgMap {
                    StatCell(label: "平均血圧", value: "\(map)")
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
                // 上〜下の帯（日次平均）
                ForEach(dailyAverages) { d in
                    AreaMark(
                        x: .value("日時", d.date),
                        yStart: .value("下", d.lo),
                        yEnd:   .value("上", d.hi)
                    )
                    .foregroundStyle(Color.purple.opacity(0.08))
                    .interpolationMethod(.catmullRom)
                }
                // 上ライン（日次平均を経由）
                ForEach(dailyAverages) { d in
                    LineMark(x: .value("日時", d.date), y: .value("上", d.hi),
                             series: .value("系列", "上"))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
                // 上ポイント（個別レコード、同日は同X）
                ForEach(validRecords) { r in
                    PointMark(x: .value("日時", dayStart(r.dateTime)), y: .value("上", Double(r.nBpHi_mmHg)))
                        .foregroundStyle(r.dateOpt.color)
                        .symbolSize(18)
                }
                // 下ライン（日次平均を経由）
                ForEach(dailyAverages) { d in
                    LineMark(x: .value("日時", d.date), y: .value("下", d.lo),
                             series: .value("系列", "下"))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
                // 下ポイント（個別レコード、同日は同X）
                ForEach(validRecords) { r in
                    PointMark(x: .value("日時", dayStart(r.dateTime)), y: .value("下", Double(r.nBpLo_mmHg)))
                        .foregroundStyle(r.dateOpt.color)
                        .symbolSize(18)
                }
                // 平均血圧ライン（graphBpMean ON 時のみ）
                if settings.graphBpMean {
                    ForEach(dailyAverages) { d in
                        LineMark(x: .value("日時", d.date), y: .value("平均血圧", d.map),
                                 series: .value("系列", "平均血圧"))
                            .foregroundStyle(.purple)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                            .interpolationMethod(.catmullRom)
                    }
                }
                // 選択ルール
                if let date = selectedDate {
                    RuleMark(x: .value("選択", dayStart(date)))
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
            .chartYTightDomain(enabled: true, minVal: yearMinLo, maxVal: yearMaxHi)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(String(Int(v.rounded()))).font(.caption2) } }
                }
            }
            .tapToSelectDay($selectedDate, validDays: Set(validRecords.map { dayStart($0.dateTime) }))
            .standardXAxis(period: period, scrollPosition: $scrollPosition, oldestDate: validRecords.first?.dateTime)
            .frame(height: 150)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // 選択詳細（同日複数レコードも全表示）
            if !selectedDayRecords.isEmpty {
                Divider()
                ForEach(selectedDayRecords) { r in
                    let map = (r.nBpHi_mmHg + 2 * r.nBpLo_mmHg) / 3
                    let mapStr = settings.graphBpMean ? "  平均 \(map)" : ""
                    SelectionDetailRow(
                        record: r,
                        detail: "\(r.nBpHi_mmHg)／\(r.nBpLo_mmHg)\(mapStr) mmHg",
                        color: r.dateOpt.color
                    )
                }
            }

        }
    }
}

// MARK: - 脈圧グラフパネル

struct BpPpChartView: View {
    let records: [BodyRecord]
    let period: GraphPeriod

    private let cal = Calendar.current
    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()

    private func dayStart(_ date: Date) -> Date { cal.startOfDay(for: date) }

    private var validRecords: [BodyRecord] {
        records.filter { $0.nBpHi_mmHg > 0 && $0.nBpLo_mmHg > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }

    private var dailyPP: [DailyBpAvg] {
        let grouped = Dictionary(grouping: validRecords) { dayStart($0.dateTime) }
        return grouped.map { date, recs in
            let pp = Double(recs.map { $0.nBpHi_mmHg - $0.nBpLo_mmHg }.reduce(0, +)) / Double(recs.count)
            return DailyBpAvg(date: date, mean: pp, pp: pp)
        }.sorted { $0.date < $1.date }
    }

    private var ppValues: [(record: BodyRecord, value: Int)] {
        validRecords.map { r in (r, r.nBpHi_mmHg - r.nBpLo_mmHg) }
    }

    private var periodStart: Date {
        cal.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }
    private var periodPPValues: [Int] {
        validRecords.filter { $0.dateTime >= periodStart }.map { $0.nBpHi_mmHg - $0.nBpLo_mmHg }
    }
    private var avgPP: Int? {
        guard !periodPPValues.isEmpty else { return nil }
        return Int((Double(periodPPValues.reduce(0, +)) / Double(periodPPValues.count)).rounded())
    }
    private var minPP: Int? { periodPPValues.min() }
    private var maxPP: Int? { periodPPValues.max() }

    private var selectedDayRecords: [BodyRecord] {
        guard let date = selectedDate else { return [] }
        let target = dayStart(date)
        return validRecords.filter { dayStart($0.dateTime) == target }
    }

    var body: some View {
        PanelContainer {
            // ヘッダー（血圧セクションと同スタイル）
            HStack(alignment: .firstTextBaseline) {
                Text(GraphKind.bpAvg.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let avg = avgPP {
                    StatCell(label: "平均", value: "\(avg)")
                }
                if let mn = minPP, let mx = maxPP {
                    StatCell(label: "範囲", value: "\(mn)–\(mx)")
                }
                Text("mmHg").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Chart {
                // 正常範囲帯（40〜50 mmHg）
                RectangleMark(yStart: .value("正常下限", 40), yEnd: .value("正常上限", 50))
                    .foregroundStyle(Color.green.opacity(0.12))
                // 正常範囲の境界線
                RuleMark(y: .value("正常下限", 40))
                    .foregroundStyle(Color.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                RuleMark(y: .value("正常上限", 50))
                    .foregroundStyle(Color.green.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                // 日次平均ライン
                ForEach(dailyPP) { d in
                    LineMark(x: .value("日時", d.date), y: .value("脈圧", d.pp),
                             series: .value("type", "pp"))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
                // 個別ポイント
                ForEach(ppValues, id: \.record.dateTime) { item in
                    PointMark(x: .value("日時", dayStart(item.record.dateTime)),
                              y: .value("脈圧", Double(item.value)))
                        .foregroundStyle(item.record.dateOpt.color)
                        .symbolSize(16)
                }
                // 選択ルール
                if let date = selectedDate {
                    RuleMark(x: .value("選択", dayStart(date)))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(String(Int(v.rounded()))).font(.caption2) } }
                }
            }
            .tapToSelectDay($selectedDate, validDays: Set(validRecords.map { dayStart($0.dateTime) }))
            .standardXAxis(period: period, scrollPosition: $scrollPosition, oldestDate: validRecords.first?.dateTime)
            .frame(height: 120)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            if !selectedDayRecords.isEmpty {
                Divider()
                ForEach(selectedDayRecords) { r in
                    SelectionDetailRow(record: r,
                                       detail: "脈圧 \(r.nBpHi_mmHg - r.nBpLo_mmHg) mmHg",
                                       color: r.dateOpt.color)
                }
            }
        }
    }
}

// MARK: - 汎用折れ線グラフパネル

private extension View {
    @ViewBuilder
    func chartYTightDomain(enabled: Bool, minVal: Int?, maxVal: Int?) -> some View {
        if enabled, let lo = minVal, let hi = maxVal, lo < hi {
            let pad = Swift.max(Double(hi - lo) * 0.15, 5.0)
            self.chartYScale(domain: (Double(lo) - pad)...(Double(hi) + pad))
        } else {
            self.chartYScale(domain: .automatic(includesZero: false))
        }
    }

    @ViewBuilder
    func chartYTightDomain(minVal: Double?, maxVal: Double?) -> some View {
        if let lo = minVal, let hi = maxVal, lo < hi {
            let pad = Swift.max((hi - lo) * 0.15, 0.5)
            self.chartYScale(domain: (lo - pad)...(hi + pad))
        } else {
            self.chartYScale(domain: .automatic(includesZero: false))
        }
    }
}

struct LineChartView: View {
    let records: [BodyRecord]
    let keyPath: KeyPath<BodyRecord, Int>
    let title: String
    let unit: String
    let color: Color
    let goalValue: Int
    var decimals: Int = 0
    let period: GraphPeriod
    var tightDomain: Bool = false

    private let cal = Calendar.current
    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()

    private func dayStart(_ date: Date) -> Date { cal.startOfDay(for: date) }

    private var validRecords: [BodyRecord] {
        records.filter { $0[keyPath: keyPath] > 0 }
            .sorted { $0.dateTime < $1.dateTime }
    }
    private var periodStart: Date {
        cal.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }
    private var periodRecords: [BodyRecord] { validRecords.filter { $0.dateTime >= periodStart } }

    private var dailyValues: [DailyLineValue] {
        let grouped = Dictionary(grouping: validRecords) { dayStart($0.dateTime) }
        return grouped.map { date, recs in
            let avg = Double(recs.map { $0[keyPath: keyPath] }.reduce(0, +)) / Double(recs.count)
            return DailyLineValue(date: date, avg: avg)
        }.sorted { $0.date < $1.date }
    }

    private var selectedDayRecords: [BodyRecord] {
        guard let date = selectedDate else { return [] }
        let target = dayStart(date)
        return validRecords.filter { dayStart($0.dateTime) == target }
    }

    private var avgValue: Int? {
        let v = periodRecords.map { $0[keyPath: keyPath] }
        guard !v.isEmpty else { return nil }
        return Int((Double(v.reduce(0, +)) / Double(v.count)).rounded())
    }
    private var minValue: Int? { periodRecords.map { $0[keyPath: keyPath] }.min() }
    private var maxValue: Int? { periodRecords.map { $0[keyPath: keyPath] }.max() }

    // Y軸タイトドメイン用（過去1年全体の最大最小）
    private var yearRecords: [BodyRecord] {
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return validRecords.filter { $0.dateTime >= oneYearAgo }
    }
    private var yearMinValue: Int? { yearRecords.map { $0[keyPath: keyPath] }.min() }
    private var yearMaxValue: Int? { yearRecords.map { $0[keyPath: keyPath] }.max() }

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
                // エリア（日次平均）
                ForEach(dailyValues) { d in
                    AreaMark(
                        x: .value("日時", d.date),
                        y: .value(unit, d.avg)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [color.opacity(0.25), color.opacity(0.0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                }
                // ライン（日次平均を経由）
                ForEach(dailyValues) { d in
                    LineMark(
                        x: .value("日時", d.date),
                        y: .value(unit, d.avg)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                // ポイント（個別レコード、同日は同X）
                ForEach(validRecords) { r in
                    PointMark(
                        x: .value("日時", dayStart(r.dateTime)),
                        y: .value(unit, Double(r[keyPath: keyPath]))
                    )
                    .foregroundStyle(r.dateOpt.color)
                    .symbolSize(16)
                }
                // 選択ルール
                if let date = selectedDate {
                    RuleMark(x: .value("選択", dayStart(date)))
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
            .chartYTightDomain(enabled: tightDomain, minVal: yearMinValue, maxVal: yearMaxValue)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(fmt(Int(v.rounded()))).font(.caption2)
                        }
                    }
                }
            }
            .tapToSelectDay($selectedDate, validDays: Set(validRecords.map { dayStart($0.dateTime) }))
            .standardXAxis(period: period, scrollPosition: $scrollPosition, oldestDate: validRecords.first?.dateTime)
            .frame(height: 120)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // 選択詳細（同日複数レコードも全表示）
            if !selectedDayRecords.isEmpty {
                Divider()
                ForEach(selectedDayRecords) { r in
                    SelectionDetailRow(
                        record: r,
                        detail: "\(fmt(r[keyPath: keyPath])) \(unit)",
                        color: r.dateOpt.color
                    )
                }
            }
        }
    }
}

// MARK: - BMIグラフパネル

private struct BMIChartView: View {
    let records: [BodyRecord]
    let heightCm: Int
    let period: GraphPeriod

    private let cal = Calendar.current
    @State private var selectedDate: Date?
    @State private var scrollPosition: Date = Date()
    @State private var showBMIInfo = false

    private func dayStart(_ date: Date) -> Date { cal.startOfDay(for: date) }

    private func bmi(for record: BodyRecord) -> Double? {
        guard record.nWeight_10Kg > 0 else { return nil }
        let hm = Double(heightCm) / 100.0
        return (Double(record.nWeight_10Kg) / 10.0) / (hm * hm)
    }

    private var validRecords: [BodyRecord] {
        records.filter { bmi(for: $0) != nil }
            .sorted { $0.dateTime < $1.dateTime }
    }

    private var periodStart: Date {
        cal.date(byAdding: .day, value: -period.rawValue, to: Date()) ?? Date()
    }
    private var periodRecords: [BodyRecord] { validRecords.filter { $0.dateTime >= periodStart } }

    private var dailyValues: [DailyLineValue] {
        let grouped = Dictionary(grouping: validRecords) { dayStart($0.dateTime) }
        return grouped.map { date, recs in
            let vals = recs.compactMap { bmi(for: $0) }
            let avg = vals.reduce(0.0, +) / Double(vals.count)
            return DailyLineValue(date: date, avg: avg)
        }.sorted { $0.date < $1.date }
    }

    private var selectedDayRecords: [BodyRecord] {
        guard let date = selectedDate else { return [] }
        let target = dayStart(date)
        return validRecords.filter { dayStart($0.dateTime) == target }
    }

    private var avgValue: Double? {
        let v = periodRecords.compactMap { bmi(for: $0) }
        guard !v.isEmpty else { return nil }
        return v.reduce(0.0, +) / Double(v.count)
    }
    private var minValue: Double? { periodRecords.compactMap { bmi(for: $0) }.min() }
    private var maxValue: Double? { periodRecords.compactMap { bmi(for: $0) }.max() }

    private var yearMinBMI: Double? {
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return validRecords.filter { $0.dateTime >= oneYearAgo }.compactMap { bmi(for: $0) }.min()
    }
    private var yearMaxBMI: Double? {
        let oneYearAgo = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return validRecords.filter { $0.dateTime >= oneYearAgo }.compactMap { bmi(for: $0) }.max()
    }

    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    var body: some View {
        PanelContainer {
            // ヘッダー
            HStack(alignment: .firstTextBaseline) {
                Text("BMI").font(.subheadline.weight(.semibold))
                Button {
                    showBMIInfo = true
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "info.circle")
                        Text("JASSO基準")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showBMIInfo, arrowEdge: .bottom) {
                    BMIStandardsPopover()
                }
                Spacer()
                if let avg = avgValue {
                    StatCell(label: "平均", value: fmt(avg))
                }
                if let mn = minValue, let mx = maxValue {
                    StatCell(label: "範囲", value: "\(fmt(mn))–\(fmt(mx))")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // チャート
            Chart {
                // BMI基準帯（背景）
                ForEach(bmiZones, id: \.label) { z in
                    RectangleMark(
                        yStart: .value("下限", z.min),
                        yEnd:   .value("上限", z.max)
                    )
                    .foregroundStyle(z.color)
                }

                ForEach(dailyValues) { d in
                    AreaMark(
                        x: .value("日時", d.date),
                        y: .value("BMI", d.avg)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [Color.cyan.opacity(0.25), Color.cyan.opacity(0.0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                }
                ForEach(dailyValues) { d in
                    LineMark(
                        x: .value("日時", d.date),
                        y: .value("BMI", d.avg)
                    )
                    .foregroundStyle(Color.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                ForEach(validRecords) { r in
                    if let b = bmi(for: r) {
                        PointMark(
                            x: .value("日時", dayStart(r.dateTime)),
                            y: .value("BMI", b)
                        )
                        .foregroundStyle(r.dateOpt.color)
                        .symbolSize(16)
                    }
                }
                if let date = selectedDate {
                    RuleMark(x: .value("選択", dayStart(date)))
                        .foregroundStyle(.gray.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .chartYTightDomain(minVal: yearMinBMI, maxVal: yearMaxBMI)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(fmt(v)).font(.caption2)
                        }
                    }
                }
            }
            .tapToSelectDay($selectedDate, validDays: Set(validRecords.map { dayStart($0.dateTime) }))
            .standardXAxis(period: period, scrollPosition: $scrollPosition, oldestDate: validRecords.first?.dateTime)
            .frame(height: 120)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            // 選択詳細
            if !selectedDayRecords.isEmpty {
                Divider()
                ForEach(selectedDayRecords) { r in
                    if let b = bmi(for: r) {
                        SelectionDetailRow(
                            record: r,
                            detail: "BMI \(fmt(b))",
                            color: r.dateOpt.color
                        )
                    }
                }
            }
        }
    }
}

// MARK: - BMI基準ポップアップ

private struct BMIStandardsPopover: View {
    private struct Row {
        let zone: BMIZone
        var rangeText: String {
            if zone.min <= 0  { return "< \(String(format: "%.1f", zone.max))" }
            if zone.max >= 60 { return "≥ \(String(format: "%.1f", zone.min))" }
            return "\(String(format: "%.1f", zone.min)) – \(String(format: "%.1f", zone.max))"
        }
    }
    private let rows = bmiZones.reversed().map { Row(zone: $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("JASSO肥満度分類")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            Divider()
            ForEach(rows, id: \.zone.label) { row in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(row.zone.swatch.opacity(0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5)
                        )
                        .frame(width: 18, height: 18)
                    Text(row.zone.label)
                        .font(.subheadline)
                    Spacer()
                    Text(row.rangeText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider().padding(.leading, 44)
            }
        }
        .frame(minWidth: 260)
        .presentationCompactAdaptation(.popover)
    }
}
