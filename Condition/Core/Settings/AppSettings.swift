// AppSettings.swift
// @Observable 設定ストア（iCloud KVS 同期）
// 旧 NSUbiquitousKeyValueStore の読み書きを集約

import Foundation
import Observation

@Observable
@MainActor
final class AppSettings {

    // MARK: - シングルトン
    static let shared = AppSettings()

    private let kvs = NSUbiquitousKeyValueStore.default
    private let ud  = UserDefaults.standard

    // MARK: - グラフ設定
    var graphPanelOrder: [Int] = [
        GraphKind.bp.rawValue,       // 0
        GraphKind.pulse.rawValue,    // 2
        GraphKind.temp.rawValue,     // 3
        GraphKind.bpAvg.rawValue,    // 1
        GraphKind.weight.rawValue,   // 4
        GraphKind.pedo.rawValue,     // 5
        GraphKind.bodyFat.rawValue,  // 6
        GraphKind.skMuscle.rawValue, // 7
    ] {
        didSet { kvs.set(graphPanelOrder, forKey: KVSKeys.settGraphs) }
    }
    var graphOneWidth: Int = 45 {
        didSet { kvs.set(graphOneWidth, forKey: KVSKeys.settGraphOneWid) }
    }
    var graphBpMean: Bool = false {
        didSet { kvs.set(graphBpMean, forKey: KVSKeys.settGraphBpMean) }
    }
    var graphBpPress: Bool = false {
        didSet { kvs.set(graphBpPress, forKey: KVSKeys.settGraphBpPress) }
    }
    var graphBMITall: Int = 0 {
        didSet { kvs.set(graphBMITall, forKey: KVSKeys.settGraphBMITall) }
    }

    // MARK: - 統計設定
    var statType: Int = 0 {
        didSet { kvs.set(statType, forKey: KVSKeys.settStatType) }
    }
    var statDays: Int = 7 {
        didSet { kvs.set(statDays, forKey: KVSKeys.settStatDays) }
    }
    var statShowAvg: Bool = true {
        didSet { kvs.set(statShowAvg, forKey: KVSKeys.settStatAvgShow) }
    }
    var statShowTimeLine: Bool = true {
        didSet { kvs.set(statShowTimeLine, forKey: KVSKeys.settStatTimeLine) }
    }
    var statShow24HLine: Bool = false {
        didSet { kvs.set(statShow24HLine, forKey: KVSKeys.settStat24HLine) }
    }

    // MARK: - 機能切替
    var goalEnabled: Bool = false {
        didSet { kvs.set(goalEnabled, forKey: KVSKeys.bGoal) }
    }
    var calendarEnabled: Bool = false {
        didSet { kvs.set(calendarEnabled, forKey: KVSKeys.bCalender) }
    }

    // MARK: - DateOpt 自動判定時刻
    var wakeHour: Int = 6 {
        didSet { kvs.set(wakeHour, forKey: KVSKeys.dateOptWakeHour) }
    }
    var restHour: Int = 12 {
        didSet { kvs.set(restHour, forKey: KVSKeys.dateOptRestHour) }
    }
    var downHour: Int = 21 {
        didSet { kvs.set(downHour, forKey: KVSKeys.dateOptDownHour) }
    }
    var sleepHour: Int = 23 {
        didSet { kvs.set(sleepHour, forKey: KVSKeys.dateOptSleepHour) }
    }

    // MARK: - 目標値
    var goalBpHi: Int = 0 {
        didSet { kvs.set(goalBpHi, forKey: KVSKeys.goalBpHi) }
    }
    var goalBpLo: Int = 0 {
        didSet { kvs.set(goalBpLo, forKey: KVSKeys.goalBpLo) }
    }
    var goalPulse: Int = 0 {
        didSet { kvs.set(goalPulse, forKey: KVSKeys.goalPulse) }
    }
    var goalWeight: Int = 0 {
        didSet { kvs.set(goalWeight, forKey: KVSKeys.goalWeight) }
    }
    var goalTemp: Int = 0 {
        didSet { kvs.set(goalTemp, forKey: KVSKeys.goalTemp) }
    }
    var goalPedometer: Int = 0 {
        didSet { kvs.set(goalPedometer, forKey: KVSKeys.goalPedometer) }
    }
    var goalBodyFat: Int = 0 {
        didSet { kvs.set(goalBodyFat, forKey: KVSKeys.goalBodyFat) }
    }
    var goalSkMuscle: Int = 0 {
        didSet { kvs.set(goalSkMuscle, forKey: KVSKeys.goalSkMuscle) }
    }

    // MARK: - カレンダー（UserDefaults: デバイス個別）
    var calendarID: String {
        get { ud.string(forKey: UDefKeys.calendarID) ?? "" }
        set { ud.set(newValue, forKey: UDefKeys.calendarID) }
    }
    var calendarTitle: String {
        get { ud.string(forKey: UDefKeys.calendarTitle) ?? "" }
        set { ud.set(newValue, forKey: UDefKeys.calendarTitle) }
    }

