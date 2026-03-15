// HealthKitService.swift
// HealthKit 連携サービス

import Foundation
import HealthKit
import OSLog

private let logger = Logger(subsystem: "com.azukid.AzBodyNote", category: "HealthKit")

// MARK: - 同期方向・タイミング

enum HKSyncDirection: Int, CaseIterable {
    case writeOnly = 0  // アプリ → HealthKit
    case readOnly  = 1  // HealthKit → アプリ
    case both      = 2  // 双方向

    var canWrite: Bool { self == .writeOnly || self == .both }
    var canRead:  Bool { self == .readOnly  || self == .both }
}

enum HKSyncTiming: Int, CaseIterable {
    case automatic = 0  // 自動（保存時 / 画面表示時）
    case manual    = 1  // 手動（ボタン操作）
}

// MARK: - データ転送用構造体

struct HealthKitValues {
    var date: Date
    var bpHi:    Int = 0   // mmHg        (0 = 未記録)
    var bpLo:    Int = 0   // mmHg
    var pulse:   Int = 0   // bpm
    var temp:    Int = 0   // ×10 ℃      例: 365 = 36.5℃
    var weight:  Int = 0   // ×10 kg      例: 650 = 65.0kg
    var steps:   Int = 0   // 歩
    var bodyFat: Int = 0   // ×10 %       例: 235 = 23.5%
}

// MARK: - サービス本体

@Observable
@MainActor
final class HealthKitService {

    static let shared = HealthKitService()

    private let store = HKHealthStore()

    var isAuthorized = false
    /// アプリ起動中に一括インポートを実行済みかどうか
    static var sessionImportDone = false

