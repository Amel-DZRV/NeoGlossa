import Foundation
import Testing
@testable import NeoGlossaCore

@Suite("Adaptive new-card throttle")
struct ThrottleTests {

    let throttle = NewCardThrottle(targetMinutes: 45)

    @Test("A heavy review day yields no new cards at all")
    func heavyDayYieldsNothing() {
        // 300 reviews at 12s each is 60 minutes — already over target.
        let count = throttle.newCardCount(
            dueReviewCount: 300, averageSecondsPerCard: 12, weeksSinceStart: 0
        )
        #expect(count == 0)
    }

    @Test("An empty day is still capped by the ramp, not by the clock")
    func emptyDayRespectsRamp() {
        // 45 minutes of nothing would afford 108 new cards; the ramp says 15.
        let count = throttle.newCardCount(
            dueReviewCount: 0, averageSecondsPerCard: 12, weeksSinceStart: 0
        )
        #expect(count == 15)
    }

    @Test("The ramp tightens as review load accumulates")
    func rampSchedule() {
        #expect(NewCardThrottle.dailyCap(weeksSinceStart: 0) == 15)
        #expect(NewCardThrottle.dailyCap(weeksSinceStart: 1) == 15)
        #expect(NewCardThrottle.dailyCap(weeksSinceStart: 2) == 10)
        #expect(NewCardThrottle.dailyCap(weeksSinceStart: 3) == 10)
        #expect(NewCardThrottle.dailyCap(weeksSinceStart: 4) == 8)
        #expect(NewCardThrottle.dailyCap(weeksSinceStart: 52) == 8)
    }

    @Test("New cards taper as reviews eat the budget")
    func taperingUnderLoad() {
        let light = throttle.newCardCount(
            dueReviewCount: 50, averageSecondsPerCard: 12, weeksSinceStart: 5
        )
        let heavy = throttle.newCardCount(
            dueReviewCount: 180, averageSecondsPerCard: 12, weeksSinceStart: 5
        )
        #expect(light == 8)       // capped by the ramp
        #expect(heavy < light)    // squeezed by the clock
        #expect(heavy > 0)
    }

    @Test("A slower user gets fewer new cards for the same review count")
    func slowerUserGetsFewer() {
        let quick = throttle.newCardCount(
            dueReviewCount: 150, averageSecondsPerCard: 8, weeksSinceStart: 5
        )
        let slow = throttle.newCardCount(
            dueReviewCount: 150, averageSecondsPerCard: 16, weeksSinceStart: 5
        )
        #expect(slow < quick)
    }

    @Test("The rolling average falls back before there is data")
    func rollingAverageFallback() {
        #expect(NewCardThrottle.rollingAverageSeconds([]) == NewCardThrottle.assumedReviewSeconds)
        #expect(NewCardThrottle.rollingAverageSeconds([10, 20, 30]) == 20)
    }
}
