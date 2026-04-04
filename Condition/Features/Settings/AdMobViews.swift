// AdMobViews.swift
// AdMob広告（開発者応援）

import SwiftUI
import UIKit

@preconcurrency import GoogleMobileAds

// アプリID は Info.plist の GADApplicationIdentifier にセット済み

private let adUnavailableMessage = "現在、特典付きの広告がありません。後ほどお試しください"

// 広告ユニットID
// AdMob コンソールで体調メモ用の広告ユニットを作成後、リリース用 ID に置き換えてください
#if DEBUG
let ADMOB_REWARD_UnitID = "ca-app-pub-3940256099942544/1712485313"  // テスト用リワード
let ADMOB_BANNER_UnitID = "ca-app-pub-3940256099942544/2435281174"  // テスト用バナー
#else
let ADMOB_REWARD_UnitID = "ca-app-pub-7576639777972199/4693657810"  // 本番用リワード ID を設定
let ADMOB_BANNER_UnitID = "ca-app-pub-7576639777972199/9141270336"  // 本番用バナー ID を設定
#endif

// MARK: - AdMobAdSheetView

/// バナー広告と動画広告をまとめて確認できるシートビュー
struct AdMobAdSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let onRewardEarned: () -> Void

    private let bannerConfigs = [
        AdMobBannerConfiguration(
            adUnitID: ADMOB_BANNER_UnitID,
            size: CGSize(width: 300, height: 250)
        )
    ]

    @StateObject private var loader = RewardedAdLoader(adUnitID: ADMOB_REWARD_UnitID)
    @State private var rewardDescription: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(bannerConfigs) { config in
                            AdMobBannerView(adUnitID: config.adUnitID, size: config.size)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(uiColor: .tertiarySystemBackground))
                                )
                        }

                        AdMobRewardedContentView(
                            loader: loader,
                            rewardDescription: $rewardDescription,
                            presentAction: presentAd
                        )
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(uiColor: .tertiarySystemBackground))
                        )
                    }
                    .padding()
                }
                .padding(.vertical, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .onAppear {
            loader.onAdDismissed = {
                loader.loadAd()
            }
            loader.onRewardEarned = { _ in
                rewardDescription = "広告視聴ありがとうございます！"
                onRewardEarned()
            }
            loader.onAdLoaded = {
                rewardDescription = nil
            }
            loader.onAdFailedToLoad = { _ in
                rewardDescription = adUnavailableMessage
            }
            loader.onAdPresented = {
                rewardDescription = nil
            }
            loader.onAdFailedToPresent = { _ in
                rewardDescription = adUnavailableMessage
            }
        }
    }

    private func presentAd() {
        guard let topController = UIApplication.topMostViewController() else { return }
        loader.present(from: topController)
    }
}

// MARK: - AdMobBannerConfiguration

struct AdMobBannerConfiguration: Identifiable {
    let id = UUID()
    let adUnitID: String
    let size: CGSize
}

// MARK: - AdMobRewardedContentView

struct AdMobRewardedContentView: View {
    @ObservedObject var loader: RewardedAdLoader
    @Binding var rewardDescription: String?
    let presentAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 66) {
                Label {
                    Text("動画広告")
                        .font(.headline)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "movieclapper")
                        .symbolRenderingMode(.hierarchical)
                        .colorMultiply(.primary)
                }

                Label {
                    Text("音が出ます")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                }
            }

            Text("最後まで視聴すると閉じる【×】ボタンが現れます")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal)

            HStack {
                Spacer()
                if loader.isLoading {
                    ProgressView("広告を読み込み中...")
                        .padding()
                } else {
                    Button {
                        presentAction()
                    } label: {
                        Label {
                            Text("広告を再生する")
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, 8)
                        } icon: {
                            Image(systemName: loader.isReady ? "play.rectangle" : "pause.rectangle")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!loader.isReady)
                }
                Spacer()
            }

            if loader.errorMessage != nil {
                Button("再読み込み") {
                    loader.loadAd()
                }
                .buttonStyle(.borderedProminent)
            }

            if let rewardDescription {
                Text(rewardDescription)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
}

// MARK: - RewardedAdLoader

