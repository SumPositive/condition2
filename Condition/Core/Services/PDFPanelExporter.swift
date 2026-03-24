// PDFPanelExporter.swift
// グラフ・統計パネルをA4縦PDFに変換するユーティリティ

import SwiftUI  // AnyView
import UIKit

@MainActor
enum PDFPanelExporter {

    // MARK: - 定数

    static let contentW: CGFloat = 563

    private static let pageW: CGFloat = 595
    private static let pageH: CGFloat = 842
    private static let margin: CGFloat = 16
    private static let panelSpacing: CGFloat = 12
    private static let titleBlockH: CGFloat = 50
    private static let footerH: CGFloat = 22

    // MARK: - 公開API

    /// panels を A4縦PDF に変換して Data を返す。
    /// - Parameters:
    ///   - panels: 各パネルのビュー（AnyView）
    ///   - title:  1ページ目に大きく表示するタイトル
    ///   - subtitle: タイトル下に小さく表示するサブタイトル（期間・日付など）
    static func export(panels: [AnyView], title: String, subtitle: String) -> Data {
        let images = panels
            .compactMap { renderToImage($0) }
            .filter { $0.size.height > 2 }   // 空ビューを除外

        guard !images.isEmpty else { return Data() }

        let pages = layoutPages(images: images)
        let pageRect = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { ctx in
            for (idx, pageImages) in pages.enumerated() {
                ctx.beginPage()
                drawPage(
                    in: ctx.cgContext,
                    images: pageImages,
                    isFirst: idx == 0,
                    pageNum: idx + 1,
                    totalPages: pages.count,
                    title: title,
                    subtitle: subtitle
                )
            }
        }
    }

    /// 一時ディレクトリに PDF ファイルを書き出し URL を返す。
    static func writeTempFile(name: String, data: Data) -> URL? {
        guard !data.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - レンダリング

    private static func renderToImage(_ view: AnyView) -> UIImage? {
        // Swift Charts のエントリアニメーションを完全に止めるため、
        // ImageRenderer ではなく UIHostingController + UIGraphicsImageRenderer を使用する。
        // UIView.setAnimationsEnabled(false) と CATransaction.setDisableActions(true) を
        // 組み合わせることで CA レベルのアニメーションも無効化し、
        // マークが最終状態で即座に描画されるようにする。
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }

        let hostVC = UIHostingController(rootView:
            view
                .frame(width: contentW)
                .environment(\.colorScheme, .light)
        )
        hostVC.view.backgroundColor = .white

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let fitting = hostVC.sizeThatFits(in: CGSize(
            width: contentW,
            height: UIView.layoutFittingCompressedSize.height
        ))
        let h = fitting.height > 0 ? fitting.height : 300
        let size = CGSize(width: contentW, height: h)
        hostVC.view.frame = CGRect(origin: .zero, size: size)
        hostVC.view.setNeedsLayout()
        hostVC.view.layoutIfNeeded()

        CATransaction.commit()

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            hostVC.view.drawHierarchy(
                in: CGRect(origin: .zero, size: size),
                afterScreenUpdates: true
            )
        }
    }

    // MARK: - ページレイアウト

    private static func layoutPages(images: [UIImage]) -> [[UIImage]] {
        let usableH = pageH - margin * 2 - footerH
        var pages: [[UIImage]] = [[]]
        // 1ページ目はタイトルブロック分だけ先行消費
        var usedH: CGFloat = titleBlockH

        for img in images {
            let h = img.size.height
            let addSpacing: CGFloat = pages[pages.count - 1].isEmpty ? 0 : panelSpacing
            if !pages[pages.count - 1].isEmpty && usedH + addSpacing + h > usableH {
                // 新しいページへ
                pages.append([])
                usedH = 0
            }
            let sp: CGFloat = pages[pages.count - 1].isEmpty ? 0 : panelSpacing
            pages[pages.count - 1].append(img)
            usedH += sp + h
        }

        return pages
    }

    // MARK: - ページ描画

    private static func drawPage(
        in ctx: CGContext,
        images: [UIImage],
        isFirst: Bool,
        pageNum: Int,
        totalPages: Int,
        title: String,
        subtitle: String
    ) {
        var y = margin

        if isFirst {
            let titleFont = UIFont.boldSystemFont(ofSize: 18)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]
            (title as NSString).draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: titleAttrs
            )
            y += titleFont.lineHeight + 4

            let subFont = UIFont.systemFont(ofSize: 11)
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: subFont,
                .foregroundColor: UIColor.darkGray
            ]
            (subtitle as NSString).draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: subAttrs
            )
            y += subFont.lineHeight + panelSpacing
        }

        for (i, img) in images.enumerated() {
            if i > 0 { y += panelSpacing }
            img.draw(in: CGRect(x: margin, y: y, width: contentW, height: img.size.height))
            y += img.size.height
        }

        // ページ番号
        let footerFont = UIFont.systemFont(ofSize: 10)
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: UIColor.gray
        ]
        let footerStr = "\(pageNum) / \(totalPages)" as NSString
        let footerSize = footerStr.size(withAttributes: footerAttrs)
        footerStr.draw(
            at: CGPoint(
                x: (pageW - footerSize.width) / 2,
                y: pageH - margin - footerSize.height
            ),
            withAttributes: footerAttrs
        )
    }
}
