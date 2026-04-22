# 体調メモ Condition

iOS 向けの健康記録アプリです。SwiftUI と SwiftData で開発しています。

**User Guide**
[English](https://docs.azukid.com/en/sumpo/Condition/condition.html) / [日本語](https://docs.azukid.com/jp/sumpo/Condition/condition.html)

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
[![App Store](https://img.shields.io/badge/App%20Store-Download-blue)](https://apps.apple.com/app/id472914799)

## 概要

Condition は、血圧、心拍数、体温、体重、体脂肪率、骨格筋率などを記録して、日々の変化を確認するためのアプリです。

2012 年に公開した旧版を、2026 年に SwiftUI / SwiftData ベースで再構築しました。旧 Core Data 版の記録は、初回起動時に SwiftData へ自動移行します。

## 機能

- 血圧（収縮期 / 拡張期）、心拍数、体温、体重、体脂肪率、骨格筋率の記録
- 測定タイミングの自動分類 — 起床時、安静時、就寝前、就寝時、運動前、運動後
- [AZDial](https://github.com/SumPositive/AZDial) によるダイアル入力 — ハプティック付きのスクロールホイール操作
- Apple ヘルスケア連携 — 書き込みのみ、読み込みのみ、双方向を選択可能
- グラフ表示 — 1週間、1ヶ月、3ヶ月、6ヶ月、1年の期間を切り替え
- 補助グラフ — 平均血圧、体重移動平均などを表示可能
- 統計分析 — 血圧分布、JSH 基準比率、測定タイミングとの相関など
- PDF、CSV、JSON での書き出し
- 表示項目と並び順のカスタマイズ
- 外観モード — 自動、ライト、ダーク
- ダイアル設定 — デザイン、回しやすさ、反応を調整可能

## 構成

```text
Condition/
├── Components/       — 共通 UI コンポーネント
├── Core/
│   ├── Models/       — BodyRecord、DateOpt、MeasureRange
│   ├── DataStore/    — SwiftData 設定、旧 Core Data からの移行
│   ├── Services/     — HealthKitService、PDFPanelExporter
│   └── Settings/     — AppSettings、設定キー、TipStore
├── Features/
│   ├── RecordList/   — 記録一覧、エクスポート
│   ├── RecordEdit/   — 記録入力、編集、ダイアル入力
│   ├── Graph/        — グラフ表示、PDF 出力
│   ├── Statistics/   — 統計表示、PDF 出力
│   └── Settings/     — 設定画面
└── Resources/        — アセット、ローカライズ、Info.plist
```

**主な依存関係**
- [AZDial](https://github.com/SumPositive/AZDial) — SwiftUI スクロールホイール型ダイアル
- Google Mobile Ads SDK

## 必要環境

- iOS 17.0+
- Xcode 26+
- Swift 6

## リリース履歴

| バージョン | 公開日 | 内容 |
|---|---|---|
| 2.0.0 | 2026-04-01 | SwiftUI / SwiftData で全面再構築、HealthKit 連携を追加 |
| 2.1.0 | 2026-04-22 | 外観モード、ダイアル設定、グラフ表示設定、ローカライズ改善 |

## ライセンス

本リポジトリのソースコードは参照目的で公開しています。
著作権は SumPositive に帰属します。
無断での複製、改変、再配布、商用利用を禁止します。
