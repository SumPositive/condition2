// ContentView.swift
// ルートタブビュー

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RecordListView()
                .tabItem {
                    Label(
                        "記録",
                        systemImage: "list.bullet.clipboard"
                    )
                }

            GraphView()
                .tabItem {
                    Label(
                        "グラフ",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                }

            StatisticsView()
                .tabItem {
                    Label(
                        "統計",
                        systemImage: "chart.dots.scatter"
                    )
                }

            SettingsView()
                .tabItem {
                    Label(
                        "設定",
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
