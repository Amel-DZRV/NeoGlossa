import Foundation

/// Chooses which lexemes enter the rotation next, and builds their cards.
///
/// Ordering is A1 before A2, as a hard gate rather than a setting: no A2 word
/// is introduced while an A1 word remains unseen.
public struct Introducer: Sendable {

    public init() {}

    /// - Parameters:
    ///   - catalogue: every card-bearing lexeme, already A1-first.
    ///   - alreadyIntroduced: lexeme ids that have cards.
    ///   - count: how many to introduce, from the throttle.
    public func introduce(
        from catalogue: [Lexeme],
        alreadyIntroduced: Set<Int>,
        count: Int,
        on day: Date,
        calendar: Calendar = .current
    ) -> [Card] {
        guard count > 0 else { return [] }

        var cards: [Card] = []
        var introduced = 0

        for lexeme in catalogue where !alreadyIntroduced.contains(lexeme.id) {
            if introduced >= count { break }

            switch lexeme.pos {
            case "noun":
                cards.append(contentsOf: CardFactory.cards(
                    forNoun: lexeme.id,
                    hasGloss: !lexeme.glosses.isEmpty,
                    hasPlural: lexeme.plural != nil && !lexeme.pluralOnly,
                    introducedOn: day,
                    calendar: calendar
                ))
            case "verb":
                guard lexeme.isIrregular else { continue }
                cards.append(CardFactory.card(forIrregularVerb: lexeme.id, introducedOn: day))
            case "preposition":
                cards.append(CardFactory.card(forPreposition: lexeme.id, introducedOn: day))
            default:
                continue
            }
            introduced += 1
        }

        return cards
    }
}
