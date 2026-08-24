import Foundation
import Testing
@testable import NeoGlossaCore

@Suite("Card creation and unlocking")
struct CardFactoryTests {

    let calendar = Calendar(identifier: .gregorian)

    @Test("On introduction day only one translation sibling is due")
    func introductionDaySplitsSiblings() {
        let cards = CardFactory.cards(
            forNoun: 1, hasGloss: true, hasPlural: true,
            introducedOn: monday, calendar: calendar
        )
        let dueToday = cards.filter {
            $0.type.isTranslationCard && calendar.isDate($0.scheduler.due, inSameDayAs: monday)
        }
        #expect(dueToday.count == 1)
        #expect(dueToday.first?.type == .nounProduction)

        // Both exist from day one; they just do not both appear on day one.
        #expect(cards.contains { $0.type == .nounRecognition })
    }

    @Test("The deferred sibling is never seeded onto a weekend")
    func siblingSeedAvoidsWeekend() {
        // Introduced on a Friday, so +1 day would land on Saturday.
        let friday = calendar.date(byAdding: .day, value: 4, to: monday)!
        let cards = CardFactory.cards(
            forNoun: 1, hasGloss: true, hasPlural: false,
            introducedOn: friday, calendar: calendar
        )
        let recognition = cards.first { $0.type == .nounRecognition }!
        #expect(calendar.isDateInWeekend(recognition.scheduler.due) == false)
    }

    @Test("A plural card is created locked")
    func pluralStartsLocked() {
        let cards = CardFactory.cards(
            forNoun: 1, hasGloss: true, hasPlural: true,
            introducedOn: monday, calendar: calendar
        )
        let plural = cards.first { $0.type == .nounPlural }
        #expect(plural?.availability == .locked)
    }

    @Test("A noun with no gloss gets no recognition card")
    func noGlossNoRecognitionCard() {
        let cards = CardFactory.cards(
            forNoun: 1, hasGloss: false, hasPlural: true,
            introducedOn: monday, calendar: calendar
        )
        #expect(cards.contains { $0.type == .nounRecognition } == false)
        #expect(cards.contains { $0.type == .nounProduction })
    }

    @Test("A mass or plural-only noun gets no plural card")
    func noPluralNoPluralCard() {
        let cards = CardFactory.cards(
            forNoun: 1, hasGloss: true, hasPlural: false,
            introducedOn: monday, calendar: calendar
        )
        #expect(cards.contains { $0.type == .nounPlural } == false)
    }

    @Test("The plural stays locked until its parent passes 21 days of stability")
    func pluralUnlocksOnParentMaturity() {
        var cards = CardFactory.cards(
            forNoun: 1, hasGloss: true, hasPlural: true,
            introducedOn: monday, calendar: calendar
        )

        // Just short of maturity: still locked.
        let parentIndex = cards.firstIndex { $0.type == .nounProduction }!
        cards[parentIndex].scheduler.stability = 20.9
        #expect(CardFactory.unlockMaturedPlurals(in: &cards) == 0)
        #expect(cards.first { $0.type == .nounPlural }?.availability == .locked)

        // Past it: unlocked.
        cards[parentIndex].scheduler.stability = 21.1
        #expect(CardFactory.unlockMaturedPlurals(in: &cards) == 1)
        #expect(cards.first { $0.type == .nounPlural }?.availability == .active)
    }

    @Test("Another noun's maturity does not unlock this noun's plural")
    func unlockingIsPerLexeme() {
        var cards = CardFactory.cards(
            forNoun: 1, hasGloss: true, hasPlural: true,
            introducedOn: monday, calendar: calendar
        )
        var mature = makeCard(2, .nounProduction)
        mature.scheduler.stability = 100
        cards.append(mature)

        #expect(CardFactory.unlockMaturedPlurals(in: &cards) == 0)
    }
}
