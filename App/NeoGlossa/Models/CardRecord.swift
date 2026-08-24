import Foundation
import SwiftData
import NeoGlossaCore

/// A card's persisted scheduler state.
///
/// The scheduler itself lives in NeoGlossaCore and knows nothing about
/// SwiftData; this type is the storage boundary between the two.
@Model
final class CardRecord {
    #Index<CardRecord>([\.due], [\.lexemeId])

    var lexemeId: Int = 0
    var typeRaw: String = CardType.nounProduction.rawValue
    var availabilityRaw: String = CardAvailability.active.rawValue

    var stability: Double = 0
    var difficulty: Double = 0
    var due: Date = Date.distantPast
    var lastReview: Date?
    var reps: Int = 0
    var lapses: Int = 0
    var stateRaw: String = CardState.new.rawValue

    init(lexemeId: Int, type: CardType, availability: CardAvailability, scheduler: SchedulerState) {
        self.lexemeId = lexemeId
        self.typeRaw = type.rawValue
        self.availabilityRaw = availability.rawValue
        apply(scheduler)
    }

    var type: CardType {
        get { CardType(rawValue: typeRaw) ?? .nounProduction }
        set { typeRaw = newValue.rawValue }
    }

    var availability: CardAvailability {
        get { CardAvailability(rawValue: availabilityRaw) ?? .active }
        set { availabilityRaw = newValue.rawValue }
    }

    var scheduler: SchedulerState {
        SchedulerState(
            stability: stability, difficulty: difficulty, due: due,
            lastReview: lastReview, reps: reps, lapses: lapses,
            state: CardState(rawValue: stateRaw) ?? .new
        )
    }

    func apply(_ state: SchedulerState) {
        stability = state.stability
        difficulty = state.difficulty
        due = state.due
        lastReview = state.lastReview
        reps = state.reps
        lapses = state.lapses
        stateRaw = state.state.rawValue
    }

    /// The in-memory form the scheduler and queue builder work with.
    func asCard() -> Card {
        Card(lexemeId: lexemeId, type: type, availability: availability, scheduler: scheduler)
    }
}
