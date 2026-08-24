import Foundation
import Testing
@testable import NeoGlossaCore

@Suite("Grading is strict")
struct GraderTests {

    let grader = Grader()

    @Test("The article is required and capitalisation is enforced")
    func articleAndCapitalisation() {
        let expected = ["der Termin"]
        #expect(grader.gradeGerman(given: "der Termin", expected: expected).isCorrect)
        // German nouns are always capitalised; drilling this is the point.
        #expect(grader.gradeGerman(given: "der termin", expected: expected).isCorrect == false)
        // The article carries the gender, which is the thing being taught.
        #expect(grader.gradeGerman(given: "Termin", expected: expected).isCorrect == false)
        #expect(grader.gradeGerman(given: "termin", expected: expected).isCorrect == false)
        #expect(grader.gradeGerman(given: "die Termin", expected: expected).isCorrect == false)
    }

    @Test("Umlauts are not interchangeable with their ae/oe/ue spellings")
    func umlautsAreStrict() {
        let expected = ["die Bücher"]
        #expect(grader.gradeGerman(given: "die Bücher", expected: expected).isCorrect)
        #expect(grader.gradeGerman(given: "die Bucher", expected: expected).isCorrect == false)
        #expect(grader.gradeGerman(given: "die Buecher", expected: expected).isCorrect == false)
    }

    @Test("Whitespace and trailing punctuation are forgiven, nothing else is")
    func normalisation() {
        let expected = ["der Termin"]
        #expect(grader.gradeGerman(given: "  der Termin  ", expected: expected).isCorrect)
        #expect(grader.gradeGerman(given: "der    Termin", expected: expected).isCorrect)
        #expect(grader.gradeGerman(given: "der Termin.", expected: expected).isCorrect)
        #expect(grader.gradeGerman(given: "der Termin!", expected: expected).isCorrect)
    }

    @Test("Any stored gloss is accepted, case-insensitively")
    func recognitionAcceptsAnyGloss() {
        let expected = ["bank", "bench"]
        #expect(grader.gradeEnglish(given: "bank", expected: expected).isCorrect)
        #expect(grader.gradeEnglish(given: "Bench", expected: expected).isCorrect)
        #expect(grader.gradeEnglish(given: "BANK", expected: expected).isCorrect)
        #expect(grader.gradeEnglish(given: "shelf", expected: expected).isCorrect == false)
    }

    @Test("A verb gloss grades with or without its infinitive marker")
    func infinitiveMarkerOptional() {
        // The sources are inconsistent: "to take off" alongside "move out".
        #expect(grader.gradeEnglish(given: "take off", expected: ["to take off"]).isCorrect)
        #expect(grader.gradeEnglish(given: "to move out", expected: ["move out"]).isCorrect)
    }

    @Test("The auxiliary is required on a participle card")
    func auxiliaryRequired() {
        let expected = ["ist gefahren"]
        #expect(grader.gradeGerman(given: "ist gefahren", expected: expected).isCorrect)
        // `gefahren` alone is useless — ist against hat is what gets missed.
        #expect(grader.gradeGerman(given: "gefahren", expected: expected).isCorrect == false)
        #expect(grader.gradeGerman(given: "hat gefahren", expected: expected).isCorrect == false)
    }

    @Test("A wrong answer offers no rating buttons; a right one never offers Again")
    func ratingButtonsFollowCorrectness() {
        let wrong = grader.gradeGerman(given: "Termin", expected: ["der Termin"])
        #expect(wrong.offeredRatings.isEmpty)
        #expect(wrong.automaticRating == .again)

        let right = grader.gradeGerman(given: "der Termin", expected: ["der Termin"])
        #expect(right.offeredRatings == [.hard, .good, .easy])
        #expect(right.offeredRatings.contains(.again) == false)
        #expect(right.automaticRating == nil)
    }
}
