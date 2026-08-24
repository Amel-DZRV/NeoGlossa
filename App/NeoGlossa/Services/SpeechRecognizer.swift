import AVFoundation
import Foundation
import Observation
import Speech

/// On-device German dictation for answering a card by voice.
///
/// The whole design turns on one distinction: a transcript with **no**
/// article means the microphone did not hear it, and a transcript with the
/// **wrong** article means the user did not know it. Conflating the two is
/// what makes speech input feel broken, and it gets blamed on the recogniser.
@Observable
@MainActor
final class SpeechRecognizer {

    enum Outcome: Equatable {
        /// Grade this text as if it had been typed.
        case transcript(String)
        /// An article was expected and none was heard. Do not fail the card —
        /// offer der/die/das and grade the tap instead.
        case articleMissing(heard: String)
        case unavailable(String)
    }

    enum State: Equatable { case idle, listening, finished }

    private(set) var state: State = .idle
    private(set) var partial: String = ""
    private(set) var outcome: Outcome?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    static let articles = ["der", "die", "das"]

    var isAvailable: Bool {
        recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true
    }

    func requestAuthorisation() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// - Parameters:
    ///   - contextualStrings: the expected article and lemma, which bias the
    ///     decoder toward the answer being drilled.
    ///   - expectsArticle: true for noun cards, where a missing article
    ///     triggers the fallback rather than a failure.
    func start(contextualStrings: [String], expectsArticle: Bool) {
        stop()
        guard let recognizer, isAvailable else {
            outcome = .unavailable("On-device German recognition is not available.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        // No network, ever.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) {
                buffer, _ in request.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            outcome = .unavailable("Could not start the microphone.")
            return
        }

        state = .listening
        partial = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.partial = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finish(with: self.partial, expectsArticle: expectsArticle)
                    }
                } else if error != nil {
                    self.finish(with: self.partial, expectsArticle: expectsArticle)
                }
            }
        }
    }

    /// End dictation and classify what was heard.
    func stopAndGrade(expectsArticle: Bool) {
        let heard = partial
        stop()
        finish(with: heard, expectsArticle: expectsArticle)
    }

    private func finish(with text: String, expectsArticle: Bool) {
        guard state != .finished else { return }
        stop()
        state = .finished

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectsArticle else {
            outcome = .transcript(trimmed)
            return
        }

        let words = trimmed.split(separator: " ").map { $0.lowercased() }
        let carriesArticle = words.contains { Self.articles.contains($0) }

        // No article at all: the microphone missed it. A wrong article falls
        // through to normal grading, where it is a genuine miss.
        outcome = carriesArticle ? .transcript(trimmed) : .articleMissing(heard: trimmed)
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if state == .listening { state = .idle }
    }

    func reset() {
        stop()
        state = .idle
        partial = ""
        outcome = nil
    }
}
