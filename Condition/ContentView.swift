// ContentView.swift
// ルートタブビュー

import SwiftUI

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        TabView {
            RecordListView()
                .tabItem {
                    Label(
                        "tab.records",
                        systemImage: "list.bullet.clipboard"
                    )
                }

            GraphView()
                .tabItem {
                    Label(
                        "tab.graph",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                }

            StatisticsView()
                .tabItem {
                    Label(
                        "tab.statistics",
                        systemImage: "chart.dots.scatter"
                    )
                }

            SettingsView()
                .tabItem {
                    Label(
                        "tab.settings",
                        systemImage: "gear"
                    )
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, settings.openNewRecordOnForeground else { return }
            // 未保存の変更あり・すでに開いている → 何もしない
            guard !settings.newRecordSheetModified, !settings.showNewRecordSheet else { return }
            // 実機でアプリが完全に復帰してから呈示するため少し待つ
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !settings.showNewRecordSheet else { return }
                settings.showNewRecordSheet = true
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: BodyRecord.self, inMemory: true)
}
