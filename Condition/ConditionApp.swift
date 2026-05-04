// ConditionApp.swift
// アプリエントリポイント（旧 AppDelegate 相当）

import SwiftUI
import SwiftData
@preconcurrency import GoogleMobileAds

@main
struct ConditionApp: App {

    @State private var migrationService = MigrationService()
    @State private var settings = AppSettings.shared

    init() {
        // 改善案2: ModelContainer.shared を初期化する前に
        // SwiftData ストアファイルを "AzBodyNote" → "Condition" へリネーム
        // （CoreData 移行完了済みユーザーのみ対象。未移行ユーザーの旧ファイルは触らない）
        ModelContainer.renameSwiftDataStoreIfNeeded()

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
                    ProgressView("app.loading")
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
                    } onSkip: {
                        // スキップして続行
                        // migrationDone フラグは立てない → 次回アップデートで自動再試行
                        migrationService.skipMigration()
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
            .preferredColorScheme(settings.appearanceMode.colorScheme)
        }
        .modelContainer(ModelContainer.shared)
    }
}

private extension AppAppearanceMode {
    var colorScheme: ColorScheme? {
        // 自動はシステム設定へ任せる
        switch self {
        case .automatic: return nil
        case .light:     return .light
        case .dark:      return .dark
        }
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

            Text("migration.inProgress")
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
    let onSkip: () -> Void

    @State private var showDetail = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 54))
                    .foregroundStyle(.orange)

                Text("migration.failed")
                    .font(.title3.weight(.semibold))

                Text("migration.failedDescription")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    Button("action.retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    Button("migration.skipAndContinue", role: .destructive, action: onSkip)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }

                VStack(spacing: 6) {
                    Text("migration.skipNote")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    Text("migration.originalProtected")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                // 技術的な詳細は折りたたみで表示
                DisclosureGroup(isExpanded: $showDetail) {
                    Text(message)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Text("migration.errorDetail")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
            }
            .padding(40)
        }
    }
}
