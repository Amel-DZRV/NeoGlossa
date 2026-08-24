import Foundation
import Observation
import SwiftData
import NeoGlossaCore

/// Everything the app does with the scheduler, in one place.
///
/// Constants that a settings screen would have exposed live here. Changing
/// one is a one-line edit and a rebuild, which for a personal build is
/// faster than building a screen.
@Observable
@MainActor
final class StudyStore {

    static let targetDailyMinutes: Double = 45
    static let targetRetention: Double = 0.9

    private let context: ModelContext
    private let lexicon: Lexicon
    private let fsrs: FSRS
    private let grader = Grader()
    private let queueBuilder = QueueBuilder()
    private let introducer = Introducer()
    private let calendar = Calendar.current

    /// Every card-bearing lexeme, A1 first. Read once; it never changes.
    private(set) var catalogue: [Lexeme] = []
    private var lexemesById: [Int: Lexeme] = [:]

    private(set) var queue: [CardRecord] = []
    private(set) var position: Int = 0
    private(set) var misses: [Miss] = []

    struct Miss: Identifiable {
        let id = UUID()
        let lexemeId: Int
        let prompt: String
        let article: String?
        let word: String
        let given: String
        var correctedLater: Bool = false
    }

    init(context: ModelContext, lexicon: Lexicon) {
        self.context = context
        self.lexicon = lexicon
        self.fsrs = FSRS(targetRetention: Self.targetRetention)
        catalogue = (try? lexicon.allCardBearing()) ?? []
        lexemesById = Dictionary(uniqueKeysWithValues: catalogue.map { ($0.id, $0) })
    }

    func lexeme(_ id: Int) -> Lexeme? { lexemesById[id] }

    // MARK: - Home screen figures

    var learnedCount: Int {
        (try? context.fetchCount(
            FetchDescriptor<CardRecord>(
                predicate: #Predicate { $0.stability > 21 }
            )
        )) ?? 0
    }

    var totalWordCount: Int { catalogue.count }

    var dueTodayCount: Int {
        let end = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        let active = CardAvailability.active.rawValue
        return (try? context.fetchCount(
            FetchDescriptor<CardRecord>(
                predicate: #Predicate { $0.due < end && $0.availabilityRaw == active }
            )
        )) ?? 0
    }

    var streak: Int { meta().streak(calendar: calendar) }

    private func meta() -> StudyMeta {
        if let existing = try? context.fetch(FetchDescriptor<StudyMeta>()).first {
            return existing
        }
        let created = StudyMeta()
        context.insert(created)
        return created
    }

    // MARK: - Session

    /// Build today's session: unlock what has matured, introduce what fits,
    /// then order it.
    func startSession(now: Date = Date()) {
        misses = []
        position = 0

        var all = (try? context.fetch(FetchDescriptor<CardRecord>())) ?? []
        unlockMaturedPlurals(in: all)

        let introduced = Set(all.map(\.lexemeId))
        let endOfDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        let dueRecords = all.filter { $0.availability == .active && $0.due < endOfDay }

        let newRecords = makeNewCards(
            dueReviewCount: dueRecords.count, alreadyIntroduced: introduced, now: now
        )
        all.append(contentsOf: newRecords)

        let result = queueBuilder.build(
            due: dueRecords.map { $0.asCard() },
            new: newRecords.map { $0.asCard() }
        )

        // Map the ordered cards back onto their records.
        var byKey: [String: CardRecord] = [:]
        for record in all { byKey["\(record.lexemeId)-\(record.typeRaw)"] = record }
        queue = result.queue.compactMap { byKey["\($0.lexemeId)-\($0.type.rawValue)"] }

        // Anything that could not be separated waits until tomorrow.
        for deferred in result.deferred {
            if let record = byKey["\(deferred.lexemeId)-\(deferred.type.rawValue)"] {
                record.due = WeekdayShift.shift(
                    calendar.date(byAdding: .day, value: 1, to: now) ?? now, calendar: calendar
                )
            }
        }

        meta().markStudied(now, calendar: calendar)
        try? context.save()
    }

    private func unlockMaturedPlurals(in records: [CardRecord]) {
        var cards = records.map { $0.asCard() }
        guard CardFactory.unlockMaturedPlurals(in: &cards) > 0 else { return }
        let unlocked = Set(
            cards.filter { $0.type == .nounPlural && $0.availability == .active }.map(\.lexemeId)
        )
        for record in records
        where record.type == .nounPlural && unlocked.contains(record.lexemeId) {
            record.availability = .active
        }
    }

