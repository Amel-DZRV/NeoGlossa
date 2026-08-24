import Foundation

/// Rolls due dates off the weekend.
///
/// The user studies weekdays only. Without this, everything that would have
/// fallen on a Saturday or Sunday piles onto Monday, making it permanently
/// about 2.4x heavier than a Thursday.
public enum WeekdayShift {

    public static func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDateInWeekend(date)
    }

    /// The same date, or the next weekday if it lands on a weekend.
    public static func shift(_ date: Date, calendar: Calendar = .current) -> Date {
        var result = date
        var guardCount = 0
        while calendar.isDateInWeekend(result) && guardCount < 7 {
            result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
            guardCount += 1
        }
        return result
    }

    /// Apply the shift to a scheduler state's due date.
    public static func apply(to state: SchedulerState, calendar: Calendar = .current) -> SchedulerState {
        var shifted = state
        shifted.due = shift(state.due, calendar: calendar)
        return shifted
    }
}
