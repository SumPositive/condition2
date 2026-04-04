// ConditionApp.swift
// アプリエントリポイント（旧 AppDelegate 相当）

import SwiftUI
import SwiftData
@preconcurrency import GoogleMobileAds

@main
struct ConditionApp: App {

    @State private var migrationService = MigrationService()

    init() {
        let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        UITabBarItem.appearance().setTitleTextAttributes(attrs, for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes(attrs, for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch migrationService.phase {
                case .idle, .checking:
                    ProgressView("起動中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .migrating(let progress):
                    MigrationProgressView(progress: progress)

                case .done:
                    ContentView()

                case .failed(let message):
                    MigrationErrorView(message: message) {
                        // 再試行
                        Task {
                            let context = ModelContainer.shared.mainContext
                            await migrationService.migrateIfNeeded(context: context)
                        }
                    }
                }
            }
            .task {
                let context = ModelContainer.shared.mainContext
                await migrationService.migrateIfNeeded(context: context)
            }
            .task {
                await MobileAds.shared.start()
            }
        }
        .modelContainer(ModelContainer.shared)
    }
}

// MARK: - 移行中画面

private struct MigrationProgressView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 68))
                .foregroundStyle(Color.azuki)

            Text("データを移行中...")
                .font(.title3)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 240)

            Text(String(format: "%.0f%%", progress * 100))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

// MARK: - 移行エラー画面

private struct MigrationErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 54))
                .foregroundStyle(.orange)

            Text("データ移行に失敗しました")
                .font(.title3)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("再試行", action: onRetry)
                .buttonStyle(.borderedProminent)

            Text("元のデータは保護されています")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}
