// ContentView.swift
// ルートタブビュー

import SwiftUI

struct ContentView: View {
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: BodyRecord.self, inMemory: true)
}
