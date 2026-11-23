import EventKit
import Foundation

/// "Remind me at 4 to …" (#47): a real Reminder through EventKit. macOS asks for Reminders access once.
@MainActor
enum Reminders {
    static let store = EKEventStore()

    /// `due`: local "yyyy-MM-ddTHH:mm" (or with seconds), or "" for no time.
    static func add(title: String, due: String) async -> (ok: Bool, detail: String) {
        do {
            guard try await store.requestFullAccessToReminders() else { return (false, "Reminders access is off for Zoe") }
        } catch {
            return (false, "couldn't ask for Reminders access: \(error.localizedDescription)")
        }
        guard let cal = store.defaultCalendarForNewReminders() else { return (false, "no default Reminders list") }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = cal
        var detail = "in \(cal.title)"
        if let date = parse(due) {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            r.dueDateComponents = comps
            r.addAlarm(EKAlarm(absoluteDate: date))
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
            detail = "\(f.string(from: date)), \(detail)"
        }
        do {
            try store.save(r, commit: true)
            return (true, detail)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    static func parse(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        return ISO8601DateFormatter().date(from: t)
    }
}
