import Foundation

/// The four grades a review can be given.
///
/// `again` is only ever produced by a wrong answer — it is never offered as a
/// button on a correct one, and the rating buttons are never offered on a
/// wrong one. See `Grader`.
public enum Rating: Int, Codable, Sendable, CaseIterable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}

public enum CardState: String, Codable, Sendable {
    case new, learning, review, relearning
}

/// Everything the scheduler knows about one card.
public struct SchedulerState: Codable, Sendable, Equatable {
    public var stability: Double
    public var difficulty: Double
    public var due: Date
    public var lastReview: Date?
    public var reps: Int
    public var lapses: Int
    public var state: CardState

    public init(
        stability: Double = 0,
        difficulty: Double = 0,
        due: Date = .distantPast,
        lastReview: Date? = nil,
        reps: Int = 0,
        lapses: Int = 0,
        state: CardState = .new
    ) {
        self.stability = stability
        self.difficulty = difficulty
        self.due = due
        self.lastReview = lastReview
        self.reps = reps
        self.lapses = lapses
        self.state = state
    }

    /// The plan's definition of "learned": stability past three weeks.
    public var isLearned: Bool { stability > FSRS.maturityDays }
}

/// FSRS-5, implemented directly from the published spec and default weights.
///
/// The formulas are the reference ones: retrievability decays as a power
/// function of elapsed time over stability, stability grows on recall by a
/// factor that shrinks as difficulty and current stability rise, and a lapse
/// collapses stability toward a value derived from difficulty.
public struct FSRS: Sendable {

    /// Default FSRS-5 weights, w0…w18.
    public static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046,
        1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315,
        2.9898, 0.51655, 0.6621,
    ]

    static let decay = -0.5
    static let factor = 19.0 / 81.0

    /// Stability at which a card counts as learned, and at which a noun's
    /// plural card unlocks.
    public static let maturityDays = 21.0

    let w: [Double]

    /// Desired probability of recall at the moment a card comes due.
    public let targetRetention: Double

    /// Hard ceiling on any scheduled interval, in days.
    public let maximumInterval: Double

    public init(
        weights: [Double] = FSRS.defaultWeights,
        targetRetention: Double = 0.9,
        maximumInterval: Double = 365 * 10
    ) {
        precondition(weights.count >= 19, "FSRS-5 needs 19 weights")
        self.w = weights
        self.targetRetention = targetRetention
        self.maximumInterval = maximumInterval
    }

    // MARK: - Core formulas

    /// Probability of recall after `days` elapsed at the given stability.
    public func retrievability(days: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + Self.factor * days / stability, Self.decay)
    }

    /// Days until retrievability decays to `targetRetention`.
    public func interval(stability: Double) -> Double {
        let raw = (stability / Self.factor) * (pow(targetRetention, 1 / Self.decay) - 1)
        return min(max(raw, 1), maximumInterval)
    }

    func initialStability(_ rating: Rating) -> Double {
        max(w[rating.rawValue - 1], 0.1)
    }

    func initialDifficulty(_ rating: Rating) -> Double {
        clampDifficulty(w[4] - exp(w[5] * Double(rating.rawValue - 1)) + 1)
    }

    func clampDifficulty(_ d: Double) -> Double { min(max(d, 1), 10) }

    func nextDifficulty(_ difficulty: Double, _ rating: Rating) -> Double {
        let delta = -w[6] * Double(rating.rawValue - 3)
        let linear = difficulty + delta * (10 - difficulty) / 9
        // Mean reversion toward the difficulty an Easy first answer implies.
        return clampDifficulty(w[7] * initialDifficulty(.easy) + (1 - w[7]) * linear)
    }

    func stabilityAfterRecall(
        difficulty: Double, stability: Double, retrievability r: Double, rating: Rating
    ) -> Double {
        let hardPenalty = rating == .hard ? w[15] : 1.0
        let easyBonus = rating == .easy ? w[16] : 1.0
        let growth = exp(w[8])
            * (11 - difficulty)
            * pow(stability, -w[9])
            * (exp(w[10] * (1 - r)) - 1)
            * hardPenalty
            * easyBonus
        return stability * (1 + growth)
    }

    func stabilityAfterLapse(
        difficulty: Double, stability: Double, retrievability r: Double
    ) -> Double {
        let recovered = w[11]
            * pow(difficulty, -w[12])
            * (pow(stability + 1, w[13]) - 1)
            * exp(w[14] * (1 - r))
        // A lapse must never raise stability.
        return min(recovered, stability)
    }

    /// Stability change for a second review on the same day, where no
    /// meaningful time has elapsed for memory to decay.
    func stabilitySameDay(stability: Double, rating: Rating) -> Double {
        stability * exp(w[17] * (Double(rating.rawValue) - 3 + w[18]))
    }

    // MARK: - Scheduling

    /// Apply a review and return the card's new scheduler state.
    ///
    /// The returned `due` date is *not* weekday-shifted; callers pass it
    /// through `WeekdayShift` so the shift stays visible rather than buried in
    /// the maths.
    public func review(
        _ state: SchedulerState, rating: Rating, now: Date = Date()
    ) -> SchedulerState {
        var next = state
        next.reps += 1
        next.lastReview = now

        if state.state == .new {
            next.difficulty = initialDifficulty(rating)
            next.stability = initialStability(rating)
            // A miss on a card's very first showing is not a lapse — there
            // was no established memory to lose.
            next.state = rating == .again ? .learning : .review
        } else {
            let elapsed = state.lastReview.map {
                max(now.timeIntervalSince($0) / 86_400, 0)
            } ?? 0
            let r = retrievability(days: elapsed, stability: state.stability)
            next.difficulty = nextDifficulty(state.difficulty, rating)

            if elapsed < 1 {
                // Same-day re-review: memory has not decayed, so the
                // recall formula would overstate the gain.
                next.stability = stabilitySameDay(stability: state.stability, rating: rating)
            } else if rating == .again {
                next.stability = stabilityAfterLapse(
                    difficulty: next.difficulty, stability: state.stability, retrievability: r
                )
            } else {
                next.stability = stabilityAfterRecall(
                    difficulty: next.difficulty, stability: state.stability,
                    retrievability: r, rating: rating
                )
            }

            if rating == .again {
                next.lapses += 1
                next.state = .relearning
            } else {
                next.state = .review
            }
        }

        next.stability = max(next.stability, 0.1)
        next.due = now.addingTimeInterval(interval(stability: next.stability) * 86_400)
        return next
    }

    /// What each button would schedule, for the interval hints on the
    /// rating buttons.
    public func preview(
        _ state: SchedulerState, now: Date = Date()
    ) -> [Rating: Double] {
        var result: [Rating: Double] = [:]
        for rating in Rating.allCases {
            result[rating] = interval(stability: review(state, rating: rating, now: now).stability)
        }
        return result
    }
}
