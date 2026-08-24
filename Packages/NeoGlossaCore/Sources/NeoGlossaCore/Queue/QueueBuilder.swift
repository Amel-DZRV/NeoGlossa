import Foundation

/// Orders a day's cards, keeping translation siblings apart.
///
/// The problem this exists for: `EN -> der Termin` followed immediately by
/// `der Termin -> EN` is not recall. The answer is still in working memory.
/// That is one long rep, not two.
///
/// Rules:
/// 1. Introduction day — only one of a noun's two translation cards is due
///    that day. Handled at creation time by `CardFactory`, not here.
/// 2. Minimum separation — at least 15 other cards between translation
///    siblings that fall due together.
/// 3. Defer if it does not fit — a session too short to separate them pushes
///    the second sibling to tomorrow.
/// 4. Plural siblings are exempt. `nounProduction` and `nounPlural` may sit
///    close together; the plural depends on the gender, so the pair
///    reinforces rather than leaks.
/// 5. New cards spread evenly, never front-loaded. Twenty new words in a
///    block at the start is a wall; spread through, they act as breaks.
///
/// Card types are never sorted together — nouns, verbs and prepositions
/// interleave.
public struct QueueBuilder: Sendable {

    /// Other cards required between two translation siblings.
    public static let minimumSeparation = 15

    /// Where a missed card is reinserted, relative to the current position.
    public static let reinsertionOffset = 3

    public let minimumSeparation: Int

    public init(minimumSeparation: Int = QueueBuilder.minimumSeparation) {
        self.minimumSeparation = minimumSeparation
    }

    public struct Result: Sendable {
        public let queue: [Card]
        /// Siblings that could not be separated within this session.
        public let deferred: [Card]
    }

    /// - Parameters:
    ///   - due: review cards due today. Suspended and locked cards are
    ///     filtered out here rather than trusted to the caller.
    ///   - new: cards being introduced today, already capped by the throttle.
    ///   - generator: injected so tests are deterministic.
    public func build(
        due: [Card],
        new: [Card],
        using generator: inout some RandomNumberGenerator
    ) -> Result {
        let reviews = due.filter { $0.availability == .active }.shuffled(using: &generator)
        let newcomers = new.filter { $0.availability == .active }.shuffled(using: &generator)
        let interleaved = spread(new: newcomers, through: reviews)

        var queue: [Card] = []
        var pending: [Card] = []
        var lastTranslationSlot: [Int: Int] = [:]

        func canPlace(_ card: Card) -> Bool {
            guard card.type.isTranslationCard,
                  let previous = lastTranslationSlot[card.lexemeId]
            else { return true }
            return queue.count - previous > minimumSeparation
        }

        func place(_ card: Card) {
            if card.type.isTranslationCard {
                lastTranslationSlot[card.lexemeId] = queue.count
            }
            queue.append(card)
        }

        for card in interleaved {
            if canPlace(card) {
                place(card)
            } else {
                pending.append(card)
            }
            // Every placement moves the window, so a blocked card may now fit.
            drain(&pending, canPlace: canPlace, place: place)
        }

        // Nothing left to push the window forward: whatever still cannot be
        // separated goes to tomorrow rather than being crammed in.
        drain(&pending, canPlace: canPlace, place: place)
        return Result(queue: queue, deferred: pending)
    }

    /// Convenience overload using the system generator.
    public func build(due: [Card], new: [Card]) -> Result {
        var generator = SystemRandomNumberGenerator()
        return build(due: due, new: new, using: &generator)
    }

    private func drain(
        _ pending: inout [Card],
        canPlace: (Card) -> Bool,
        place: (Card) -> Void
    ) {
        var progressed = true
        while progressed, !pending.isEmpty {
            progressed = false
            for index in pending.indices where canPlace(pending[index]) {
                place(pending[index])
                pending.remove(at: index)
                progressed = true
                break
            }
        }
    }

    /// Distribute new cards evenly across the reviews rather than in a block.
    func spread(new: [Card], through reviews: [Card]) -> [Card] {
        guard !new.isEmpty else { return reviews }
        guard !reviews.isEmpty else { return new }

        var result: [Card] = []
        result.reserveCapacity(new.count + reviews.count)

        let step = Double(reviews.count) / Double(new.count + 1)
        var nextNew = 0
        for (index, review) in reviews.enumerated() {
            // Place a new card once the running position passes its slot, so
            // the first new card never lands at index 0.
            while nextNew < new.count, Double(index) >= step * Double(nextNew + 1) {
                result.append(new[nextNew])
                nextNew += 1
            }
            result.append(review)
        }
        result.append(contentsOf: new[nextNew...])
        return result
    }

    /// Put a missed card back into the running session.
    ///
    /// It returns `reinsertionOffset` positions ahead of the current one. The
    /// separation rule does not apply: this is the same card returning, not a
    /// sibling leaking its answer.
    public func reinsert(
        _ card: Card, into queue: inout [Card], currentIndex: Int
    ) {
        let target = min(currentIndex + Self.reinsertionOffset, queue.count)
        queue.insert(card, at: target)
    }
}
