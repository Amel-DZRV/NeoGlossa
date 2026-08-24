import Foundation
import Testing
@testable import NeoGlossaCore

@Suite("FSRS-5")
struct FSRSTests {

    let fsrs = FSRS()

    @Test("Initial stability matches the reference weights")
    func initialStability() {
        // w0…w3 are the first-review stabilities for Again…Easy.
        #expect(abs(fsrs.initialStability(.again) - 0.40255) < 1e-5)
        #expect(abs(fsrs.initialStability(.hard) - 1.18385) < 1e-5)
        #expect(abs(fsrs.initialStability(.good) - 3.173) < 1e-5)
        #expect(abs(fsrs.initialStability(.easy) - 15.69105) < 1e-5)
    }

    @Test("A first Good schedules about three days, a first Easy about sixteen")
    func firstIntervals() {
        let good = fsrs.interval(stability: fsrs.initialStability(.good))
        let easy = fsrs.interval(stability: fsrs.initialStability(.easy))
        #expect(abs(good - 3.17) < 0.05)
        #expect(abs(easy - 15.69) < 0.05)
    }

    @Test("Difficulty falls as the grade rises")
    func difficultyOrdering() {
        #expect(fsrs.initialDifficulty(.again) > fsrs.initialDifficulty(.good))
        #expect(fsrs.initialDifficulty(.good) > fsrs.initialDifficulty(.easy))
    }

    @Test("Interval and retrievability are inverses at the target retention")
    func intervalInvertsRetrievability() {
        let stability = 10.0
        let days = fsrs.interval(stability: stability)
        #expect(abs(fsrs.retrievability(days: days, stability: stability) - 0.9) < 1e-9)
    }

    @Test("Recall raises stability, and Hard raises it less than Easy")
    func recallOrdering() {
        let d = 5.0, s = 10.0, r = 0.9
        let hard = fsrs.stabilityAfterRecall(difficulty: d, stability: s, retrievability: r, rating: .hard)
        let good = fsrs.stabilityAfterRecall(difficulty: d, stability: s, retrievability: r, rating: .good)
        let easy = fsrs.stabilityAfterRecall(difficulty: d, stability: s, retrievability: r, rating: .easy)
        #expect(hard > s)
        #expect(hard < good)
        #expect(good < easy)
    }

    @Test("A lapse can never raise stability")
    func lapseNeverRaises() {
        for stability in [1.0, 10.0, 100.0, 1000.0] {
            let after = fsrs.stabilityAfterLapse(difficulty: 5, stability: stability, retrievability: 0.9)
            #expect(after <= stability)
        }
    }

    @Test("A higher target retention schedules shorter intervals")
    func retentionShortensIntervals() {
        let strict = FSRS(targetRetention: 0.95).interval(stability: 100)
        let normal = FSRS(targetRetention: 0.90).interval(stability: 100)
        let loose = FSRS(targetRetention: 0.80).interval(stability: 100)
        #expect(strict < normal)
        #expect(normal < loose)
    }

    @Test("Repeated Good answers grow stability monotonically")
    func repeatedGoodGrows() {
        var state = fsrs.review(SchedulerState(), rating: .good, now: monday)
        var previous = state.stability
        for step in 1...5 {
            let now = monday.addingTimeInterval(Double(step) * 40 * 86_400)
            state = fsrs.review(state, rating: .good, now: now)
            #expect(state.stability > previous)
            previous = state.stability
        }
        #expect(state.isLearned)
    }

    @Test("A card is only learned past 21 days of stability")
    func maturityThreshold() {
        #expect(SchedulerState(stability: 20.9).isLearned == false)
        #expect(SchedulerState(stability: 21.1).isLearned == true)
    }
}
