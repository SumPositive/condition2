// PurchaseService.swift
// StoreKit 2 による In-App Purchase
// 旧 STORE_PRODUCTID_UNLOCK と同一の ProductID を継続使用

import Foundation
import StoreKit
import OSLog

private let logger = Logger(subsystem: "com.azukid.AzBodyNote", category: "Purchase")

@Observable
@MainActor
final class PurchaseService {

    static let shared = PurchaseService()

    private let productID = AppConstants.unlockProductID
    var product: Product?
    var purchaseError: String?

    private init() {}

    // MARK: - 購入状態確認

    func checkStatus() async {
        // Transaction.currentEntitlement で既存購入を確認
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == productID {
                AppSettings.shared.isUnlocked = true
                NSUbiquitousKeyValueStore.default.set(true, forKey: KVSKeys.unlockProductID)
                logger.info("購入済み確認: \(self.productID)")
                return
            }
        }
        // KVS からも確認（旧バージョン互換）
        if NSUbiquitousKeyValueStore.default.bool(forKey: KVSKeys.unlockProductID) {
            AppSettings.shared.isUnlocked = true
        }
    }

    // MARK: - 商品情報取得

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [productID])
            product = products.first
        } catch {
            logger.error("商品情報取得失敗: \(error.localizedDescription)")
        }
    }

    // MARK: - 購入

    func purchase() async {
        guard let product else {
            await loadProduct()
            guard let product else { return }
            await doPurchase(product)
            return
        }
        await doPurchase(product)
    }

    private func doPurchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    AppSettings.shared.isUnlocked = true
                    NSUbiquitousKeyValueStore.default.set(true, forKey: KVSKeys.unlockProductID)
                    await tx.finish()
                    logger.info("購入成功")
                }
            case .userCancelled:
                logger.info("購入キャンセル")
            case .pending:
                logger.info("購入保留中")
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
            logger.error("購入エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - 復元

    func restore() async {
        do {
            try await AppStore.sync()
            await checkStatus()
            logger.info("購入復元完了")
        } catch {
            purchaseError = error.localizedDescription
            logger.error("復元エラー: \(error.localizedDescription)")
        }
    }
}
