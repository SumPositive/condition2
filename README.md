# 体調メモ Condition

A health diary app for iOS, built with SwiftUI and SwiftData.

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
[![App Store](https://img.shields.io/badge/App%20Store-Download-blue)](https://apps.apple.com/app/id472914799)

## Overview

Condition lets you record and track your daily health data — blood pressure, pulse, weight, body temperature, steps, body fat, and skeletal muscle rate. Originally released in 2012, fully rebuilt in 2026 with SwiftData and HealthKit integration.

Past records are automatically migrated from the previous Core Data version.

## Features

- Record blood pressure (systolic / diastolic), pulse, weight, body temperature, steps, body fat, skeletal muscle rate
- Dial input via [AZDial](https://github.com/SumPositive/AZDial) — scroll-wheel control with haptic feedback
- HealthKit sync — bidirectional, read-only, or write-only
- Graph view — timeline charts per metric with goal lines and moving average
- Statistics view — min / max / average per period
- Dark mode and VoiceOver support

## Architecture

```
Condition/
├── App/              — App entry point, AppSettings
├── Core/
│   ├── Models/       — BodyRecord (SwiftData), DateOpt, MeasureRange
│   ├── DataStore/    — Migration from Core Data
│   └── Services/     — HealthKitService
├── Features/
│   ├── RecordList/   — Main list view
│   ├── RecordEdit/   — Edit / new record with dial input
│   ├── Graph/        — Chart views
│   ├── Statistics/   — Stats views
│   └── Settings/     — App settings
└── Components/       — Shared UI components
```

**Key dependency**
- [AZDial](https://github.com/SumPositive/AZDial) — SwiftUI scroll-wheel dial control

## Requirements

- iOS 17.0+
- Xcode 16+
- Swift 6

## License

MIT License. See [LICENSE](LICENSE) for details.
