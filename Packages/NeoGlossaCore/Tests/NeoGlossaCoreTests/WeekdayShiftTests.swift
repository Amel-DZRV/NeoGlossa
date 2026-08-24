import Foundation
import Testing
@testable import NeoGlossaCore

@Suite("Weekday shifting")
struct WeekdayShiftTests {

    let calendar = Calendar(identifier: .gregorian)

    @Test("No card is ever due on a Saturday or Sunday")
    func neverLandsOnWeekend() {
        // Walk a full year of due dates and check every one.
        for offset in 0..<365 {
            let raw = calendar.date(byAdding: .day, value: offset, to: monday)!
            let shifted = WeekdayShift.shift(raw, calendar: calendar)
            #expect(calendar.isDateInWeekend(shifted) == false)
        }
    }

    @Test("A weekday is left where it is")
    func weekdayUnchanged() {
        #expect(WeekdayShift.shift(monday, calendar: calendar) == monday)
    }

    @Test("Saturday and Sunday both roll forward to Monday")
    func weekendRollsForward() {
        let saturday = calendar.date(byAdding: .day, value: 5, to: monday)!
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!
        #expect(WeekdayShift.shift(saturday, calendar: calendar) == nextMonday)
        #expect(WeekdayShift.shift(sunday, calendar: calendar) == nextMonday)
    }
}