    private func makeNewCards(
        dueReviewCount: Int, alreadyIntroduced: Set<Int>, now: Date
    ) -> [CardRecord] {
        let throttle = NewCardThrottle(targetMinutes: Self.targetDailyMinutes)
        let count = throttle.newCardCount(
            dueReviewCount: dueReviewCount,
            averageSecondsPerCard: rollingAverageSeconds(),
            weeksSinceStart: NewCardThrottle.weeksSinceStart(from: meta().startedOn, to: now)
        )
        let cards = introducer.introduce(
            from: catalogue, alreadyIntroduced: alreadyIntroduced,
            count: count, on: now, calendar: calendar
        )
        return cards.map { card in
            let record = CardRecord(
                lexemeId: card.lexemeId, type: card.type,
                availability: card.availability, scheduler: card.scheduler
            )
            context.insert(record)
            return record
        }
    }

    private func rollingAverageSeconds() -> Double {
        let cutoff = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recent = (try? context.fetch(
            FetchDescriptor<ReviewLogEntry>(
                predicate: #Predicate { $0.reviewedAt > cutoff }
            )
        )) ?? []
        return NewCardThrottle.rollingAverageSeconds(recent.map(\.elapsedSeconds))
    }

    // MARK: - Answering

    var currentRecord: CardRecord? {
        position < queue.count ? queue[position] : nil
    }

    var currentLexeme: Lexeme? {
        currentRecord.flatMap { lexeme($0.lexemeId) }
    }

    func grade(_ given: String) -> GradeResult? {
        guard let record = currentRecord, let lexeme = currentLexeme else { return nil }
        let expected = lexeme.expectedAnswers(for: record.type)
        return record.type == .nounRecognition
            ? grader.gradeEnglish(given: given, expected: expected)
            : grader.gradeGerman(given: given, expected: expected)
    }

    func intervalPreviews() -> [Rating: Double] {
        guard let record = currentRecord else { return [:] }
        return fsrs.preview(record.scheduler)
    }

    /// Commit a rating and advance. Returns true when the session is over.
    @discardableResult
    func commit(
        rating: Rating, result: GradeResult, elapsed: TimeInterval, now: Date = Date()
    ) -> Bool {
        guard let record = currentRecord, let lexeme = currentLexeme else { return true }

        var next = fsrs.review(record.scheduler, rating: rating, now: now)
        next = WeekdayShift.apply(to: next, calendar: calendar)
        record.apply(next)

        context.insert(ReviewLogEntry(
            lexemeId: record.lexemeId, type: record.type, reviewedAt: now,
            rating: rating, wasCorrect: result.isCorrect,
            given: result.given, elapsedSeconds: elapsed
        ))

        if result.isCorrect {
            markCorrectedIfPreviouslyMissed(record.lexemeId)
        } else {
            recordMiss(record: record, lexeme: lexeme, given: result.given, now: now)
            // The card comes back this session, three positions on. The
            // separation rule does not apply — this is the same card
            // returning, not a sibling leaking its answer.
            queue.insert(record, at: min(position + QueueBuilder.reinsertionOffset, queue.count))
        }

        position += 1
        try? context.save()
        return position >= queue.count
    }

    private func recordMiss(record: CardRecord, lexeme: Lexeme, given: String, now: Date) {
        let expected = lexeme.expectedAnswers(for: record.type).first ?? lexeme.lemma
        misses.append(Miss(
            lexemeId: lexeme.id,
            prompt: lexeme.prompt(for: record.type),
            article: lexeme.gender,
            word: expected,
            given: given.isEmpty ? "nothing" : given
        ))
        context.insert(ErrorLogEntry(
            lexemeId: lexeme.id, occurredAt: now,
            prompt: lexeme.prompt(for: record.type),
            correctAnswer: expected, given: given, article: lexeme.gender
        ))
    }

    private func markCorrectedIfPreviouslyMissed(_ lexemeId: Int) {
        if let index = misses.firstIndex(where: { $0.lexemeId == lexemeId }) {
            misses[index].correctedLater = true
        }
    }

    /// Unique words missed, in the order they were first missed.
    var uniqueMisses: [Miss] {
        var seen = Set<Int>()
        return misses.filter { seen.insert($0.lexemeId).inserted }
    }

    var cardsSeen: Int { position }
}
