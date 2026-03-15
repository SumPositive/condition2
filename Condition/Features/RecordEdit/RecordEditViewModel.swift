// RecordEditViewModel.swift
// 記録編集 ViewModel（旧 E2editTVC のビジネスロジック相当）

import Foundation
import SwiftData
import Observation

enum EditMode {
    case addNew
    case edit(BodyRecord)
    case goalEdit
}

@Observable
@MainActor
final class RecordEditViewModel {

    // MARK: - 編集フィールド
    var dateTime: Date
    var dateOpt: DateOpt
    var bCaution: Bool
    var sNote1: String
    var sNote2: String
    var sEquipment: String

    var nBpHi_mmHg: Int
    var nBpLo_mmHg: Int
    var nPulse_bpm: Int
    var nTemp_10c: Int
    var nWeight_10Kg: Int
    var nPedometer: Int
    var nBodyFat_10p: Int
    var nSkMuscle_10p: Int

    // MARK: - 入力有効フラグ
    var bpHiEnabled:      Bool
    var bpLoEnabled:      Bool
    var pulseEnabled:     Bool
    var weightEnabled:    Bool
    var tempEnabled:      Bool
    var pedometerEnabled: Bool
    var bodyFatEnabled:   Bool
    var skMuscleEnabled:  Bool

    // MARK: - 状態
    var isModified: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var isLoadingFromHK: Bool = false
    var dataSource: RecordDataSource = .appInput

    let mode: EditMode
    private var originalRecord: BodyRecord?

    // MARK: - 初期化

    init(mode: EditMode) {
        self.mode = mode

        let settings = AppSettings.shared

        switch mode {
        case .addNew:
            let now = Date()
            dateTime    = now
            dateOpt     = settings.autoDateOpt(for: now)
            bCaution    = false
            sNote1      = ""
            sNote2      = ""
            sEquipment  = ""
            nBpHi_mmHg  = MeasureRange.bpHi.initVal
            nBpLo_mmHg  = MeasureRange.bpLo.initVal
            nPulse_bpm  = MeasureRange.pulse.initVal
            nTemp_10c   = MeasureRange.temp.initVal
            nWeight_10Kg = MeasureRange.weight.initVal
            nPedometer   = MeasureRange.pedometer.initVal
            nBodyFat_10p  = MeasureRange.bodyFat.initVal
            nSkMuscle_10p = MeasureRange.skMuscle.initVal
            bpHiEnabled      = true
            bpLoEnabled      = true
            pulseEnabled     = false
            weightEnabled    = false
            tempEnabled      = false
            pedometerEnabled = false
            bodyFatEnabled   = false
            skMuscleEnabled  = false

        case .edit(let record):
            originalRecord = record
            dataSource  = record.dataSource
            dateTime    = record.dateTime
            dateOpt     = record.dateOpt
            bCaution    = record.bCaution
            sNote1      = record.sNote1
            sNote2      = record.sNote2
            sEquipment  = record.sEquipment
            nBpHi_mmHg  = record.nBpHi_mmHg  > 0 ? record.nBpHi_mmHg  : MeasureRange.bpHi.initVal
            nBpLo_mmHg  = record.nBpLo_mmHg  > 0 ? record.nBpLo_mmHg  : MeasureRange.bpLo.initVal
            nPulse_bpm  = record.nPulse_bpm   > 0 ? record.nPulse_bpm  : MeasureRange.pulse.initVal
            nTemp_10c   = record.nTemp_10c    > 0 ? record.nTemp_10c   : MeasureRange.temp.initVal
            nWeight_10Kg = record.nWeight_10Kg > 0 ? record.nWeight_10Kg : MeasureRange.weight.initVal
            nPedometer   = record.nPedometer   > 0 ? record.nPedometer  : MeasureRange.pedometer.initVal
            nBodyFat_10p  = record.nBodyFat_10p  > 0 ? record.nBodyFat_10p  : MeasureRange.bodyFat.initVal
            nSkMuscle_10p = record.nSkMuscle_10p > 0 ? record.nSkMuscle_10p : MeasureRange.skMuscle.initVal
            bpHiEnabled      = record.nBpHi_mmHg   > 0
            bpLoEnabled      = record.nBpLo_mmHg   > 0
            pulseEnabled     = record.nPulse_bpm    > 0
            weightEnabled    = record.nWeight_10Kg  > 0
            tempEnabled      = record.nTemp_10c     > 0
            pedometerEnabled = record.nPedometer    > 0
            bodyFatEnabled   = record.nBodyFat_10p  > 0
            skMuscleEnabled  = record.nSkMuscle_10p > 0

        case .goalEdit:
            let settings = AppSettings.shared
            dateTime    = BodyRecord.goalDate
            dateOpt     = .rest
            bCaution    = false
            sNote1      = ""
            sNote2      = ""
            sEquipment  = ""
            nBpHi_mmHg  = settings.goalBpHi
            nBpLo_mmHg  = settings.goalBpLo
            nPulse_bpm  = settings.goalPulse
            nTemp_10c   = settings.goalTemp
            nWeight_10Kg = settings.goalWeight
            nPedometer   = settings.goalPedometer
            nBodyFat_10p  = settings.goalBodyFat
            nSkMuscle_10p = settings.goalSkMuscle
            bpHiEnabled      = true
            bpLoEnabled      = true
            pulseEnabled     = true
            weightEnabled    = true
            tempEnabled      = true
            pedometerEnabled = true
            bodyFatEnabled   = true
            skMuscleEnabled  = true
        }
    }

