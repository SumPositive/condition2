// ModelContainer+Setup.swift
// SwiftData ModelContainer の設定

import SwiftData
import Foundation
import SQLite3
import OSLog

private let logger = Logger(subsystem: "com.azukid.AzBodyNote", category: "ModelContainer")

extension ModelContainer {

    @MainActor
    static var shared: ModelContainer = {
        let schema = Schema([BodyRecord.self])
        let storeName = resolveStoreName()
        logger.info("使用ストア: \(storeName).sqlite")

        let config = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: BodyRecord.self, configurations: config)
        } catch {
            fatalError("ModelContainer の作成に失敗しました: \(error)")
        }
    }()

    // MARK: - ストア名決定

    /// 4ケースを網羅してストア名を返す
    private static func resolveStoreName() -> String {
        let fm           = FileManager.default
        let appSupport   = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let conditionURL  = appSupport.appendingPathComponent("Condition.sqlite")
        let azBodyNoteURL = appSupport.appendingPathComponent("AzBodyNote.sqlite")

        let conditionExists  = fm.fileExists(atPath: conditionURL.path)
        let azBodyNoteExists = fm.fileExists(atPath: azBodyNoteURL.path)
        let migrationDone    = UserDefaults.standard.bool(forKey: UDefKeys.migrationDone)

        switch (conditionExists, azBodyNoteExists, migrationDone) {

        // ケース1: Condition のみ存在 → 通常ケース
        case (true, false, _):
            return "Condition"

        // ケース2: どちらも存在しない → 新規インストール
        case (false, false, _):
            return "Condition"

        // ケース3: AzBodyNote のみ存在 かつ migrationDone=true
        //   → renameSwiftDataStoreIfNeeded が未実行 or 失敗
        case (false, true, true):
            logger.warning("ケース3: Condition なし・AzBodyNote あり → リネーム再試行")
            let renamed = attemptRename(from: azBodyNoteURL, to: conditionURL, fm: fm)
            return renamed ? "Condition" : "AzBodyNote"

        // ケース4: 両方存在 かつ migrationDone=true
        //   → リネーム失敗後に空の Condition が作られた可能性大
        case (true, true, true):
            logger.warning("ケース4: 両方存在 → レコード有無を確認して判定")
            return resolveConflict(
                conditionURL: conditionURL,
                azBodyNoteURL: azBodyNoteURL,
                fm: fm
            )

        // ケース3/4 で migrationDone=false → CoreData 移行前ユーザー
        // AzBodyNote.sqlite は CoreData ファイルなので触らない
        default:
            return "Condition"
        }
    }

    /// ケース4: 両方存在する場合に正しいストアを特定して返す
    private static func resolveConflict(
        conditionURL: URL,
        azBodyNoteURL: URL,
        fm: FileManager
    ) -> String {
        let conditionHasData  = sqliteHasRecords(at: conditionURL)
        let azBodyNoteHasData = sqliteHasRecords(at: azBodyNoteURL)

        switch (conditionHasData, azBodyNoteHasData) {

        case (true, _):
            // Condition にデータあり → 正常
            logger.info("ケース4: Condition にデータあり → Condition を使用")
            return "Condition"

        case (false, true):
            // Condition は空、AzBodyNote にデータあり
            // → 空の Condition を退避して AzBodyNote をリネーム
            logger.warning("ケース4: Condition が空・AzBodyNote にデータあり → 復元")
            archiveEmpty(conditionURL, fm: fm)
            let renamed = attemptRename(from: azBodyNoteURL, to: conditionURL, fm: fm)
            return renamed ? "Condition" : "AzBodyNote"

        case (false, false):
            // どちらも空 → Condition を使用（新しい方を優先）
            logger.info("ケース4: 両方空 → Condition を使用")
            return "Condition"
        }
    }

    // MARK: - SQLite レコード有無チェック

    /// SwiftData の BodyRecord テーブル（= ZBODYRECORD）に1件以上レコードがあるか確認
    private static func sqliteHasRecords(at url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return false }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        // SwiftData は CoreData と同様に Z + 大文字クラス名をテーブル名に使用
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM ZBODYRECORD LIMIT 1", -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return false }
        defer { sqlite3_finalize(stmt) }

        return sqlite3_step(stmt) == SQLITE_ROW
    }

    // MARK: - ユーティリティ

    /// 空になった Condition.sqlite を .empty にリネーム（デバッグ用に保持）
    private static func archiveEmpty(_ url: URL, fm: FileManager) {
        for ext in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: url.path + ext)
            let dst = URL(fileURLWithPath: url.path + ext + ".empty")
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dst)
            }
        }
        logger.info("空の Condition.sqlite を .empty にリネーム")
    }

    /// リネーム実行（ログ付き）。主ファイルのリネーム成否を返す
    @discardableResult
    private static func attemptRename(from srcBase: URL, to dstBase: URL, fm: FileManager) -> Bool {
        var mainSucceeded = false
        for ext in ["", "-shm", "-wal"] {
            let src = URL(fileURLWithPath: srcBase.path + ext)
            let dst = URL(fileURLWithPath: dstBase.path + ext)
            guard fm.fileExists(atPath: src.path) else { continue }
            do {
                try fm.moveItem(at: src, to: dst)
                if ext == "" { mainSucceeded = true }
                logger.info("リネーム成功: \(src.lastPathComponent) → \(dst.lastPathComponent)")
            } catch {
                logger.error("リネーム失敗: \(src.lastPathComponent) - \(error)")
            }
        }
        return mainSucceeded
    }

    // MARK: - 事前リネーム（ConditionApp.init から呼ぶ）

    /// SwiftData ストアを "AzBodyNote" → "Condition" へ事前リネーム。
    /// 失敗しても resolveStoreName() がフォールバックするので致命的にならない。
    static func renameSwiftDataStoreIfNeeded() {
        guard UserDefaults.standard.bool(forKey: UDefKeys.migrationDone) else { return }

        let fm = FileManager.default
        let appSupport    = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let srcBase       = appSupport.appendingPathComponent("AzBodyNote.sqlite")
        let dstBase       = appSupport.appendingPathComponent("Condition.sqlite")

        guard fm.fileExists(atPath: srcBase.path)  else { return }
        guard !fm.fileExists(atPath: dstBase.path) else { return }

        attemptRename(from: srcBase, to: dstBase, fm: fm)
    }
}