    private static let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.bloodPressureSystolic),
        HKQuantityType(.bloodPressureDiastolic),
        HKQuantityType(.heartRate),
        HKQuantityType(.bodyTemperature),
        HKQuantityType(.bodyMass),
        HKQuantityType(.stepCount),
        HKQuantityType(.bodyFatPercentage),
    ]

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.bloodPressureSystolic),
        HKQuantityType(.bloodPressureDiastolic),
        HKQuantityType(.heartRate),
        HKQuantityType(.bodyTemperature),
        HKQuantityType(.bodyMass),
        HKQuantityType(.stepCount),
        HKQuantityType(.bodyFatPercentage),
    ]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private init() {}

    // MARK: - 権限リクエスト

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            isAuthorized = true
            logger.info("HealthKit 権限リクエスト完了")
        } catch {
            logger.error("HealthKit 権限エラー: \(error.localizedDescription)")
        }
    }

    func checkAuthorization() {
        guard isAvailable else { return }
        let status = store.authorizationStatus(for: HKQuantityType(.bloodPressureSystolic))
        isAuthorized = status == .sharingAuthorized
    }

    // MARK: - 書き込み

    func write(_ values: HealthKitValues) async {
        guard isAvailable else { return }

        var samples: [HKSample] = []
        let date = values.date

        // 血圧（Correlation）
        if values.bpHi > 0 && values.bpLo > 0 {
            let systolic = HKQuantitySample(
                type: HKQuantityType(.bloodPressureSystolic),
                quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: Double(values.bpHi)),
                start: date, end: date)
            let diastolic = HKQuantitySample(
                type: HKQuantityType(.bloodPressureDiastolic),
                quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: Double(values.bpLo)),
                start: date, end: date)
            let bp = HKCorrelation(
                type: HKCorrelationType(.bloodPressure),
                start: date, end: date,
                objects: [systolic, diastolic])
            samples.append(bp)
        }

        // 脈拍
        if values.pulse > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: Double(values.pulse)),
                start: date, end: date))
        }

        // 体温
        if values.temp > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyTemperature),
                quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: Double(values.temp) / 10.0),
                start: date, end: date))
        }

        // 体重
        if values.weight > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyMass),
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: Double(values.weight) / 10.0),
                start: date, end: date))
        }

        // 歩数
        if values.steps > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.stepCount),
                quantity: HKQuantity(unit: .count(), doubleValue: Double(values.steps)),
                start: date, end: date))
        }

        // 体脂肪率（HKUnit.percent() は 0–100 のパーセント値）
        if values.bodyFat > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyFatPercentage),
                quantity: HKQuantity(unit: .percent(), doubleValue: Double(values.bodyFat) / 10.0 / 100.0),
                start: date, end: date))
        }

        guard !samples.isEmpty else { return }

        do {
            try await store.save(samples)
            logger.info("HealthKit 書き込み完了: \(samples.count) サンプル")
        } catch {
            logger.error("HealthKit 書き込み失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - 読み込み

    /// 指定日時より前の最新サンプルを取得（歩数は当日合計）
    func readLatest(before date: Date) async -> HealthKitValues {
        guard isAvailable else { return HealthKitValues(date: date) }

        var v = HealthKitValues(date: date)

        // 血圧
        if let bp = await mostRecentBloodPressure(before: date) {
            v.bpHi = bp.0
            v.bpLo = bp.1
        }

        // 脈拍
        if let s = await mostRecentQuantity(.heartRate, before: date) {
            v.pulse = Int(s.quantity.doubleValue(for: HKUnit(from: "count/min")))
        }

        // 体温
        if let s = await mostRecentQuantity(.bodyTemperature, before: date) {
            v.temp = Int(s.quantity.doubleValue(for: .degreeCelsius()) * 10.0)
        }

        // 体重
        if let s = await mostRecentQuantity(.bodyMass, before: date) {
            v.weight = Int(s.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 10.0)
        }

        // 歩数（当日合計）
        if let steps = await stepCountForDay(of: date) {
            v.steps = steps
        }

        // 体脂肪率
        if let s = await mostRecentQuantity(.bodyFatPercentage, before: date) {
            // percent() は内部的に fraction (0–1) で格納されるため ×100×10
            v.bodyFat = Int(s.quantity.doubleValue(for: .percent()) * 100.0 * 10.0)
        }

        return v
    }

    // MARK: - Private helpers

    private func mostRecentQuantity(
        _ id: HKQuantityTypeIdentifier,
        before date: Date
    ) async -> HKQuantitySample? {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: date)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        return try? await descriptor.result(for: store).first
    }

    private func mostRecentBloodPressure(before date: Date) async -> (Int, Int)? {
        let type = HKCorrelationType(.bloodPressure)
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: date)
        return await withCheckedContinuation { continuation in
            let query = HKCorrelationQuery(
                type: type,
                predicate: predicate,
                samplePredicates: nil
            ) { _, results, error in
                guard error == nil,
                      let correlation = results?.sorted(by: { $0.endDate > $1.endDate }).first
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let systolic = correlation.objects
                    .compactMap { $0 as? HKQuantitySample }
                    .first { $0.quantityType == HKQuantityType(.bloodPressureSystolic) }
                let diastolic = correlation.objects
                    .compactMap { $0 as? HKQuantitySample }
                    .first { $0.quantityType == HKQuantityType(.bloodPressureDiastolic) }
                guard let s = systolic, let d = diastolic else {
                    continuation.resume(returning: nil)
                    return
                }
                let hi = Int(s.quantity.doubleValue(for: .millimeterOfMercury()))
                let lo = Int(d.quantity.doubleValue(for: .millimeterOfMercury()))
                continuation.resume(returning: (hi, lo))
            }
            self.store.execute(query)
        }
    }

    private func stepCountForDay(of date: Date) async -> Int? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                guard error == nil, let sum = result?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Int(sum.doubleValue(for: .count())))
            }
            self.store.execute(query)
        }
    }

    // MARK: - 期間一括読み込み

    /// 指定期間のデータを日別に集約して返す（日ごとに最新サンプルを採用）
    func readDailySamples(from startDate: Date, to endDate: Date) async -> [HealthKitValues] {
        guard isAvailable else { return [] }
        let cal = Calendar.current
        func key(_ d: Date) -> Date { cal.startOfDay(for: d) }

        var byDay: [Date: HealthKitValues] = [:]

        // 血圧（日ごと最新）
        for (date, hi, lo) in (await allBPSamples(from: startDate, to: endDate)).reversed() {
            let k = key(date)
            var v = byDay[k] ?? HealthKitValues(date: k)
            if v.bpHi == 0 { v.bpHi = hi; v.bpLo = lo }
            byDay[k] = v
        }
        // 脈拍
        for (date, val) in (await allQtySamples(.heartRate, from: startDate, to: endDate, unit: HKUnit(from: "count/min"))).reversed() {
            let k = key(date); var v = byDay[k] ?? HealthKitValues(date: k)
            if v.pulse == 0 { v.pulse = Int(val) }
            byDay[k] = v
        }
        // 体温
        for (date, val) in (await allQtySamples(.bodyTemperature, from: startDate, to: endDate, unit: .degreeCelsius())).reversed() {
            let k = key(date); var v = byDay[k] ?? HealthKitValues(date: k)
            if v.temp == 0 { v.temp = Int(val * 10) }
            byDay[k] = v
        }
        // 体重
        for (date, val) in (await allQtySamples(.bodyMass, from: startDate, to: endDate, unit: .gramUnit(with: .kilo))).reversed() {
            let k = key(date); var v = byDay[k] ?? HealthKitValues(date: k)
            if v.weight == 0 { v.weight = Int(val * 10) }
            byDay[k] = v
        }
        // 体脂肪率
        for (date, val) in (await allQtySamples(.bodyFatPercentage, from: startDate, to: endDate, unit: .percent())).reversed() {
            let k = key(date); var v = byDay[k] ?? HealthKitValues(date: k)
            if v.bodyFat == 0 { v.bodyFat = Int(val * 100 * 10) }
            byDay[k] = v
        }
        // 歩数（日別合計）
        for (date, steps) in await allStepsByDay(from: startDate, to: endDate) {
            let k = key(date); var v = byDay[k] ?? HealthKitValues(date: k)
            v.steps = steps
            byDay[k] = v
        }

        return byDay.values
            .filter { $0.bpHi > 0 || $0.pulse > 0 || $0.temp > 0 || $0.weight > 0 || $0.steps > 0 || $0.bodyFat > 0 }
            .sorted { $0.date < $1.date }
    }

    private func allBPSamples(from start: Date, to end: Date) async -> [(Date, Int, Int)] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKCorrelationQuery(
                type: HKCorrelationType(.bloodPressure),
                predicate: predicate,
                samplePredicates: nil
            ) { _, results, _ in
                let pairs = (results ?? [])
                    .sorted { $0.endDate < $1.endDate }
                    .compactMap { corr -> (Date, Int, Int)? in
                        let objs = corr.objects.compactMap { $0 as? HKQuantitySample }
                        guard let sys = objs.first(where: { $0.quantityType == HKQuantityType(.bloodPressureSystolic) }),
                              let dia = objs.first(where: { $0.quantityType == HKQuantityType(.bloodPressureDiastolic) })
                        else { return nil }
                        return (corr.endDate,
                                Int(sys.quantity.doubleValue(for: .millimeterOfMercury())),
                                Int(dia.quantity.doubleValue(for: .millimeterOfMercury())))
                    }
                continuation.resume(returning: pairs)
            }
            self.store.execute(query)
        }
    }

    private func allQtySamples(
        _ id: HKQuantityTypeIdentifier,
        from start: Date, to end: Date,
        unit: HKUnit
    ) async -> [(Date, Double)] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)])
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { ($0.endDate, $0.quantity.doubleValue(for: unit)) }
    }

    private func allStepsByDay(from start: Date, to end: Date) async -> [(Date, Int)] {
        let cal = Calendar.current
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: cal.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var result: [(Date, Int)] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let sum = stats.sumQuantity() {
                        result.append((stats.startDate, Int(sum.doubleValue(for: .count()))))
                    }
                }
                continuation.resume(returning: result)
            }
            self.store.execute(query)
        }
    }
}