    // MARK: - 前回値ロード（旧 setE2recordPrev 相当）

    func loadPreviousValues(context: ModelContext) {
        guard case .addNew = mode else { return }

        let now = dateTime
        let opt = dateOpt.rawValue

        // 各フィールドを前回値で初期化（0=未入力の場合のみ）
        let descriptor = FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.dateTime < now && $0.dateTime < bodyRecordGoalDate },
            sortBy: [SortDescriptor(\BodyRecord.dateTime, order: .reverse)]
        )

        guard let allPrev = try? context.fetch(descriptor) else { return }

        // 血圧・心拍数は DateOpt 一致優先
        if nBpHi_mmHg == MeasureRange.bpHi.initVal {
            nBpHi_mmHg = allPrev
                .filter { $0.nDateOpt == opt && $0.nBpHi_mmHg > 0 }
                .first
                .map { $0.nBpHi_mmHg } ?? MeasureRange.bpHi.initVal
        }
        if nBpLo_mmHg == MeasureRange.bpLo.initVal {
            nBpLo_mmHg = allPrev
                .filter { $0.nDateOpt == opt && $0.nBpLo_mmHg > 0 }
                .first
                .map { $0.nBpLo_mmHg } ?? MeasureRange.bpLo.initVal
        }
        if nPulse_bpm == MeasureRange.pulse.initVal {
            nPulse_bpm = allPrev
                .filter { $0.nDateOpt == opt && $0.nPulse_bpm > 0 }
                .first
                .map { $0.nPulse_bpm } ?? MeasureRange.pulse.initVal
        }

        // 体重・体温・歩数・体脂肪・骨格筋は日時順のみ
        if nWeight_10Kg == MeasureRange.weight.initVal {
            nWeight_10Kg = allPrev.first { $0.nWeight_10Kg > 0 }.map { $0.nWeight_10Kg } ?? MeasureRange.weight.initVal
        }
        if nTemp_10c == MeasureRange.temp.initVal {
            nTemp_10c = allPrev.first { $0.nTemp_10c > 0 }.map { $0.nTemp_10c } ?? MeasureRange.temp.initVal
        }
        if nPedometer == MeasureRange.pedometer.initVal {
            nPedometer = allPrev.first { $0.nPedometer > 0 }.map { $0.nPedometer } ?? MeasureRange.pedometer.initVal
        }
        if nBodyFat_10p == MeasureRange.bodyFat.initVal {
            nBodyFat_10p = allPrev.first { $0.nBodyFat_10p > 0 }.map { $0.nBodyFat_10p } ?? MeasureRange.bodyFat.initVal
        }
        if nSkMuscle_10p == MeasureRange.skMuscle.initVal {
            nSkMuscle_10p = allPrev.first { $0.nSkMuscle_10p > 0 }.map { $0.nSkMuscle_10p } ?? MeasureRange.skMuscle.initVal
        }

        // 直前レコードのスイッチ状態を引き継ぐ
        let prevBp   = allPrev.filter { $0.nDateOpt == opt }.first ?? allPrev.first
        let prevBody = allPrev.first
        if let p = prevBp {
            bpHiEnabled  = p.nBpHi_mmHg  > 0
            bpLoEnabled  = p.nBpLo_mmHg  > 0
            pulseEnabled = p.nPulse_bpm   > 0
        }
        if let p = prevBody {
            weightEnabled    = p.nWeight_10Kg  > 0
            tempEnabled      = p.nTemp_10c     > 0
            pedometerEnabled = p.nPedometer    > 0
            bodyFatEnabled   = p.nBodyFat_10p  > 0
            skMuscleEnabled  = p.nSkMuscle_10p > 0
        }
    }

    // MARK: - 日付変更時に DateOpt を自動更新

    func onDateChanged() {
        if case .addNew = mode {
            dateOpt = AppSettings.shared.autoDateOpt(for: dateTime)
        }
        isModified = true
    }

    // MARK: - 保存（旧 actionSave 相当）

    func save(context: ModelContext) throws {
        isSaving = true
        defer { isSaving = false }

        switch mode {
        case .addNew:
            let record = BodyRecord(dateTime: dateTime, dateOpt: dateOpt)
            record.dataSource = .appInput
            applyFields(to: record)
            context.insert(record)

        case .edit(let record):
            record.dateTime = dateTime
            record.dateOpt  = dateOpt
            applyFields(to: record)
            switch record.dataSource {
            case .appInput:  record.dataSource = .appModified
            case .hkImport:  record.dataSource = .hkModified
            default: break
            }

        case .goalEdit:
            let s = AppSettings.shared
            s.goalBpHi      = nBpHi_mmHg
            s.goalBpLo      = nBpLo_mmHg
            s.goalPulse     = nPulse_bpm
            s.goalTemp      = nTemp_10c
            s.goalWeight    = nWeight_10Kg
            s.goalPedometer = nPedometer
            s.goalBodyFat   = nBodyFat_10p
            s.goalSkMuscle  = nSkMuscle_10p
        }

        try context.save()
        writeToHealthKitIfAutomatic()
        isModified = false
    }

    private func writeToHealthKitIfAutomatic() {
        if case .goalEdit = mode { return }
        let s = AppSettings.shared
        guard s.hkEnabled,
              HKSyncDirection(rawValue: s.hkDirection)?.canWrite == true,
              HKSyncTiming(rawValue: s.hkTiming) == .automatic else { return }
        Task { await HealthKitService.shared.write(currentHealthKitValues()) }
    }

    // MARK: - 削除

    func delete(record: BodyRecord, context: ModelContext) throws {
        context.delete(record)
        try context.save()
    }

    // MARK: - フィールド適用

    private func applyFields(to record: BodyRecord) {
        record.bCaution      = bCaution
        record.sNote1        = sNote1
        record.sNote2        = sNote2
        record.sEquipment    = sEquipment
        record.nBpHi_mmHg    = bpHiEnabled      ? nBpHi_mmHg   : 0
        record.nBpLo_mmHg    = bpLoEnabled      ? nBpLo_mmHg   : 0
        record.nPulse_bpm    = pulseEnabled     ? nPulse_bpm   : 0
        record.nTemp_10c     = tempEnabled      ? nTemp_10c    : 0
        record.nWeight_10Kg  = weightEnabled    ? nWeight_10Kg  : 0
        record.nPedometer    = pedometerEnabled ? nPedometer   : 0
        record.nBodyFat_10p  = bodyFatEnabled   ? nBodyFat_10p  : 0
        record.nSkMuscle_10p = skMuscleEnabled  ? nSkMuscle_10p : 0
    }

    // MARK: - HealthKit 連携

    /// HealthKit から最新値を読み込んでフォームに反映
    func loadFromHealthKit() async {
        guard case .addNew = mode else { return }
        isLoadingFromHK = true
        defer { isLoadingFromHK = false }

        let values = await HealthKitService.shared.readLatest(
            before: dateTime,
            hiddenFields: Set(AppSettings.shared.hiddenFields)
        )
        applyHealthKitValues(values)
    }

    /// HealthKit へ現在のフォーム値を書き込み
    func writeToHealthKit() {
        let s = AppSettings.shared
        guard s.hkEnabled, HKSyncDirection(rawValue: s.hkDirection)?.canWrite == true else { return }
        Task {
            await HealthKitService.shared.write(currentHealthKitValues())
        }
    }

    private func currentHealthKitValues() -> HealthKitValues {
        let hidden = Set(AppSettings.shared.hiddenFields)
        func active(_ kind: GraphKind, _ flag: Bool) -> Bool { flag && !hidden.contains(kind.rawValue) }
        return HealthKitValues(
            date:    dateTime,
            bpHi:    active(.bp,      bpHiEnabled)      ? nBpHi_mmHg   : 0,
            bpLo:    active(.bp,      bpLoEnabled)      ? nBpLo_mmHg   : 0,
            pulse:   active(.pulse,   pulseEnabled)     ? nPulse_bpm   : 0,
            temp:    active(.temp,    tempEnabled)      ? nTemp_10c    : 0,
            weight:  active(.weight,  weightEnabled)    ? nWeight_10Kg  : 0,
            steps:   active(.pedo,    pedometerEnabled) ? nPedometer   : 0,
            bodyFat: active(.bodyFat, bodyFatEnabled)   ? nBodyFat_10p  : 0
        )
    }

    private func applyHealthKitValues(_ v: HealthKitValues) {
        if v.bpHi > 0    { nBpHi_mmHg   = v.bpHi;    bpHiEnabled      = true }
        if v.bpLo > 0    { nBpLo_mmHg   = v.bpLo;    bpLoEnabled      = true }
        if v.pulse > 0   { nPulse_bpm   = v.pulse;   pulseEnabled     = true }
        if v.temp > 0    { nTemp_10c    = v.temp;    tempEnabled      = true }
        if v.weight > 0  { nWeight_10Kg  = v.weight;  weightEnabled    = true }
        if v.steps > 0   { nPedometer   = v.steps;   pedometerEnabled = true }
        if v.bodyFat > 0 { nBodyFat_10p  = v.bodyFat; bodyFatEnabled   = true }
        if v.bpHi > 0 || v.bpLo > 0 || v.pulse > 0 || v.temp > 0
            || v.weight > 0 || v.steps > 0 || v.bodyFat > 0 {
            isModified = true
        }
    }

}
