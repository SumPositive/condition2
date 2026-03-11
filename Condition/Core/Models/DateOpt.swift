// DateOpt.swift
// 測定時の状況区分（旧 MocEntity.h の DateOpt enum 相当）

import Foundation

enum DateOpt: Int, CaseIterable, Codable {
    case wake  = 0  // 起床時
    case rest  = 1  // 安静時
    case down  = 2  // 就寝前
    case sleep = 3  // 就寝時

    var label: String {
        switch self {
        case .wake:  return String(localized: "DateOpt_Wake",  defaultValue: "起床時")
        case .rest:  return String(localized: "DateOpt_Rest",  defaultValue: "安静時")
        case .down:  return String(localized: "DateOpt_Down",  defaultValue: "就寝前")
        case .sleep: return String(localized: "DateOpt_Sleep", defaultValue: "就寝時")
        }
    }

    var shortLabel: String {
        switch self {
        case .wake:  return String(localized: "DateOpt_Wake_Short",  defaultValue: "起")
        case .rest:  return String(localized: "DateOpt_Rest_Short",  defaultValue: "安")
        case .down:  return String(localized: "DateOpt_Down_Short",  defaultValue: "前")
        case .sleep: return String(localized: "DateOpt_Sleep_Short", defaultValue: "眠")
        }
    }
}
