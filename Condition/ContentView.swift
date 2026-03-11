// ContentView.swift
// ルートタブビュー

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RecordListView()
                .tabItem {
                    Label(
                        String(localized: "Tab_List", defaultValue: "記録"),
                        systemImage: "list.bullet.clipboard"
                    )
                }

            GraphView()
                .tabItem {
                    Label(
                        String(localized: "Tab_Graph", defaultValue: "グラフ"),
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                }

            StatisticsView()
                .tabItem {
                    Label(
                        String(localized: "Tab_Statistics", defaultValue: "統計"),
                        systemImage: "chart.dots.scatter"
                    )
                }

            SettingsView()
                .tabItem {
                    Label(
                        String(localized: "Tab_Settings", defaultValue: "設定"),
                        systemImage: "gear"
                    )
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: BodyRecord.self, inMemory: true)
}
