import Foundation
import SwiftData
import NeoGlossaCore

/// One answered card. Append-only.
///
/// This table is never mutated or pruned. It is the record that survives a
/// bad migration, and the source the rolling seconds-per-card average is
/// computed from.
@Model
final class ReviewLogEntry {
    #Index<ReviewLogEntry>([\.reviewedAt])

    var lexemeId: Int = 0
    var typeRaw: String = ""
    var reviewedAt: Date = Date()
    var ratingRaw: Int = Rating.good.rawValue
    var wasCorrect: Bool = true
    var given: String = ""
    var elapsedSeconds: Double = 0

    init(
        lexemeId: Int, type: CardType, reviewedAt: Date = Date(),
        rating: Rating, wasCorrect: Bool, given: String, elapsedSeconds: Double
    ) {
        self.lexemeId = lexemeId
        self.typeRaw = type.rawValue
        self.reviewedAt = reviewedAt
        self.ratingRaw = rating.rawValue
        self.wasCorrect = wasCorrect
        self.given = given
        self.elapsedSeconds = elapsedSeconds
    }
}

/// A miss, kept for the error log the user exports to Obsidian.
@Model
final class ErrorLogEntry {
    var lexemeId: Int = 0
    var occurredAt: Date = Date()
    var prompt: String = ""
    var correctAnswer: String = ""
    var given: String = ""
    var article: String?

    init(
        lexemeId: Int, occurredAt: Date = Date(), prompt: String,
        correctAnswer: String, given: String, article: String?
    ) {
        self.lexemeId = lexemeId
        self.occurredAt = occurredAt
        self.prompt = prompt
        self.correctAnswer = correctAnswer
        self.given = given
        self.article = article
    }
}

/// Single-row bookkeeping: when studying started, and which weekdays were
/// studied, for the streak.
@Model
final class StudyMeta {
    var startedOn: Date = Date()
    var studiedDays: [Date] = []

    init(startedOn: Date = Date()) {
        self.startedOn = startedOn
    }

    /// Weekday-aware streak: a skipped weekend does not break it.
    func streak(calendar: Calendar = .current, now: Date = Date()) -> Int {
        let days = Set(studiedDays.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        var count = 0
        var cursor = calendar.startOfDay(for: now)
        // Today not yet studied is not a break — start from the last weekday.
        if !days.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while true {
            if calendar.isDateInWeekend(cursor) {
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                continue
            }
            guard days.contains(cursor) else { break }
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return count
    }

    func markStudied(_ date: Date = Date(), calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        if !studiedDays.contains(day) { studiedDays.append(day) }
    }
}
