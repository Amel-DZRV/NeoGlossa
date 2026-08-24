import Foundation
import Testing
@testable import NeoGlossaCore

@Suite("Queue building and sibling burying")
struct QueueBuilderTests {

    let builder = QueueBuilder()

    /// Smallest gap between any pair of translation siblings in the queue.
    func minimumSiblingGap(_ queue: [Card]) -> Int {
        var lastSlot: [Int: Int] = [:]
        var smallest = Int.max
        for (index, card) in queue.enumerated() where card.type.isTranslationCard {
            if let previous = lastSlot[card.lexemeId] {
                smallest = min(smallest, index - previous)
            }
            lastSlot[card.lexemeId] = index
        }
        return smallest
    }

    @Test("Translation siblings never appear within 15 cards of each other")
    func siblingsStayApart() {
        var generator = SeededGenerator()
        // 20 nouns, both translation cards of each due the same day.
        let due = (1...20).flatMap { id in
            [makeCard(id, .nounProduction), makeCard(id, .nounRecognition)]
        }
        let result = builder.build(due: due, new: [], using: &generator)
        #expect(minimumSiblingGap(result.queue) > QueueBuilder.minimumSeparation)
    }

    @Test("Siblings that cannot be separated are deferred, not crammed in")
    func defersWhenTooShort() {
        var generator = SeededGenerator()
        // Two cards only: there is no room for 15 others between them.
        let due = [makeCard(1, .nounProduction), makeCard(1, .nounRecognition)]
        let result = builder.build(due: due, new: [], using: &generator)
        #expect(result.queue.count == 1)
        #expect(result.deferred.count == 1)
    }

    @Test("Plural siblings are exempt from burying")
    func pluralSiblingsExempt() {
        var generator = SeededGenerator()
        // The plural depends on the gender, so the pair reinforces.
        let due = [makeCard(1, .nounProduction), makeCard(1, .nounPlural)]
        let result = builder.build(due: due, new: [], using: &generator)
        #expect(result.queue.count == 2)
        #expect(result.deferred.isEmpty)
    }

    @Test("Suspended and locked cards never enter the queue")
    func excludesUnavailableCards() {
        var generator = SeededGenerator()
        var suspended = makeCard(1, .nounRecognition)
        suspended.availability = .suspended
        var locked = makeCard(2, .nounPlural)
        locked.availability = .locked

        let result = builder.build(
            due: [makeCard(3, .prepCase), suspended, locked], new: [], using: &generator
        )
        #expect(result.queue.count == 1)
        #expect(result.queue[0].type == .prepCase)
    }

    @Test("New cards are spread through the session, never front-loaded")
    func newCardsAreSpread() {
        var generator = SeededGenerator()
        let due = (1...40).map { makeCard($0, .prepCase) }
        let new = (100...104).map { makeCard($0, .verbPartizip) }
        let result = builder.build(due: due, new: new, using: &generator)

        let positions = result.queue.enumerated()
            .filter { $0.element.type == .verbPartizip }
            .map(\.offset)
        #expect(positions.count == 5)
        // None in the opening block, and they reach into the second half.
        #expect(positions.first! > 2)
        #expect(positions.last! > result.queue.count / 2)
    }

    @Test("A missed card returns three positions later, exempt from separation")
    func reinsertionPlacesCardAhead() {
        var queue = (1...10).map { makeCard($0, .nounProduction) }
        let missed = queue[2]
        builder.reinsert(missed, into: &queue, currentIndex: 2)
        #expect(queue[5].id == missed.id)
        #expect(queue.count == 11)
    }

    @Test("Reinsertion near the end appends rather than overflowing")
    func reinsertionClampsToEnd() {
        var queue = (1...4).map { makeCard($0, .nounProduction) }
        let missed = queue[3]
        builder.reinsert(missed, into: &queue, currentIndex: 3)
        #expect(queue.last?.id == missed.id)
        #expect(queue.count == 5)
    }

    @Test("Card types interleave rather than sorting into blocks")
    func typesInterleave() {
        var generator = SeededGenerator()
        let due = (1...15).map { makeCard($0, .nounProduction) }
            + (20...34).map { makeCard($0, .prepCase) }
        let result = builder.build(due: due, new: [], using: &generator)

        // A sorted queue would have exactly one type change.
        let changes = zip(result.queue, result.queue.dropFirst())
            .filter { $0.type != $1.type }.count
        #expect(changes > 1)
    }
}
