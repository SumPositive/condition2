// MigrationService.swift
// Core Data（旧 AzBodyNote）→ SwiftData（新 Condition）への移行処理
// 初回起動時のみ1度だけ実行する。失敗しても旧データは保全する。

import Foundation
import CoreData
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.azukid.AzBodyNote", category: "Migration")

@Observable
@MainActor
final class MigrationService {

    // MARK: - 状態
    enum Phase: Equatable {
        case idle
        case checking
        case migrating(progress: Double)
        case done
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.checking, .checking), (.done, .done): return true
            case (.migrating(let a), .migrating(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var phase: Phase = .idle

    // MARK: - エントリポイント

    func migrateIfNeeded(context: ModelContext) async {
        phase = .checking

        // 移行済みフラグ確認
        if UserDefaults.standard.bool(forKey: UDefKeys.migrationDone) {
            phase = .done
            return
        }

        // 旧 SQLite ファイル検索
        guard let oldStoreURL = findOldStoreURL() else {
            logger.info("旧データなし → 新規インストール")
            UserDefaults.standard.set(true, forKey: UDefKeys.migrationDone)
            phase = .done
            return
        }

        logger.info("旧データ発見: \(oldStoreURL.path)")
        await performMigration(from: oldStoreURL, context: context)
    }

    // MARK: - 旧ファイル検索

    private func findOldStoreURL() -> URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let candidates = [
            appSupport.appendingPathComponent("AzBodyNote.sqlite"),
            appSupport.appendingPathComponent("AzBodyNote/AzBodyNote.sqlite"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - 移行実行

    private func performMigration(from oldStoreURL: URL, context: ModelContext) async {
        do {
            // 旧 Core Data コンテナ初期化
            let oldContainer = try makeOldContainer(storeURL: oldStoreURL)
            let oldContext = oldContainer.viewContext

            // 全件取得
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "E2record")
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "dateTime", ascending: true)]
            let allRecords = try oldContext.fetch(fetchRequest)

            logger.info("旧レコード数: \(allRecords.count)")

            let batchSize = 100
            var processed = 0

            for record in allRecords {
                guard let dateTime = record.value(forKey: "dateTime") as? Date else { continue }

                // 目標値レコードを検出し AppSettings へ書き出す
                if dateTime >= BodyRecord.goalDate {
                    migrateGoalRecord(record)
                    processed += 1
                    continue
                }

                // 通常レコードを変換
                let body = convertToBodyRecord(record, dateTime: dateTime)
                context.insert(body)
                processed += 1

                // バッチ保存
                if processed % batchSize == 0 {
                    try context.save()
                    let progress = Double(processed) / Double(allRecords.count)
                    phase = .migrating(progress: progress)
                    logger.info("移行中: \(processed)/\(allRecords.count)")
                }
            }

            // 最終保存
            try context.save()
            logger.info("移行完了: \(processed) 件")

            // 旧ファイルを .bak にリネーム（削除しない）
            archiveOldStore(at: oldStoreURL)

            // 完了フラグ
            UserDefaults.standard.set(true, forKey: UDefKeys.migrationDone)
            phase = .done

        } catch {
            logger.error("移行失敗: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - 旧 Core Data コンテナ生成

    private func makeOldContainer(storeURL: URL) throws -> NSPersistentContainer {
        // 旧モデルを動的に生成
        let entity = NSEntityDescription()
        entity.name = "E2record"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let attrs: [(String, NSAttributeType)] = [
            ("bCaution",       .stringAttributeType),
            ("dateTime",       .dateAttributeType),
            ("nDateOpt",       .integer32AttributeType),
            ("nYearMM",        .integer32AttributeType),
            ("sEventID",       .stringAttributeType),
            ("sGSpreadID",     .stringAttributeType),
            ("sNote1",         .stringAttributeType),
            ("sNote2",         .stringAttributeType),
            ("sEquipment",     .stringAttributeType),
            ("nBpHi_mmHg",     .integer16AttributeType),
            ("nBpLo_mmHg",     .integer16AttributeType),
            ("nPulse_bpm",     .integer16AttributeType),
            ("nTemp_10c",      .integer16AttributeType),
            ("nWeight_10Kg",   .integer32AttributeType),
            ("nBodyFat_10p",   .integer32AttributeType),
            ("nSkMuscle_10p",  .integer32AttributeType),
        ]

        for (name, type) in attrs {
            let attr = NSAttributeDescription()
            attr.name = name
            attr.attributeType = type
            attr.isOptional = true
            entity.properties.append(attr)
        }

        let model = NSManagedObjectModel()
        model.entities = [entity]

        let container = NSPersistentContainer(name: "AzBodyNote", managedObjectModel: model)
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.isReadOnly = true
        container.persistentStoreDescriptions = [desc]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError { throw error }

        return container
    }

    // MARK: - レコード変換

    private func convertToBodyRecord(_ obj: NSManagedObject, dateTime: Date) -> BodyRecord {
        let record = BodyRecord(dateTime: dateTime)

        // DateOpt
        if let v = obj.value(forKey: "nDateOpt") as? Int {
            record.nDateOpt = v
        }

        // bCaution（旧: NSString "YES"/"NO"）
        if let v = obj.value(forKey: "bCaution") as? String {
            record.bCaution = (v == "YES")
        }

        record.sNote1     = (obj.value(forKey: "sNote1")     as? String) ?? ""
        record.sNote2     = (obj.value(forKey: "sNote2")     as? String) ?? ""
        record.sEquipment = (obj.value(forKey: "sEquipment") as? String) ?? ""

        record.nBpHi_mmHg   = (obj.value(forKey: "nBpHi_mmHg")   as? Int) ?? 0
        record.nBpLo_mmHg   = (obj.value(forKey: "nBpLo_mmHg")   as? Int) ?? 0
        record.nPulse_bpm   = (obj.value(forKey: "nPulse_bpm")   as? Int) ?? 0
        record.nTemp_10c    = (obj.value(forKey: "nTemp_10c")    as? Int) ?? 0
        record.nWeight_10Kg = (obj.value(forKey: "nWeight_10Kg") as? Int) ?? 0
        record.nBodyFat_10p  = (obj.value(forKey: "nBodyFat_10p")  as? Int) ?? 0
        record.nSkMuscle_10p = (obj.value(forKey: "nSkMuscle_10p") as? Int) ?? 0

        return record
    }

    // MARK: - 目標値レコード → AppSettings へ書き出し

    private func migrateGoalRecord(_ obj: NSManagedObject) {
        let settings = AppSettings.shared
        if let v = obj.value(forKey: "nBpHi_mmHg") as? Int,   v > 0 { settings.goalBpHi      = v }
        if let v = obj.value(forKey: "nBpLo_mmHg") as? Int,   v > 0 { settings.goalBpLo      = v }
        if let v = obj.value(forKey: "nPulse_bpm") as? Int,   v > 0 { settings.goalPulse     = v }
        if let v = obj.value(forKey: "nWeight_10Kg") as? Int, v > 0 { settings.goalWeight    = v }
        if let v = obj.value(forKey: "nTemp_10c") as? Int,    v > 0 { settings.goalTemp      = v }
        if let v = obj.value(forKey: "nBodyFat_10p") as? Int, v > 0 { settings.goalBodyFat   = v }
        if let v = obj.value(forKey: "nSkMuscle_10p") as? Int, v > 0 { settings.goalSkMuscle = v }
        logger.info("目標値レコードを AppSettings へ書き出し完了")
    }

    // MARK: - 旧ファイルアーカイブ

    private func archiveOldStore(at url: URL) {
        let fm = FileManager.default
        let extensions = ["", "-shm", "-wal"]
        for ext in extensions {
            let src = URL(fileURLWithPath: url.path + ext)
            let dst = URL(fileURLWithPath: url.path + ext + ".bak")
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dst)
            }
        }
        logger.info("旧ファイルを .bak にリネーム完了")
    }
}