@MainActor
final class RewardedAdLoader: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var isLoading = false
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?

    var onAdLoaded: (() -> Void)?
    var onAdFailedToLoad: ((Error) -> Void)?
    var onAdPresented: (() -> Void)?
    var onAdFailedToPresent: ((Error) -> Void)?
    var onAdDismissed: (() -> Void)?
    var onRewardEarned: ((AdReward) -> Void)?

    private let adUnitID: String
    // nonisolated(unsafe): completion handler から isolation を越えずに代入するため
    nonisolated(unsafe) private var rewardedAd: RewardedAd?

    init(adUnitID: String) {
        self.adUnitID = adUnitID
        super.init()
        loadAd()
    }

    func loadAd() {
        isLoading = true
        isReady = false
        errorMessage = nil

        let request = Request()
        RewardedAd.load(with: adUnitID, request: request) { [weak self] ad, error in
            guard let self else { return }
            // ad を assumeIsolated の外で代入し、isolation 境界を越える Sending を回避
            self.rewardedAd = ad
            if let ad { ad.fullScreenContentDelegate = self }
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = adUnavailableMessage
                    self.onAdFailedToLoad?(error)
                    self.rewardedAd = nil
                } else if self.rewardedAd != nil {
                    self.isReady = true
                    self.onAdLoaded?()
                }
            }
        }
    }

    func present(from root: UIViewController) {
        guard let rewardedAd else { return }
        let ad = rewardedAd
        isReady = false
        errorMessage = nil
        ad.present(from: root) { [weak self] in
            guard let self else { return }
            self.onRewardEarned?(ad.adReward)
        }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        MainActor.assumeIsolated { [weak self] in
            guard let self else { return }
            self.isReady = false
            self.rewardedAd = nil
            self.onAdDismissed?()
            self.loadAd()
        }
    }

    nonisolated func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        MainActor.assumeIsolated { [weak self] in
            guard let self else { return }
            self.onAdPresented?()
        }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        MainActor.assumeIsolated { [weak self] in
            guard let self else { return }
            self.errorMessage = adUnavailableMessage
            self.isReady = false
            self.rewardedAd = nil
            self.onAdFailedToPresent?(error)
            self.loadAd()
        }
    }
}

// MARK: - AdMobBannerView

struct AdMobBannerView: View {
    let adUnitID: String
    let size: CGSize

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 8) {
            AdMobBannerRepresentable(
                adUnitID: adUnitID,
                size: size,
                onReceiveAd: {
                    isLoading = false
                    errorMessage = nil
                },
                onFailToReceiveAd: { _ in
                    isLoading = false
                    errorMessage = adUnavailableMessage
                },
                reloadToken: reloadToken
            )
            .id(reloadToken)
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .tertiarySystemBackground))
            )

            if isLoading {
                ProgressView("広告を読み込み中...")
                    .font(.caption)
            } else if errorMessage != nil {
                VStack(spacing: 6) {
                    Text(adUnavailableMessage)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Button("再読み込み") {
                        reloadToken = UUID()
                        isLoading = true
                        errorMessage = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear {
            isLoading = true
            errorMessage = nil
        }
    }
}

// MARK: - AdMobBannerRepresentable

struct AdMobBannerRepresentable: UIViewControllerRepresentable {
    let adUnitID: String
    let size: CGSize
    let onReceiveAd: () -> Void
    let onFailToReceiveAd: (Error) -> Void
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(onReceiveAd: onReceiveAd, onFailToReceiveAd: onFailToReceiveAd)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear

        let bannerView = BannerView(adSize: adSizeFor(cgSize: size))
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = viewController
        bannerView.delegate = context.coordinator
        bannerView.translatesAutoresizingMaskIntoConstraints = false

        viewController.view.addSubview(bannerView)
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor)
        ])

        context.coordinator.bannerView = bannerView
        bannerView.load(Request())

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.bannerView?.rootViewController = uiViewController
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        weak var bannerView: BannerView?
        private let onReceiveAd: () -> Void
        private let onFailToReceiveAd: (Error) -> Void

        init(onReceiveAd: @escaping () -> Void, onFailToReceiveAd: @escaping (Error) -> Void) {
            self.onReceiveAd = onReceiveAd
            self.onFailToReceiveAd = onFailToReceiveAd
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onReceiveAd()
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            onFailToReceiveAd(error)
        }
    }
}

// MARK: - UIApplication extension

extension UIApplication {
    static func topMostViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow })?.rootViewController }
            .first
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topMostViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topMostViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return base
    }
}
