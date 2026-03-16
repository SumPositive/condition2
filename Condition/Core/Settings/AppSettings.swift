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
        GraphKind.weight.rawValue,   // 4
        GraphKind.temp.rawValue,     // 3
        GraphKind.bpAvg.rawValue,    // 1
        GraphKind.pedo.rawValue,     // 5
        GraphKind.bodyFat.rawValue,  // 6
        GraphKind.skMuscle.rawValue, // 7
    ] {
        didSet { kvs.set(graphPanelOrder, forKey: KVSKeys.settGraphs) }
    }
    /// 非表示フィールドの GraphKind.rawValue 集合（グラフ・記録入力の両方に適用）
    var hiddenFields: [Int] = [
        GraphKind.temp.rawValue,     // 3
        GraphKind.pedo.rawValue,     // 5
        GraphKind.bodyFat.rawValue,  // 6
        GraphKind.skMuscle.rawValue, // 7
    ] {
        didSet { kvs.set(hiddenFields, forKey: KVSKeys.settFieldHidden) }
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
    var graphBMITall: Int = 160 {
        didSet { kvs.set(graphBMITall, forKey: KVSKeys.settGraphBMITall) }
    }
    var graphBMI: Bool = false {
        didSet { kvs.set(graphBMI, forKey: KVSKeys.settGraphBMI) }
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
// MARK: - DateOpt 自動判定時刻（旧設定、マイグレーション用に保持）
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

    // MARK: - DateOpt 時刻マトリックス（24要素、-1=未割当→.restにフォールバック）
    var dateOptHourMap: [Int] = AppSettings.factoryDefaultHourMap {
        didSet { kvs.set(dateOptHourMap, forKey: KVSKeys.settDateOptHourMap) }
    }

    /// 出荷時初期値（画像定義）
    static let factoryDefaultHourMap: [Int] = [
        3, 3, 3,       // 0-2:   就寝時
        0, 0, 0, 0, 0, // 3-7:   起床時
        1, 1, 1,       // 8-10:  安静時
        4, 4, 4,       // 11-13: 運動前
        5, 5, 5,       // 14-16: 運動後
        1, 1, 1,       // 17-19: 安静時
        2, 2,          // 20-21: 就寝前
        3, 3,          // 22-23: 就寝時
    ]

    /// 旧設定（wakeHour/downHour/sleepHour）からのマイグレーション用
    static func makeDefaultHourMap(wake: Int, down: Int, sleep: Int) -> [Int] {
        var map = Array(repeating: -1, count: 24)
        let around = DateOptConstants.aroundHour
        for offset in -around..<around {
            map[(down  + offset + 24) % 24] = DateOpt.down.rawValue
        }
        for offset in -around..<around {
            map[(sleep + offset + 24) % 24] = DateOpt.sleep.rawValue
        }
        for offset in -around..<around {
            map[(wake  + offset + 24) % 24] = DateOpt.wake.rawValue
        }
        return map
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
    var goalBpPp: Int = 0 {
        didSet { kvs.set(goalBpPp, forKey: KVSKeys.goalBpPp) }
    }
    var goalBMI: Int = 0 {
        didSet { kvs.set(goalBMI, forKey: KVSKeys.goalBMI) }
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
        if let arr = kvs.array(forKey: KVSKeys.settFieldHidden) as? [Int] {
            hiddenFields = arr
        }
        let ow = kvs.longLong(forKey: KVSKeys.settGraphOneWid)
        if ow > 0 { graphOneWidth = Int(ow) }

        graphBpMean    = kvs.bool(forKey: KVSKeys.settGraphBpMean)
        graphBpPress   = kvs.bool(forKey: KVSKeys.settGraphBpPress)
        graphBMI       = kvs.bool(forKey: KVSKeys.settGraphBMI)
        let tall = kvs.longLong(forKey: KVSKeys.settGraphBMITall)
        if tall > 0 { graphBMITall = Int(tall) }

        let sd = kvs.longLong(forKey: KVSKeys.settStatDays)
        if sd > 0 { statDays = Int(sd) }
        statType        = Int(kvs.longLong(forKey: KVSKeys.settStatType))
        statShowAvg     = kvs.bool(forKey: KVSKeys.settStatAvgShow)
        statShowTimeLine = kvs.bool(forKey: KVSKeys.settStatTimeLine)
        statShow24HLine = kvs.bool(forKey: KVSKeys.settStat24HLine)

        goalEnabled     = kvs.bool(forKey: KVSKeys.bGoal)

        let wh = kvs.longLong(forKey: KVSKeys.dateOptWakeHour)
        if wh > 0 { wakeHour = Int(wh) }
        let rh = kvs.longLong(forKey: KVSKeys.dateOptRestHour)
        if rh > 0 { restHour = Int(rh) }
        let dh = kvs.longLong(forKey: KVSKeys.dateOptDownHour)
        if dh > 0 { downHour = Int(dh) }
        let sh = kvs.longLong(forKey: KVSKeys.dateOptSleepHour)
        if sh > 0 { sleepHour = Int(sh) }
        // 時刻マトリックス（保存済みを優先、旧設定があればマイグレーション、なければ出荷時初期値）
        if let arr = kvs.array(forKey: KVSKeys.settDateOptHourMap) as? [Int], arr.count == 24 {
            dateOptHourMap = arr
        } else if wh > 0 || dh > 0 || sh > 0 {
            dateOptHourMap = AppSettings.makeDefaultHourMap(wake: wakeHour, down: downHour, sleep: sleepHour)
        } else {
            dateOptHourMap = AppSettings.factoryDefaultHourMap
        }

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
        let gpp = kvs.longLong(forKey: KVSKeys.goalBpPp)
        if gpp > 0 { goalBpPp = Int(gpp) }
        let gbmi = kvs.longLong(forKey: KVSKeys.goalBMI)
        if gbmi > 0 { goalBMI = Int(gbmi) }

    }

    @objc nonisolated private func kvsDidChangeExternally(_ notification: Notification) {
        Task { @MainActor [self] in
            self.loadFromKVS()
        }
    }

    // MARK: - DateOpt 自動判定
    func autoDateOpt(for date: Date) -> DateOpt {
        let hour = Calendar(identifier: .gregorian).component(.hour, from: date)
        return DateOpt(rawValue: dateOptHourMap[hour]) ?? .rest
    }
}
