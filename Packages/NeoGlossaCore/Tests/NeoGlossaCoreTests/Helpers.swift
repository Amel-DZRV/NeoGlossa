import Foundation
@testable import NeoGlossaCore

/// Deterministic generator so queue tests do not flake.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64 = 0x2545F491_4F6CDD1D) { state = seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// A weekday, so tests are never accidentally shifted by WeekdayShift.
let monday: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 24  // a Monday
    components.hour = 9
    return Calendar(identifier: .gregorian).date(from: components)!
}()

func makeCard(_ lexemeId: Int, _ type: CardType, due: Date = monday) -> Card {
    var card = Card(lexemeId: lexemeId, type: type)
    card.scheduler.due = due
    return card
}
