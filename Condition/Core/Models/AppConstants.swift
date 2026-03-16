// AppConstants.swift
// 旧 Global.h / MocEntity.h の定数群

import Foundation
import SwiftUI

// MARK: - #Predicate で参照可能なグローバル定数
// SwiftData の #Predicate マクロは @Model クラスの static プロパティを参照できないため
// ファイルスコープの let 定数として定義する

let bodyRecordGoalDate: Date = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var comps = DateComponents()
    comps.year = 2200; comps.month = 1; comps.day = 1
    comps.hour = 0; comps.minute = 0; comps.second = 0
    return cal.date(from: comps)!
}()

let bodyRecordMaxDate: Date = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var comps = DateComponents()
    comps.year = 2090; comps.month = 12; comps.day = 31
    comps.hour = 23; comps.minute = 59; comps.second = 59
    return cal.date(from: comps)!
}()

// MARK: - アプリ識別
enum AppConstants {
    static let productName      = "AzBodyNote"
    static let copyright        = "©2012 Azukid"
    static let unlockProductID  = "com.azukid.AzBodyNote.Unlock"

    // 通知名
    static let notificationRefreshAllViews = Notification.Name("RefreshAllViews")
    static let notificationRefetchAllData  = Notification.Name("RefetchAllDatabaseData")
    static let notificationAppDidBecomeActive = Notification.Name("AppDidBecomeActive")
}

// MARK: - 測定値の範囲・初期値（旧 E2_n* 定数群）
enum MeasureRange {
    // 血圧（上）mmHg
    static let bpHi = MeasureSpec(min: 30,  initVal: 120, max: 300, decimals: 0)
    // 血圧（下）mmHg
    static let bpLo = MeasureSpec(min: 20,  initVal: 80,  max: 200, decimals: 0)
    // 心拍数 bpm
    static let pulse = MeasureSpec(min: 10,  initVal: 65,  max: 200, decimals: 0)
    // 体重 x10 kg  (650 = 65.0 kg)
    static let weight = MeasureSpec(min: 0,   initVal: 650, max: 2000, decimals: 1)
    // 体温 x10 ℃  (365 = 36.5 ℃)
    static let temp = MeasureSpec(min: 310, initVal: 365, max: 429,  decimals: 1)
    // 歩数
    static let pedometer = MeasureSpec(min: 0,   initVal: 5000, max: 99999, decimals: 0)
    // 体脂肪率 x10 % (235 = 23.5 %)
    static let bodyFat = MeasureSpec(min: 0,   initVal: 235, max: 1000,  decimals: 1)
    // 骨格筋率 x10 % (285 = 28.5 %)
    static let skMuscle = MeasureSpec(min: 0,   initVal: 285, max: 1000,  decimals: 1)
}

struct MeasureSpec {
    let min: Int
    let initVal: Int
    let max: Int
    let decimals: Int   // 小数点桁数（0=整数表示、1=小数1桁）
}

// MARK: - 日付判定
enum DateOptConstants {
    static let aroundHour = 2   // 前後許容時間（旧 DateOpt_AroundHOUR）
    static let goalDateUTC = "2200-01-01T00:00:00"  // 目標値レコードの特殊日時
    static let maxDateUTC  = "2090-12-31T23:59:59"  // 最大入力許可日付
}

// MARK: - アプリカラー（旧 COLOR_* マクロ）
extension Color {
    static let azuki    = Color(red: 151/255, green:  80/255, blue:  77/255)
    static let azDark   = Color(red:  70/255, green:  70/255, blue:  70/255)
    static let azWhite  = Color(red: 250/255, green: 250/255, blue: 250/255)
    static let azBack   = Color(red: 220/255, green: 220/255, blue: 220/255)
    static let azEdit   = Color(red: 210/255, green: 220/255, blue: 210/255)
    static let azGoal   = Color(red: 210/255, green: 210/255, blue: 220/255)
}

// MARK: - グラフ・統計設定
enum GraphConstants {
    static let listPageLimit  = 50    // 旧 LIST_PAGE_LIMIT
    static let graphPageLimit = 50    // 旧 GRAPH_PAGE_LIMIT
    static let statDaysMax    = 70    // 旧 STAT_DAYS_MAX
    static let statDaysFree   = 7     // 旧 STAT_DAYS_FREE（無料制限）
    static let oneWidMin      = 30    // 旧 ONE_WID_MIN
    static let oneWidMax      = 80    // 旧 ONE_WID_MAX
}

// MARK: - グラフパネル種別（旧 EnumGraphs）
enum GraphKind: Int, CaseIterable, Identifiable, Codable {
    case bp      = 0
    case bpAvg   = 1
    case pulse   = 2
    case temp    = 3
    case weight  = 4
    case pedo    = 5
    case bodyFat = 6
    case skMuscle = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .bp:       return String(localized: "Graph_Bp",       defaultValue: "血圧")
        case .bpAvg:    return String(localized: "Graph_BpAvg",    defaultValue: "脈圧")
        case .pulse:    return String(localized: "Graph_Pulse",    defaultValue: "心拍数")
        case .temp:     return String(localized: "Graph_Temp",     defaultValue: "体温")
        case .weight:   return String(localized: "Graph_Weight",   defaultValue: "体重")
        case .pedo:     return String(localized: "Graph_Pedo",     defaultValue: "歩数")
        case .bodyFat:  return String(localized: "Graph_BodyFat",  defaultValue: "体脂肪率")
        case .skMuscle: return String(localized: "Graph_SkMuscle", defaultValue: "骨格筋率")
        }
    }

    /// 記録入力画面にも対応するフィールドかどうか（bpAvg はグラフ専用）
    var isRecordField: Bool { self != .bpAvg }
}
