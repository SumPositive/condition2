// CalendarService.swift
// EventKit 連携（旧 AppDelegate + E2editTVC のカレンダー操作）

import Foundation
import EventKit
import OSLog

private let logger = Logger(subsystem: "com.azukid.AzBodyNote", category: "Calendar")

@Observable
@MainActor
final class CalendarService {

    static let shared = CalendarService()

    nonisolated(unsafe) private let eventStore = EKEventStore()
    var isAuthorized = false
    var availableCalendars: [EKCalendar] = []

    private init() {}

    // MARK: - 権限リクエスト

    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            isAuthorized = granted
            if granted {
                loadCalendars()
            }
            logger.info("カレンダーアクセス: \(granted)")
        } catch {
            isAuthorized = false
            logger.error("カレンダー権限エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - カレンダー一覧

    func loadCalendars() {
        availableCalendars = eventStore.calendars(for: .event)
            .sorted { $0.title < $1.title }
    }

    func calendar(for id: String) -> EKCalendar? {
        guard !id.isEmpty else { return nil }
        return eventStore.calendar(withIdentifier: id)
    }

    // MARK: - イベント追加・更新

    func saveEvent(
        title: String,
        notes: String,
        date: Date,
        eventID: String?,
        calendarID: String
    ) -> String? {
        guard isAuthorized,
              let calendar = self.calendar(for: calendarID) else { return nil }

        let event: EKEvent
        if let eid = eventID, !eid.isEmpty,
           let existing = eventStore.event(withIdentifier: eid) {
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
        }

        event.title    = title
        event.notes    = notes
        event.calendar = calendar
        event.startDate = date
        event.endDate   = date.addingTimeInterval(3600)
        event.isAllDay  = false

        do {
            try eventStore.save(event, span: .thisEvent)
            logger.info("イベント保存: \(event.eventIdentifier ?? "")")
            return event.eventIdentifier
        } catch {
            logger.error("イベント保存失敗: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - イベント削除

    func deleteEvent(eventID: String) {
        guard !eventID.isEmpty,
              let event = eventStore.event(withIdentifier: eventID) else { return }
        do {
            try eventStore.remove(event, span: .thisEvent)
            logger.info("イベント削除: \(eventID)")
        } catch {
            logger.error("イベント削除失敗: \(error.localizedDescription)")
        }
    }
}
