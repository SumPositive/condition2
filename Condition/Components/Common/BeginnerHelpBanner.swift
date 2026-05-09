// BeginnerHelpBanner.swift
// タイトル直下に表示する初心者向けヒントバナー
// ユーザレベルが「初心者」の時のみ表示。

import SwiftUI

struct BeginnerHelpBanner: View {
    let messageKey: LocalizedStringKey

    /// ユーザレベル（@Observable なので body で参照すると自動追跡）
    private var settings: AppSettings { AppSettings.shared }

    init(_ messageKey: LocalizedStringKey, storageKey: String) {
        self.messageKey = messageKey
    }

    var body: some View {
        if settings.userLevel == .beginner {
            Text(messageKey)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(.background.secondary)
        }
    }
}
