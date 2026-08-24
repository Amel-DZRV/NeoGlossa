import Foundation
import SwiftData

/// Writes a plain-JSON snapshot of all scheduler state after every session.
///
/// This exists for one failure mode: a SwiftData schema change that goes
/// wrong resets the store, and months of review history are gone with no way
/// to recover it. Everything else in this app is fixable after the fact;
/// that is not. The snapshot is written to Documents, so it survives a
/// reinstall via the Files app and can be read back by hand.
enum Backup {

    struct Snapshot: Codable {
        struct Entry: Codable {
            let lexemeId: Int
            let type: String
            let availability: String
            let stability: Double
            let difficulty: Double
            let due: Date
            let lastReview: Date?
            let reps: Int
            let lapses: Int
            let state: String
        }
        let writtenAt: Date
        let cards: [Entry]
    }

    static var url: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("neoglossa-backup.json")
    }

    static func write(context: ModelContext) {
        let records = (try? context.fetch(FetchDescriptor<CardRecord>())) ?? []
        let snapshot = Snapshot(
            writtenAt: Date(),
            cards: records.map {
                Snapshot.Entry(
                    lexemeId: $0.lexemeId, type: $0.typeRaw, availability: $0.availabilityRaw,
                    stability: $0.stability, difficulty: $0.difficulty, due: $0.due,
                    lastReview: $0.lastReview, reps: $0.reps, lapses: $0.lapses,
                    state: $0.stateRaw
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // A failed backup must never take the session down with it.
        try? encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    /// Restore from the snapshot, for use after a store reset.
    static func restore(into context: ModelContext) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: Data(contentsOf: url))

        let existing = (try? context.fetch(FetchDescriptor<CardRecord>())) ?? []
        var byKey: [String: CardRecord] = [:]
        for record in existing { byKey["\(record.lexemeId)-\(record.typeRaw)"] = record }

        var restored = 0
        for entry in snapshot.cards {
            guard let record = byKey["\(entry.lexemeId)-\(entry.type)"] else { continue }
            record.stability = entry.stability
            record.difficulty = entry.difficulty
            record.due = entry.due
            record.lastReview = entry.lastReview
            record.reps = entry.reps
            record.lapses = entry.lapses
            record.stateRaw = entry.state
            record.availabilityRaw = entry.availability
            restored += 1
        }
        try context.save()
        return restored
    }
}
