// ConditionApp.swift
// アプリエントリポイント（旧 AppDelegate 相当）

import SwiftUI
import SwiftData

@main
struct ConditionApp: App {

    @State private var migrationService = MigrationService()

    var body: some Scene {
        WindowGroup {
            Group {
                switch migrationService.phase {
                case .idle, .checking:
                    ProgressView(String(localized: "Launch_Checking", defaultValue: "起動中..."))
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
                .font(.system(size: 60))
                .foregroundStyle(Color.azuki)

            Text(String(localized: "Migration_Title", defaultValue: "データを移行中..."))
                .font(.headline)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 240)

            Text(String(format: "%.0f%%", progress * 100))
                .font(.caption)
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
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(String(localized: "Migration_Error", defaultValue: "データ移行に失敗しました"))
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(String(localized: "Migration_Retry", defaultValue: "再試行"), action: onRetry)
                .buttonStyle(.borderedProminent)

            Text(String(localized: "Migration_Note", defaultValue: "元のデータは保護されています"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}
