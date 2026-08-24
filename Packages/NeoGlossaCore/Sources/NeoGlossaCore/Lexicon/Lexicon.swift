import Foundation
import SQLite3

/// One entry from the bundled lexicon, resolved for display.
public struct Lexeme: Identifiable, Sendable, Equatable {
    public let id: Int
    /// `der Termin`, `fahren`, `wegen`
    public let lemma: String
    /// The headword without its article: `Termin`
    public let word: String
    public let pos: String
    public let cefr: String
    public let glosses: [String]
    public let exampleDE: String
    public let exampleEN: String

    // noun_data
    public let gender: String?
    public let plural: String?
    public let pluralOnly: Bool

    // verb_data
    public let partizipII: String?
    public let auxiliary: String?
    public let isIrregular: Bool

    // prep_data
    public let governedCase: String?

    /// The answer a card of this type expects. Multiple entries mean any of
    /// them is accepted.
    public func expectedAnswers(for type: CardType) -> [String] {
        switch type {
        case .nounProduction:
            [lemma]
        case .nounRecognition:
            glosses
        case .nounPlural:
            plural.map { ["die \($0)"] } ?? []
        case .verbPartizip:
            if let auxiliary, let partizipII {
                [auxiliary == "haben" ? "hat \(partizipII)" : "ist \(partizipII)"]
            } else { [] }
        case .prepCase:
            governedCase.map { [$0, "+ \($0)"] } ?? []
        }
    }

    /// What the front of the card shows.
    public func prompt(for type: CardType) -> String {
        switch type {
        case .nounProduction: glosses.first ?? word
        case .nounRecognition, .nounPlural: lemma
        case .verbPartizip: glosses.first ?? lemma
        case .prepCase: lemma
        }
    }
}

/// Read-only reader over the bundled `lexicon.sqlite`.
///
/// The lexicon never changes, so it is not loaded into SwiftData — it is
/// opened read-only straight from the app bundle.
public final class Lexicon: @unchecked Sendable {

    public enum Failure: Error {
        case cannotOpen(String)
        case queryFailed(String)
    }

    private var db: OpaquePointer?
    private let lock = NSLock()

    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, handle != nil else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw Failure.cannotOpen(message)
        }
        db = handle
    }

    deinit { sqlite3_close(db) }

    private static let selectClause = """
        SELECT l.id, l.lemma, l.word, l.pos, l.cefr, l.glosses, l.exampleDE, l.exampleEN,
               n.gender, n.plural, n.pluralOnly,
               v.partizipII, v.auxiliary, v.isIrregular,
               p.governedCase
        FROM lexeme l
        LEFT JOIN noun_data n ON n.lexemeId = l.id
        LEFT JOIN verb_data v ON v.lexemeId = l.id
        LEFT JOIN prep_data p ON p.lexemeId = l.id
        """

    /// Every lexeme that can produce at least one card, ordered A1 before A2.
    ///
    /// The level order is a hard gate, not a setting: A1 finishes entirely
    /// before any A2 word is introduced.
    public func allCardBearing() throws -> [Lexeme] {
        try query(
            Self.selectClause + """
            \nWHERE l.pos = 'noun'
               OR (l.pos = 'verb' AND v.isIrregular = 1)
               OR l.pos = 'preposition'
            ORDER BY CASE l.cefr WHEN 'A1' THEN 0 ELSE 1 END, l.id
            """
        )
    }

    public func lexeme(id: Int) throws -> Lexeme? {
        try query(Self.selectClause + "\nWHERE l.id = \(id)").first
    }

    private func query(_ sql: String) throws -> [Lexeme] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var results: [Lexeme] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(row(statement))
        }
        return results
    }

    private func row(_ statement: OpaquePointer?) -> Lexeme {
        func text(_ column: Int32) -> String? {
            guard let raw = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: raw)
        }
        func int(_ column: Int32) -> Int {
            Int(sqlite3_column_int64(statement, column))
        }

        let glossJSON = text(5) ?? "[]"
        let glosses = (try? JSONDecoder().decode([String].self, from: Data(glossJSON.utf8))) ?? []

        return Lexeme(
            id: int(0),
            lemma: text(1) ?? "",
            word: text(2) ?? "",
            pos: text(3) ?? "",
            cefr: text(4) ?? "",
            glosses: glosses,
            exampleDE: text(6) ?? "",
            exampleEN: text(7) ?? "",
            gender: text(8),
            plural: text(9),
            pluralOnly: int(10) == 1,
            partizipII: text(11),
            auxiliary: text(12),
            isIrregular: int(13) == 1,
            governedCase: text(14)
        )
    }
}
