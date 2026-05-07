// BeginnerHelpBanner.swift
// タイトル直下に表示する初心者向けヒントバナー
// ユーザレベルが「初心者」の時のみ表示。×で手動非表示も可能（AppStorage で記憶）。

import SwiftUI

struct BeginnerHelpBanner: View {
    let messageKey: LocalizedStringKey
    private let storageKey: String

    /// ユーザレベル（@Observable なので body で参照すると自動追跡）
    private var settings: AppSettings { AppSettings.shared }

    @AppStorage private var dismissed: Bool

    init(_ messageKey: LocalizedStringKey, storageKey: String) {
        self.messageKey = messageKey
        self.storageKey = storageKey
        self._dismissed = AppStorage(wrappedValue: false, storageKey)
    }

    var body: some View {
        Group {
            if dismissed {
                // アイコンのみ（初心者・達人 共通）
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            dismissed = false
                        }
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.trailing, 16)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            } else {
                // フルバナー（初心者・達人 共通）
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tint)
                        .padding(.top, 1)
                    Text(messageKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            dismissed = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.tertiary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.background.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: settings.userLevel) { _, newLevel in
            withAnimation(.easeOut(duration: 0.25)) {
                // 初心者に戻す → バナーを再表示
                // 達人に切り替える → アイコンに収納
                dismissed = (newLevel != .beginner)
            }
        }
    }
}
