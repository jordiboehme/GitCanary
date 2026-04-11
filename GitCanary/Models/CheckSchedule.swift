import Foundation

struct CheckSchedule: Identifiable, Codable, Equatable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var weekdays: Set<Int> // 1=Sunday, 7=Saturday (Calendar convention)
    var lastExecutedDate: Date?

    func nextFireDate(after date: Date = Date()) -> Date? {
        let calendar = Calendar.current
        let now = calendar.dateComponents([.hour, .minute, .second, .weekday], from: date)

        for dayOffset in 0..<8 {
            guard let candidate = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let weekday = calendar.component(.weekday, from: candidate)
            guard weekdays.contains(weekday) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: candidate)
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard let fireDate = calendar.date(from: components) else { continue }

            if dayOffset == 0 {
                let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
                let scheduleMinutes = hour * 60 + minute
                if currentMinutes >= scheduleMinutes {
                    continue
                }
            }

            return fireDate
        }
        return nil
    }

    func lastMissedDate(since date: Date, now: Date = Date()) -> Date? {
        guard let lastExec = lastExecutedDate else {
            return mostRecentPastDate(before: now, after: date)
        }
        return mostRecentPastDate(before: now, after: lastExec)
    }

    private func mostRecentPastDate(before now: Date, after: Date) -> Date? {
        let calendar = Calendar.current
        for dayOffset in 0..<7 {
            guard let candidate = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: candidate)
            guard weekdays.contains(weekday) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: candidate)
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard let fireDate = calendar.date(from: components),
                  fireDate < now,
                  fireDate > after else { continue }

            return fireDate
        }
        return nil
    }
}
