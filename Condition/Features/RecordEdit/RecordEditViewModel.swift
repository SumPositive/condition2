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
    // didSet で isModified を管理（loadPreviousValues 中は suppressModified で抑制）
    var dateTime: Date                                              // onDateChanged() で個別管理
    var dateOpt: DateOpt          { didSet { markModified() } }
    var bCaution: Bool            { didSet { markModified() } }
    var sNote1: String            { didSet { markModified() } }
    var sNote2: String            { didSet { markModified() } }
    var sEquipment: String        { didSet { markModified() } }

    var nBpHi_mmHg: Int          { didSet { markModified() } }
    var nBpLo_mmHg: Int          { didSet { markModified() } }
    var nPulse_bpm: Int          { didSet { markModified() } }
    var nTemp_10c: Int           { didSet { markModified() } }
    var nWeight_10Kg: Int        { didSet { markModified() } }
    var nBodyFat_10p: Int        { didSet { markModified() } }
    var nSkMuscle_10p: Int       { didSet { markModified() } }

    // MARK: - 入力有効フラグ
    var bpHiEnabled:    Bool     { didSet { markModified() } }
    var bpLoEnabled:    Bool     { didSet { markModified() } }
    var pulseEnabled:   Bool     { didSet { markModified() } }
    var weightEnabled:  Bool     { didSet { markModified() } }
    var tempEnabled:    Bool     { didSet { markModified() } }
    var bodyFatEnabled: Bool     { didSet { markModified() } }
    var skMuscleEnabled: Bool    { didSet { markModified() } }

    // MARK: - 状態
    var isModified: Bool = false
    /// true の間は didSet による isModified 更新を抑制する（初期ロード用）
    private var suppressModified = false
    var isSaving: Bool = false
    var errorMessage: String?
    var isLoadingFromHK: Bool = false
    var dataSource: RecordDataSource = .appInput
    /// ヘルスケア由来の記録は、日時と値を固定する。
    var isHealthRecord: Bool {
        dataSource == .hkImport || dataSource == .hkModified
    }
    var valuesLocked: Bool { isHealthRecord }

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
            nBodyFat_10p  = MeasureRange.bodyFat.initVal
            nSkMuscle_10p = MeasureRange.skMuscle.initVal
            bpHiEnabled      = true
            bpLoEnabled      = true
            pulseEnabled     = false
            weightEnabled    = false
            tempEnabled      = false
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
            nBodyFat_10p  = record.nBodyFat_10p  > 0 ? record.nBodyFat_10p  : MeasureRange.bodyFat.initVal
            nSkMuscle_10p = record.nSkMuscle_10p > 0 ? record.nSkMuscle_10p : MeasureRange.skMuscle.initVal
            bpHiEnabled      = record.nBpHi_mmHg   > 0
            bpLoEnabled      = record.nBpLo_mmHg   > 0
            pulseEnabled     = record.nPulse_bpm    > 0
            weightEnabled    = record.nWeight_10Kg  > 0
            tempEnabled      = record.nTemp_10c     > 0
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
            nBodyFat_10p  = settings.goalBodyFat
            nSkMuscle_10p = settings.goalSkMuscle
            bpHiEnabled      = true
            bpLoEnabled      = true
            pulseEnabled     = true
            weightEnabled    = true
            tempEnabled      = true
            bodyFatEnabled   = true
            skMuscleEnabled  = true
        }
    }

    // MARK: - isModified ヘルパー

    private func markModified() {
        if !suppressModified { isModified = true }
    }

    // MARK: - 前回値ロード（旧 setE2recordPrev 相当）

    func loadPreviousValues(context: ModelContext) {
        guard case .addNew = mode else { return }
        suppressModified = true
        defer { suppressModified = false }

        let now = dateTime

        // 各フィールドを前回値で初期化（0=未入力の場合のみ）
        let descriptor = FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.dateTime < now && $0.dateTime < bodyRecordGoalDate },
            sortBy: [SortDescriptor(\BodyRecord.dateTime, order: .reverse)]
        )

        guard let allPrev = try? context.fetch(descriptor) else { return }

        // 値は区分に関係なく、各項目ごとの直近の有効値を引き継ぐ。
        if nBpHi_mmHg == MeasureRange.bpHi.initVal {
            nBpHi_mmHg = allPrev
                .first { 0 < $0.nBpHi_mmHg }
                .map(\.nBpHi_mmHg) ?? MeasureRange.bpHi.initVal
        }
        if nBpLo_mmHg == MeasureRange.bpLo.initVal {
            nBpLo_mmHg = allPrev
                .first { 0 < $0.nBpLo_mmHg }
                .map(\.nBpLo_mmHg) ?? MeasureRange.bpLo.initVal
        }
        if nPulse_bpm == MeasureRange.pulse.initVal {
            nPulse_bpm = allPrev
                .first { 0 < $0.nPulse_bpm }
                .map(\.nPulse_bpm) ?? MeasureRange.pulse.initVal
        }

        // 体重・体温・体脂肪・骨格筋も日時順のみ
        if nWeight_10Kg == MeasureRange.weight.initVal {
            nWeight_10Kg = allPrev.first { $0.nWeight_10Kg > 0 }.map { $0.nWeight_10Kg } ?? MeasureRange.weight.initVal
        }
        if nTemp_10c == MeasureRange.temp.initVal {
            nTemp_10c = allPrev.first { $0.nTemp_10c > 0 }.map { $0.nTemp_10c } ?? MeasureRange.temp.initVal
        }
        if nBodyFat_10p == MeasureRange.bodyFat.initVal {
            nBodyFat_10p = allPrev.first { $0.nBodyFat_10p > 0 }.map { $0.nBodyFat_10p } ?? MeasureRange.bodyFat.initVal
        }
        if nSkMuscle_10p == MeasureRange.skMuscle.initVal {
            nSkMuscle_10p = allPrev.first { $0.nSkMuscle_10p > 0 }.map { $0.nSkMuscle_10p } ?? MeasureRange.skMuscle.initVal
        }

        // 表示スイッチだけは、値の参照元とは分けて直前1件の表示状態を引き継ぐ。
        if let p = allPrev.first {
            bpHiEnabled      = 0 < p.nBpHi_mmHg
            bpLoEnabled      = 0 < p.nBpLo_mmHg
            pulseEnabled     = 0 < p.nPulse_bpm
            weightEnabled    = 0 < p.nWeight_10Kg
            tempEnabled      = 0 < p.nTemp_10c
            bodyFatEnabled   = 0 < p.nBodyFat_10p
            skMuscleEnabled  = 0 < p.nSkMuscle_10p
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
            if isHealthRecord {
                // ヘルスケア由来は日時と値を固定し、区分・メモなどだけ保存する。
                record.dateTime = originalRecord?.dateTime ?? record.dateTime
            } else {
                record.dateTime = dateTime
            }
            record.dateOpt  = dateOpt
            applyFields(to: record)
            restoreHealthValues(to: record)
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
            s.goalBodyFat   = nBodyFat_10p
            s.goalSkMuscle  = nSkMuscle_10p
        }

        try context.save()
        writeToHealthKitIfAutomatic()
        isModified = false
    }

    private func writeToHealthKitIfAutomatic() {
        if case .goalEdit = mode { return }
        // hkImport / hkModified レコードはヘルスケアへ書き戻さない
        if case .edit(let record) = mode,
           record.dataSource == .hkImport || record.dataSource == .hkModified { return }
        let s = AppSettings.shared
        guard s.hkEnabled,
              HKSyncDirection(rawValue: s.hkDirection)?.canWrite == true else { return }
        Task { await HealthKitService.shared.write(currentHealthKitValues()) }
    }

    // MARK: - 直近10分以内の衝突検出と解決

    /// 衝突判定の時間しきい値（10分）
    private static let conflictThreshold: TimeInterval = 10 * 60

    /// 新規追加モードのとき、直前10分以内の記録との衝突情報を返す。
    /// 重なる項目（両方に値あり）が一つもなければ nil。
    func findRecentConflict(context: ModelContext) -> RecentConflict? {
        guard case .addNew = mode else { return nil }
        let now = dateTime
        let descriptor = FetchDescriptor<BodyRecord>(
            predicate: #Predicate { $0.dateTime < now && $0.dateTime < bodyRecordGoalDate },
            sortBy: [SortDescriptor(\BodyRecord.dateTime, order: .reverse)]
        )
        guard let prev = (try? context.fetch(descriptor))?.first else { return nil }
        let diff = now.timeIntervalSince(prev.dateTime)
        guard diff >= 0, diff <= Self.conflictThreshold else { return nil }

        let hidden = Set(AppSettings.shared.hiddenFields)
        let newBpHi   = bpHiEnabled      ? nBpHi_mmHg    : 0
        let newBpLo   = bpLoEnabled      ? nBpLo_mmHg    : 0
        let newPulse  = pulseEnabled     ? nPulse_bpm    : 0
        let newTemp   = tempEnabled      ? nTemp_10c     : 0
        let newWeight = weightEnabled    ? nWeight_10Kg  : 0
        let newBF     = bodyFatEnabled   ? nBodyFat_10p  : 0
        let newSK     = skMuscleEnabled  ? nSkMuscle_10p : 0

        var items: [ConflictItem] = []
        func push(_ f: ConflictField, p: Int, n: Int) {
            // 非表示項目は除外
            guard !hidden.contains(f.graphKind.rawValue) else { return }
            guard p > 0, n > 0 else { return }
            items.append(ConflictItem(field: f, prevValue: p, newValue: n))
        }
        push(.bpHi,     p: prev.nBpHi_mmHg,    n: newBpHi)
        push(.bpLo,     p: prev.nBpLo_mmHg,    n: newBpLo)
        push(.pulse,    p: prev.nPulse_bpm,    n: newPulse)
        push(.temp,     p: prev.nTemp_10c,     n: newTemp)
        push(.weight,   p: prev.nWeight_10Kg,  n: newWeight)
        push(.bodyFat,  p: prev.nBodyFat_10p,  n: newBF)
        push(.skMuscle, p: prev.nSkMuscle_10p, n: newSK)

        guard !items.isEmpty else { return nil }
        return RecentConflict(previous: prev, items: items)
    }

    /// 衝突の解決を適用する。
    func resolveConflict(_ action: ConflictAction, previous: BodyRecord, context: ModelContext) throws {
        switch action {
        case .keepPrevious:
            // 何もしない（新しい記録は保存しない）
            isModified = false
        case .keepBoth:
            try save(context: context)
        case .useNew:
            try overwritePrevious(previous, useAverage: false, context: context)
        case .useAverage:
            try overwritePrevious(previous, useAverage: true, context: context)
        }
    }

    /// 直前レコードを上書きする（useAverage=true なら平均値、false なら新しい値）。
    /// 両方に値がない場合は値のあるほうを残す。
    private func overwritePrevious(_ prev: BodyRecord, useAverage: Bool, context: ModelContext) throws {
        isSaving = true
        defer { isSaving = false }

        let hidden = Set(AppSettings.shared.hiddenFields)
        let newBpHi   = bpHiEnabled      ? nBpHi_mmHg    : 0
        let newBpLo   = bpLoEnabled      ? nBpLo_mmHg    : 0
        let newPulse  = pulseEnabled     ? nPulse_bpm    : 0
        let newTemp   = tempEnabled      ? nTemp_10c     : 0
        let newWeight = weightEnabled    ? nWeight_10Kg  : 0
        let newBF     = bodyFatEnabled   ? nBodyFat_10p  : 0
        let newSK     = skMuscleEnabled  ? nSkMuscle_10p : 0

        func merge(_ p: Int, _ n: Int) -> Int {
            if p > 0, n > 0 { return useAverage ? (p + n) / 2 : n }
            return n > 0 ? n : p
        }
        func apply(_ f: ConflictField, prev p: Int, new n: Int) -> Int {
            // 非表示項目は直前値をそのまま維持
            if hidden.contains(f.graphKind.rawValue) { return p }
            return merge(p, n)
        }

        prev.nBpHi_mmHg    = apply(.bpHi,     prev: prev.nBpHi_mmHg,    new: newBpHi)
        prev.nBpLo_mmHg    = apply(.bpLo,     prev: prev.nBpLo_mmHg,    new: newBpLo)
        prev.nPulse_bpm    = apply(.pulse,    prev: prev.nPulse_bpm,    new: newPulse)
        prev.nTemp_10c     = apply(.temp,     prev: prev.nTemp_10c,     new: newTemp)
        prev.nWeight_10Kg  = apply(.weight,   prev: prev.nWeight_10Kg,  new: newWeight)
        prev.nBodyFat_10p  = apply(.bodyFat,  prev: prev.nBodyFat_10p,  new: newBF)
        prev.nSkMuscle_10p = apply(.skMuscle, prev: prev.nSkMuscle_10p, new: newSK)

        // メモ・装備：新しい記録が入力済みなら上書き、空なら直前を残す
        let n1 = sNote1.trimmingCharacters(in: .newlines)
        let n2 = sNote2.trimmingCharacters(in: .newlines)
        let eq = sEquipment.trimmingCharacters(in: .newlines)
        if !n1.isEmpty { prev.sNote1     = n1 }
        if !n2.isEmpty { prev.sNote2     = n2 }
        if !eq.isEmpty { prev.sEquipment = eq }
        // 注意フラグ・区分：新しい値で上書き
        prev.bCaution = bCaution
        prev.dateOpt  = dateOpt

        // dataSource を「修正済み」へ
        switch prev.dataSource {
        case .appInput: prev.dataSource = .appModified
        case .hkImport: prev.dataSource = .hkModified
        default: break
        }

        try context.save()
        isModified = false
        // 平均値は実測値ではないため HealthKit へは書き戻さない
        if !useAverage {
            writeToHealthKitIfAutomatic()
        }
    }

    // MARK: - 削除

    func delete(record: BodyRecord, context: ModelContext) throws {
        context.delete(record)
        try context.save()
    }

    // MARK: - フィールド適用

    private func applyFields(to record: BodyRecord) {
        record.bCaution      = bCaution
        record.sNote1        = sNote1.trimmingCharacters(in: .newlines)
        record.sNote2        = sNote2.trimmingCharacters(in: .newlines)
        record.sEquipment    = sEquipment.trimmingCharacters(in: .newlines)
        record.nBpHi_mmHg    = bpHiEnabled      ? nBpHi_mmHg   : 0
        record.nBpLo_mmHg    = bpLoEnabled      ? nBpLo_mmHg   : 0
        record.nPulse_bpm    = pulseEnabled     ? nPulse_bpm   : 0
        record.nTemp_10c     = tempEnabled      ? nTemp_10c    : 0
        record.nWeight_10Kg  = weightEnabled    ? nWeight_10Kg  : 0
        record.nBodyFat_10p  = bodyFatEnabled   ? nBodyFat_10p  : 0
        record.nSkMuscle_10p = skMuscleEnabled  ? nSkMuscle_10p : 0
    }

    private func restoreHealthValues(to record: BodyRecord) {
        guard isHealthRecord, let originalRecord else { return }
        // 項目単位の取得元は保持していないため、ヘルスケア由来の値は全て元値へ戻す。
        record.nBpHi_mmHg = originalRecord.nBpHi_mmHg
        record.nBpLo_mmHg = originalRecord.nBpLo_mmHg
        record.nPulse_bpm = originalRecord.nPulse_bpm
        record.nTemp_10c = originalRecord.nTemp_10c
        record.nWeight_10Kg = originalRecord.nWeight_10Kg
        record.nBodyFat_10p = originalRecord.nBodyFat_10p
        record.nSkMuscle_10p = originalRecord.nSkMuscle_10p
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
        // hkImport / hkModified レコードはヘルスケアへ書き戻さない
        if case .edit(let record) = mode,
           record.dataSource == .hkImport || record.dataSource == .hkModified { return }
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
            bodyFat: active(.bodyFat, bodyFatEnabled)   ? nBodyFat_10p  : 0
        )
    }

    private func applyHealthKitValues(_ v: HealthKitValues) {
        if v.bpHi > 0    { nBpHi_mmHg   = v.bpHi;    bpHiEnabled      = true }
        if v.bpLo > 0    { nBpLo_mmHg   = v.bpLo;    bpLoEnabled      = true }
        if v.pulse > 0   { nPulse_bpm   = v.pulse;   pulseEnabled     = true }
        if v.temp > 0    { nTemp_10c    = v.temp;    tempEnabled      = true }
        if v.weight > 0  { nWeight_10Kg  = v.weight;  weightEnabled    = true }
        if v.bodyFat > 0 { nBodyFat_10p  = v.bodyFat; bodyFatEnabled   = true }
        if v.bpHi > 0 || v.bpLo > 0 || v.pulse > 0 || v.temp > 0
            || v.weight > 0 || v.bodyFat > 0 {
            isModified = true
        }
    }

}
