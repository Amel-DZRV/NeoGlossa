import Foundation

public enum CardType: String, Codable, Sendable, CaseIterable {
    /// "appointment" -> `der Termin`. Article required.
    case nounProduction
    /// `der Termin` -> "appointment". Not created when the noun has no gloss.
    case nounRecognition
    /// `der Termin` -> `die Termine`. Locked until the parent matures.
    case nounPlural
    /// "to become" -> `ist geworden`. Auxiliary required.
    case verbPartizip
    /// "wegen" -> `Genitiv`. Typed, like every other card.
    case prepCase

    /// The two cards that are the same fact in opposite directions. Seeing
    /// one shortly after the other is one long rep, not two, so the queue
    /// keeps them apart.
    public var isTranslationCard: Bool {
        self == .nounProduction || self == .nounRecognition
    }
}

/// Whether a card is eligible to be scheduled at all.
public enum CardAvailability: String, Codable, Sendable {
    case active
    /// Deliberately excluded — a cognate's recognition card, were that
    /// feature enabled.
    case suspended
    /// Not yet earned: a plural card whose parent is not mature.
    case locked
}

/// A card as the scheduler sees it. The prompt and answer are resolved from
/// the lexicon at display time; this type carries only scheduling identity.
public struct Card: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let lexemeId: Int
    public let type: CardType
    public var availability: CardAvailability
    public var scheduler: SchedulerState

    public init(
        id: UUID = UUID(),
        lexemeId: Int,
        type: CardType,
        availability: CardAvailability = .active,
        scheduler: SchedulerState = SchedulerState()
    ) {
        self.id = id
        self.lexemeId = lexemeId
        self.type = type
        self.availability = availability
        self.scheduler = scheduler
    }

    /// Two cards are translation siblings when they are the same lexeme's
    /// production and recognition cards. Plural cards are deliberately not
    /// siblings: the plural depends on knowing the gender, so the pair
    /// reinforces rather than leaks.
    public func isTranslationSibling(of other: Card) -> Bool {
        lexemeId == other.lexemeId
            && type.isTranslationCard
            && other.type.isTranslationCard
            && type != other.type
    }
}

/// Builds the card set for a newly introduced lexeme.
public enum CardFactory {

    /// - Parameters:
    ///   - hasGloss: false when the lexeme has no English gloss, in which
    ///     case no recognition card is created rather than one with a
    ///     guessed answer.
    ///   - hasPlural: false for mass and plural-only nouns.
    ///   - introducedOn: the day the lexeme enters the rotation. Only one of
    ///     the two translation cards is due that day; its sibling is seeded a
    ///     day later so the pair never debuts together.
    public static func cards(
        forNoun lexemeId: Int,
        hasGloss: Bool,
        hasPlural: Bool,
        introducedOn day: Date,
        calendar: Calendar = .current
    ) -> [Card] {
        var cards: [Card] = []

        var production = Card(lexemeId: lexemeId, type: .nounProduction)
        production.scheduler.due = day
        cards.append(production)

        if hasGloss {
            var recognition = Card(lexemeId: lexemeId, type: .nounRecognition)
            recognition.scheduler.due = WeekdayShift.shift(
                calendar.date(byAdding: .day, value: 1, to: day) ?? day,
                calendar: calendar
            )
            cards.append(recognition)
        }

        if hasPlural {
            var plural = Card(lexemeId: lexemeId, type: .nounPlural)
            plural.availability = .locked
            plural.scheduler.due = day
            cards.append(plural)
        }

        return cards
    }

    public static func card(forIrregularVerb lexemeId: Int, introducedOn day: Date) -> Card {
        var card = Card(lexemeId: lexemeId, type: .verbPartizip)
        card.scheduler.due = day
        return card
    }

    public static func card(forPreposition lexemeId: Int, introducedOn day: Date) -> Card {
        var card = Card(lexemeId: lexemeId, type: .prepCase)
        card.scheduler.due = day
        return card
    }

    /// Unlock any plural card whose parent production card has matured.
    ///
    /// The plural depends on knowing the gender, so it is not graded before
    /// the gender is solid.
    public static func unlockMaturedPlurals(in cards: inout [Card]) -> Int {
        let matureParents = Set(
            cards.filter { $0.type == .nounProduction && $0.scheduler.isLearned }
                .map(\.lexemeId)
        )
        var unlocked = 0
        for index in cards.indices
        where cards[index].type == .nounPlural
            && cards[index].availability == .locked
            && matureParents.contains(cards[index].lexemeId) {
            cards[index].availability = .active
            unlocked += 1
        }
        return unlocked
    }
}
