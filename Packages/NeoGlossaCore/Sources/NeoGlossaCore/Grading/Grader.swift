import Foundation

public struct GradeResult: Sendable, Equatable {
    public let isCorrect: Bool
    /// The ratings the user may choose from.
    ///
    /// A wrong answer is graded `again` automatically and offers no buttons —
    /// the user does not get to rate a miss. A right answer offers hard,
    /// good and easy, and never `again`.
    public let offeredRatings: [Rating]
    public let expected: [String]
    public let given: String

    public var automaticRating: Rating? { isCorrect ? nil : .again }
}

/// Strict grading.
///
/// Normalisation does three things and nothing more: trim the ends, collapse
/// internal whitespace, strip trailing sentence punctuation.
///
/// Deliberately *not* normalised:
/// - Case. `termin` fails. German nouns are always capitalised, and drilling
///   that is the point of the app.
/// - Umlauts. `Bucher` fails for `Bücher`; `ae`/`oe`/`ue` are not accepted.
/// - The article. `Termin` fails for `der Termin`.
public struct Grader: Sendable {

    public init() {}

    public func normalise(_ input: String) -> String {
        let collapsed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(collapsed.reversed().drop { ".!?".contains($0) }.reversed())
    }

    /// Grade a German-side answer: exact match after normalisation.
    public func gradeGerman(given: String, expected: [String]) -> GradeResult {
        let normalisedGiven = normalise(given)
        let correct = expected.contains { normalise($0) == normalisedGiven }
        return result(correct, expected: expected, given: normalisedGiven)
    }

    /// Grade an English gloss: any stored sense matches, case-insensitively.
    ///
    /// Capitalisation carries no information in English, so it is not drilled.
    /// A verb gloss may or may not carry its infinitive marker — the source
    /// lists both "to take off" and "move out" — so a leading "to " is
    /// optional on both sides.
    public func gradeEnglish(given: String, expected: [String]) -> GradeResult {
        let normalisedGiven = stripInfinitive(normalise(given).lowercased())
        let correct = expected.contains {
            stripInfinitive(normalise($0).lowercased()) == normalisedGiven
        }
        return result(correct, expected: expected, given: normalise(given))
    }

    private func stripInfinitive(_ text: String) -> String {
        text.hasPrefix("to ") ? String(text.dropFirst(3)) : text
    }

    private func result(_ correct: Bool, expected: [String], given: String) -> GradeResult {
        GradeResult(
            isCorrect: correct,
            offeredRatings: correct ? [.hard, .good, .easy] : [],
            expected: expected,
            given: given
        )
    }
}
