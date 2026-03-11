// ConditionTests.swift

import Testing
import Foundation
@testable import Condition

@Suite("ValueFormatter Tests")
struct ValueFormatterTests {

    @Test("整数値の変換")
    func integerFormat() {
        #expect(ValueFormatter.format(120, decimals: 0) == "120")
        #expect(ValueFormatter.format(0,   decimals: 0) == "")
        #expect(ValueFormatter.format(-1,  decimals: 0) == "")
    }

    @Test("小数1桁の変換")
    func decimal1Format() {
        #expect(ValueFormatter.format(650, decimals: 1) == "65.0")
        #expect(ValueFormatter.format(365, decimals: 1) == "36.5")
        #expect(ValueFormatter.format(235, decimals: 1) == "23.5")
    }
}

@Suite("DateOpt Tests")
struct DateOptTests {

    @Test("autoDateOpt: 起床時刻")
    @MainActor
    func wakeAutoDetect() {
        let settings = AppSettings.shared
        settings.wakeHour = 6
        let cal = Calendar(identifier: .gregorian)
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 6; comps.minute = 30
        let date = cal.date(from: comps)!
        #expect(settings.autoDateOpt(for: date) == .wake)
    }
}

@Suite("BodyRecord Tests")
struct BodyRecordTests {

    @Test("yearMonth 計算")
    func yearMonth() {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2024; comps.month = 3; comps.day = 15
        let date = cal.date(from: comps)!
        let record = BodyRecord(dateTime: date)
        #expect(record.yearMonth == 202403)
    }

    @Test("goalDate 判定")
    func goalDateDetection() {
        let normal = BodyRecord(dateTime: Date())
        let goal   = BodyRecord(dateTime: BodyRecord.goalDate)
        #expect(!normal.isGoalRecord)
        #expect(goal.isGoalRecord)
    }
}
