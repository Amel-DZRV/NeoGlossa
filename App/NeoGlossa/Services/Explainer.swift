import Foundation
import Observation
import NeoGlossaCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The on-device model, allowed nowhere near the answer key.
///
/// The model is small enough to get `der`/`die`/`das` wrong often enough to
/// matter, and that is precisely the content this app exists to teach. So the
/// boundary is structural rather than a matter of prompting: nothing here
/// returns a gender, a plural, an auxiliary or a governed case. Those are
/// passed *in* as already-correct facts from the bundled dataset, and the
/// model may only produce prose about them.
///
/// Permitted, because a mistake is cheap:
/// - explaining a case ending after the answer is already revealed
/// - extra example sentences, clearly labelled as generated
/// - clustering the error log into patterns
@Observable
@MainActor
final class Explainer {

    enum Availability { case ready, unavailable(String) }

    private(set) var isWorking = false
    private(set) var text: String?

    var availability: Availability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: .ready
        case .unavailable(let reason): .unavailable("\(reason)")
        }
        #else
        .unavailable("Foundation Models is not available on this OS.")
        #endif
    }

    var isReady: Bool { if case .ready = availability { true } else { false } }

    /// Explain a revealed answer. Every fact the model needs is supplied.
    func explain(lexeme: Lexeme, question: String) async {
        let facts = """
            German word: \(lexeme.lemma)
            Part of speech: \(lexeme.pos)
            \(lexeme.gender.map { "Gender: \($0)" } ?? "")
            \(lexeme.plural.map { "Plural: die \($0)" } ?? "")
            \(lexeme.auxiliary.map { "Auxiliary: \($0)" } ?? "")
            \(lexeme.partizipII.map { "Partizip II: \($0)" } ?? "")
            \(lexeme.governedCase.map { "Governed case: \($0)" } ?? "")
            Example: \(lexeme.exampleDE)
            """

        await run(prompt: """
            These facts are correct and must be treated as given. Do not \
            contradict them and do not state any grammatical form that is \
            not listed here.

            \(facts)

            Answer this learner's question in at most three sentences, \
            using only the facts above: \(question)
            """)
    }

    /// Extra practice sentences. The caller must label these as generated —
    /// they are not from the verified dataset.
    func extraExamples(lexeme: Lexeme) async {
        await run(prompt: """
            The German word "\(lexeme.lemma)" is correct as written, \
            including its article. Write two short A2-level German sentences \
            using it, each with an English translation underneath. Do not \
            change its article or its spelling.
            """)
    }

    /// Group the error log into patterns. No grammar is asserted, only
    /// observations about the user's own misses.
    func clusterErrors(_ misses: [String]) async {
        guard !misses.isEmpty else { return }
        await run(prompt: """
            Here are words a German learner answered incorrectly. Group them \
            into at most four patterns and name each pattern in a few words. \
            Do not state any grammatical rule and do not correct anything — \
            only describe what the mistakes have in common.

            \(misses.joined(separator: "\n"))
            """)
    }

    private func run(prompt: String) async {
        #if canImport(FoundationModels)
        guard isReady else { return }
        isWorking = true
        text = nil
        defer { isWorking = false }
        do {
            let session = LanguageModelSession()
            text = try await session.respond(to: prompt).content
        } catch {
            text = "Could not generate an explanation."
        }
        #endif
    }

    func clear() { text = nil }
}