    // MARK: - HealthKit（UserDefaults: デバイス個別・@Observable 追跡対象にするため stored property）
    var hkEnabled: Bool = false {
        didSet { ud.set(hkEnabled, forKey: UDefKeys.hkEnabled) }
    }
    var hkDirection: Int = HKSyncDirection.both.rawValue {
        didSet { ud.set(hkDirection, forKey: UDefKeys.hkDirection) }
    }
    var hkTiming: Int = HKSyncTiming.automatic.rawValue {
        didSet { ud.set(hkTiming, forKey: UDefKeys.hkTiming) }
    }

    // MARK: - 購入状態（制限解除済み）
    let isUnlocked: Bool = true

    // MARK: - 初期化

    private init() {
        loadFromKVS()
        // UserDefaults デフォルト値登録（キー未登録時は 0 が返るため明示的に設定）
        ud.register(defaults: [
            UDefKeys.hkDirection: HKSyncDirection.both.rawValue,
            UDefKeys.hkTiming:    HKSyncTiming.automatic.rawValue,
        ])
        // UserDefaults（デバイス個別）読み込み
        hkEnabled   = ud.bool(forKey: UDefKeys.hkEnabled)
        hkDirection = ud.integer(forKey: UDefKeys.hkDirection)
        hkTiming    = ud.integer(forKey: UDefKeys.hkTiming)
        // iCloud KVS 外部変更通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvsDidChangeExternally),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs
        )
        kvs.synchronize()
    }

    // MARK: - KVS ロード

    func loadFromKVS() {
        if let arr = kvs.array(forKey: KVSKeys.settGraphs) as? [Int], !arr.isEmpty {
            graphPanelOrder = arr
        }
        let ow = kvs.longLong(forKey: KVSKeys.settGraphOneWid)
        if ow > 0 { graphOneWidth = Int(ow) }

        graphBpMean    = kvs.bool(forKey: KVSKeys.settGraphBpMean)
        graphBpPress   = kvs.bool(forKey: KVSKeys.settGraphBpPress)
        let tall = kvs.longLong(forKey: KVSKeys.settGraphBMITall)
        if tall > 0 { graphBMITall = Int(tall) }

        let sd = kvs.longLong(forKey: KVSKeys.settStatDays)
        if sd > 0 { statDays = Int(sd) }
        statType        = Int(kvs.longLong(forKey: KVSKeys.settStatType))
        statShowAvg     = kvs.bool(forKey: KVSKeys.settStatAvgShow)
        statShowTimeLine = kvs.bool(forKey: KVSKeys.settStatTimeLine)
        statShow24HLine = kvs.bool(forKey: KVSKeys.settStat24HLine)

        goalEnabled     = kvs.bool(forKey: KVSKeys.bGoal)
        calendarEnabled = kvs.bool(forKey: KVSKeys.bCalender)

        let wh = kvs.longLong(forKey: KVSKeys.dateOptWakeHour)
        if wh > 0 { wakeHour = Int(wh) }
        let rh = kvs.longLong(forKey: KVSKeys.dateOptRestHour)
        if rh > 0 { restHour = Int(rh) }
        let dh = kvs.longLong(forKey: KVSKeys.dateOptDownHour)
        if dh > 0 { downHour = Int(dh) }
        let sh = kvs.longLong(forKey: KVSKeys.dateOptSleepHour)
        if sh > 0 { sleepHour = Int(sh) }

        let gbh = kvs.longLong(forKey: KVSKeys.goalBpHi)
        if gbh > 0 { goalBpHi = Int(gbh) }
        let gbl = kvs.longLong(forKey: KVSKeys.goalBpLo)
        if gbl > 0 { goalBpLo = Int(gbl) }
        let gp = kvs.longLong(forKey: KVSKeys.goalPulse)
        if gp > 0 { goalPulse = Int(gp) }
        let gw = kvs.longLong(forKey: KVSKeys.goalWeight)
        if gw > 0 { goalWeight = Int(gw) }
        let gt = kvs.longLong(forKey: KVSKeys.goalTemp)
        if gt > 0 { goalTemp = Int(gt) }
        let gped = kvs.longLong(forKey: KVSKeys.goalPedometer)
        if gped > 0 { goalPedometer = Int(gped) }
        let gbf = kvs.longLong(forKey: KVSKeys.goalBodyFat)
        if gbf > 0 { goalBodyFat = Int(gbf) }
        let gsk = kvs.longLong(forKey: KVSKeys.goalSkMuscle)
        if gsk > 0 { goalSkMuscle = Int(gsk) }

    }

    @objc nonisolated private func kvsDidChangeExternally(_ notification: Notification) {
        Task { @MainActor [self] in
            self.loadFromKVS()
        }
    }

    // MARK: - DateOpt 自動判定（旧 integerDateOpt: 相当）
    func autoDateOpt(for date: Date) -> DateOpt {
        let cal = Calendar(identifier: .gregorian)
        let hour = cal.component(.hour, from: date)
        let around = DateOptConstants.aroundHour

        func inRange(_ center: Int, _ h: Int) -> Bool {
            var c = center
            var hh = h
            if c - around < 0 { c += around; hh += around }
            return (c - around) <= hh && hh < (c + around)
        }

        if inRange(wakeHour, hour)  { return .wake }
        if inRange(sleepHour, hour) { return .sleep }
        if inRange(downHour, hour)  { return .down }
        return .rest
    }
}
