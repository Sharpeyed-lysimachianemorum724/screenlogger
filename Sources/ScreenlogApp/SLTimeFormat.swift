import Foundation

enum SLTimeFormat {
    static func relative(_ timestampMs: Int64, relativeTo now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func shortTime(_ timestampMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func full(_ timestampMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        return date.formatted(date: .abbreviated, time: .standard)
    }

    static func dayLabel(_ timestampMs: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func sameCalendarDay(_ first: Int64, _ second: Int64) -> Bool {
        let firstDate = Date(timeIntervalSince1970: TimeInterval(first) / 1000)
        let secondDate = Date(timeIntervalSince1970: TimeInterval(second) / 1000)
        return Calendar.current.isDate(firstDate, inSameDayAs: secondDate)
    }
}
