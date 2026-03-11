// ModelContainer+Setup.swift
// SwiftData ModelContainer の設定

import SwiftData
import Foundation

extension ModelContainer {
    @MainActor
    static var shared: ModelContainer = {
        let schema = Schema([BodyRecord.self])
        let config = ModelConfiguration(
            "AzBodyNote",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: BodyRecord.self, configurations: config)
        } catch {
            fatalError("ModelContainer の作成に失敗しました: \(error)")
        }
    }()
}
