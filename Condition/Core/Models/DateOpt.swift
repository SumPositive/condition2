// DateOpt.swift
// 測定時の状況区分（旧 MocEntity.h の DateOpt enum 相当）

import Foundation
import SwiftUI

enum DateOpt: Int, CaseIterable, Codable {
    case wake        = 0  // 起床時
    case rest        = 1  // 安静時
    case down        = 2  // 就寝前
    case sleep       = 3  // 就寝時
    case preExercise = 4  // 運動前
    case postExercise = 5 // 運動後

    var label: String {
        switch self {
        case .wake:         return String(localized: "DateOpt_Wake",         defaultValue: "起床時")
        case .rest:         return String(localized: "DateOpt_Rest",         defaultValue: "安静時")
        case .down:         return String(localized: "DateOpt_Down",         defaultValue: "就寝前")
        case .sleep:        return String(localized: "DateOpt_Sleep",        defaultValue: "就寝時")
        case .preExercise:  return String(localized: "DateOpt_PreExercise",  defaultValue: "運動前")
        case .postExercise: return String(localized: "DateOpt_PostExercise", defaultValue: "運動後")
        }
    }

    var icon: String {
        switch self {
        case .wake:         return "sun.horizon.fill"
        case .rest:         return "heart.fill"
        case .down:         return "moon.fill"
        case .sleep:        return "moon.zzz.fill"
        case .preExercise:  return "figure.run"
        case .postExercise: return "figure.walk"
        }
    }

    var color: Color {
        switch self {
        case .wake:         return .green
        case .rest:         return .blue
        case .down:         return .orange
        case .sleep:        return .purple
        case .preExercise:  return .teal
        case .postExercise: return .red
        }
    }

    var shortLabel: String {
        switch self {
        case .wake:         return String(localized: "DateOpt_Wake_Short",         defaultValue: "起")
        case .rest:         return String(localized: "DateOpt_Rest_Short",         defaultValue: "安")
        case .down:         return String(localized: "DateOpt_Down_Short",         defaultValue: "前")
        case .sleep:        return String(localized: "DateOpt_Sleep_Short",        defaultValue: "眠")
        case .preExercise:  return String(localized: "DateOpt_PreExercise_Short",  defaultValue: "運前")
        case .postExercise: return String(localized: "DateOpt_PostExercise_Short", defaultValue: "運後")
        }
    }
}

// MARK: - データ入力元

enum RecordDataSource: Int {
    case appInput    = 0  // このアプリで入力された記録です
    case appModified = 1  // このアプリで入力後に変更された記録です
    case hkImport    = 2  // ヘルスケアから読み込まれた記録です
    case hkModified  = 3  // ヘルスケアから読み込まれた後に変更された記録です

    var icon: String {
        switch self {
        case .appInput:    return "app"
        case .appModified: return "app.fill"
        case .hkImport:    return "heart"
        case .hkModified:  return "heart.fill"
        }
    }

    var color: Color {
        return .secondary
    }

    var label: String {
        switch self {
        case .appInput:    return String(localized: "DataSource_AppInput",    defaultValue: "このアプリで入力された記録です")
        case .appModified: return String(localized: "DataSource_AppModified", defaultValue: "このアプリで入力後に変更された記録です")
        case .hkImport:    return String(localized: "DataSource_HKImport",    defaultValue: "ヘルスケアから読み込まれた記録です")
        case .hkModified:  return String(localized: "DataSource_HKModified",  defaultValue: "ヘルスケアから読み込まれた後に変更された記録です。ヘルスケアに対しては変更や削除ができず常に追加されます。ヘルスケア側で重複する記録が不要ならば削除してください")
        }
    }
}
