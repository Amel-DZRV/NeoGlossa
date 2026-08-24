import SwiftUI
import NeoGlossaCore

struct ReviewView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let store: StudyStore
    let onFinished: () -> Void

    @State private var typed = ""
    @State private var flipped = false
    @State private var degrees: Double = 0
    @State private var cardOpacity: Double = 1
    @State private var result: GradeResult?
    @State private var shownAt = Date()
    @FocusState private var inputFocused: Bool

    /// 560ms, fast off the mark with a long settle, so the flip reads as mass
    /// rather than a wipe.
    private var flipAnimation: Animation {
        .timingCurve(0.22, 0.68, 0.16, 1, duration: 0.56)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: Theme.Space.m)
            card
            Spacer(minLength: Theme.Space.m)
            footer
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.safeTop)
        .padding(.bottom, Theme.Space.safeBottom)
        .onAppear { beginCard() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ProgressRail(total: store.queue.count, current: store.position)
            Text("\(min(store.position + 1, store.queue.count)) / \(store.queue.count)")
                .labelStyle(Theme.ink3(scheme))
        }
    }

    // MARK: - Card

    @ViewBuilder private var card: some View {
        if let lexeme = store.currentLexeme, let record = store.currentRecord {
            ZStack {
                if reduceMotion {
                    // No rotation; the faces cross-fade instead.
                    (flipped ? AnyView(back(lexeme)) : AnyView(front(lexeme, record)))
                        .transition(.opacity)
                } else {
                    front(lexeme, record)
                        .opacity(degrees < 90 ? 1 : 0)
                    back(lexeme)
                        .rotation3DEffect(.degrees(180), axis: (0, 1, 0), perspective: 0.28)
                        .opacity(degrees < 90 ? 0 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : degrees), axis: (0, 1, 0), perspective: 0.28
            )
            .opacity(cardOpacity)
        }
    }

    private func front(_ lexeme: Lexeme, _ record: CardRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(kindLabel(record.type)).labelStyle(Theme.ink3(scheme))

            // The prompt is centred, deliberately against the system's rule:
            // a flashcard is read at arm's length and the eye should land in
            // the same place every time.
            VStack(spacing: Theme.Space.xs) {
                Text(lexeme.prompt(for: record.type))
                    .font(TypeScale.prompt)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink(scheme))
                Text(hint(record.type))
                    .font(TypeScale.secondary)
                    .foregroundStyle(Theme.ink3(scheme))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func back(_ lexeme: Lexeme) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let result {
                HStack(spacing: Theme.Space.xs) {
                    Text(result.isCorrect ? "✓" : "✕")
                        .foregroundStyle(result.isCorrect ? Theme.ink(scheme) : Theme.wrong(scheme))
                    Text(result.isCorrect ? "Correct" : "Incorrect")
                        .labelStyle(result.isCorrect ? Theme.ink(scheme) : Theme.wrong(scheme))
                    if !result.given.isEmpty {
                        Text("“\(result.given)”").labelStyle(Theme.ink3(scheme))
                    }
                }
            }

            VStack(spacing: 4) {
                answerLine(lexeme)
                Text(genderLabel(lexeme)).labelStyle(Theme.ink3(scheme))
            }
            .frame(maxWidth: .infinity)

            if !lexeme.exampleDE.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lexeme.exampleDE)
                        .font(TypeScale.exampleDE)
                        .foregroundStyle(Theme.ink(scheme))
                    Text(lexeme.exampleEN)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Theme.ink2(scheme))
                }
            }
        }
    }

    @ViewBuilder private func answerLine(_ lexeme: Lexeme) -> some View {
        let answer = store.currentRecord
            .flatMap { lexeme.expectedAnswers(for: $0.type).first } ?? lexeme.lemma
        let parts = answer.split(separator: " ", maxSplits: 1).map(String.init)

        HStack(spacing: 8) {
            if parts.count == 2, let gender = Gender(article: parts[0]) {
                GenderArticle(article: parts[0], gender: gender).font(TypeScale.answer)
                Text(parts[1]).font(TypeScale.answer).answerTracking()
            } else if parts.count == 2 {
                // Verbs and prepositions carry no colour, by design.
                GenderArticle(article: parts[0], gender: nil).font(TypeScale.answer)
                Text(parts[1]).font(TypeScale.answer).answerTracking()
            } else {
                Text(answer).font(TypeScale.answer).answerTracking()
            }
        }
        .foregroundStyle(Theme.ink(scheme))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        if let result {
            if result.isCorrect {
                HStack(spacing: Theme.Space.xs) {
                    ForEach([Rating.hard, .good, .easy], id: \.self) { rating in
                        RatingButton(title: title(rating), interval: intervalText(rating)) {
                            commit(rating)
                        }
                    }
                }
            } else {
                // A miss is graded Again automatically; there is nothing to rate.
                PrimaryButton(
                    title: "Again",
                    trailing: "\(QueueBuilder.reinsertionOffset) cards from now",
                    tint: Theme.accent(scheme)
                ) {
                    commit(.again)
                }
            }
        } else {
            VStack(spacing: Theme.Space.xs) {
                TextField("", text: $typed, prompt: placeholderText)
                    .font(TypeScale.exampleDE)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($inputFocused)
                    .onSubmit(submit)
                    .padding(.horizontal, 12)
                    .frame(height: Theme.Space.primaryActionHeight)
                    .overlay(Rectangle().stroke(Theme.rule(scheme), lineWidth: 1))

                PrimaryButton(
                    title: "Submit",
                    trailing: "↵",
                    isEnabled: !typed.trimmingCharacters(in: .whitespaces).isEmpty,
                    action: submit
                )
            }
        }
    }

    private var placeholderText: Text {
        let text = switch store.currentRecord?.type {
        case .nounProduction, .nounPlural: "der / die / das + word"
        case .verbPartizip: "hat / ist + participle"
        case .prepCase: "akkusativ / dativ / wechsel / genitiv"
        default: "answer"
        }
        return Text(text).foregroundStyle(Theme.ink3(scheme))
    }

    // MARK: - Flow

    private func beginCard() {
        typed = ""
        result = nil
        flipped = false
        degrees = 0
        cardOpacity = 1
        shownAt = Date()
        inputFocused = true
    }

    private func submit() {
        guard let graded = store.grade(typed) else { return }
        inputFocused = false
        result = graded
        withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : flipAnimation) {
            flipped = true
            degrees = 180
        }
    }

    private func commit(_ rating: Rating) {
        guard let graded = result else { return }
        let elapsed = Date().timeIntervalSince(shownAt)

        // Advancing does not flip back: the card fades out, the deck resets
        // to 0 degrees, and the new front fades in.
        withAnimation(.linear(duration: 0.17)) { cardOpacity = 0 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let finished = store.commit(rating: rating, result: graded, elapsed: elapsed)
            if finished {
                onFinished()
            } else {
                beginCard()
                cardOpacity = 0
                withAnimation(.linear(duration: 0.17)) { cardOpacity = 1 }
            }
        }
    }

    private func title(_ rating: Rating) -> String {
        switch rating {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    private func intervalText(_ rating: Rating) -> String {
        guard let days = store.intervalPreviews()[rating] else { return "" }
        return days < 30 ? "\(Int(days.rounded())) D" : "\(Int((days / 30).rounded())) M"
    }

    private func kindLabel(_ type: CardType) -> String {
        switch type {
        case .nounProduction, .nounRecognition: "noun"
        case .nounPlural: "noun · plural"
        case .verbPartizip: "verb · past participle"
        case .prepCase: "preposition · case"
        }
    }

    private func hint(_ type: CardType) -> String {
        switch type {
        case .nounProduction: "article + noun"
        case .nounRecognition: "what does it mean?"
        case .nounPlural: "the plural, with its article"
        case .verbPartizip: "helper + participle"
        case .prepCase: "which case does it take?"
        }
    }

    private func genderLabel(_ lexeme: Lexeme) -> String {
        if let gender = Gender(article: lexeme.gender) {
            return "\(gender.label) · \(gender.rawValue)"
        }
        return lexeme.pos
    }
}
