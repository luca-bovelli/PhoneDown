import Foundation
import Testing
@testable import PhoneDownKit

private let t0 = Date(timeIntervalSince1970: 1_772_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

@Suite("Intervention accumulation")
struct InterventionTests {

    @Test("A clean single-segment intervention reports its latency")
    func singleSegment() {
        var intervention = Intervention(cooldown: 300)
        intervention.beginSegment(at: at(0))
        intervention.closeSegment(at: at(23), precision: .exact)
        intervention.resolve(at: at(323), as: .cooldownCompleted)

        #expect(intervention.accumulatedLatency == 23)
        #expect(intervention.wallClockSpan == 323)
        #expect(intervention.relapseCount == 0)
        #expect(intervention.isExactlyMeasured)
    }

    /// The headline number charges the user for time spent *on* the phone, not
    /// for the minutes they successfully stayed off it before relapsing. A
    /// wall-clock reading would punish a partial success more than a total
    /// refusal, which is backwards.
    @Test("Relapses accumulate active time and exclude the locked gaps")
    func relapsesAccumulate() {
        var intervention = Intervention(cooldown: 300)
        intervention.beginSegment(at: at(0))
        intervention.closeSegment(at: at(30), precision: .exact)     // 30s on the phone
        intervention.beginSegment(at: at(200))                       // unlocked at 200, re-interrupted
        intervention.closeSegment(at: at(245), precision: .exact)    // 45s on the phone
        intervention.beginSegment(at: at(400))
        intervention.closeSegment(at: at(410), precision: .exact)    // 10s on the phone
        intervention.resolve(at: at(710), as: .cooldownCompleted)

        #expect(intervention.accumulatedLatency == 85)
        #expect(intervention.wallClockSpan == 710)
        #expect(intervention.relapseCount == 2)
        #expect(intervention.segments.count == 3)
    }

    @Test("An open segment withholds the latency rather than reporting a partial total")
    func openSegmentHasNoLatency() {
        var intervention = Intervention(cooldown: 300)
        intervention.beginSegment(at: at(0))
        intervention.closeSegment(at: at(30), precision: .exact)
        intervention.beginSegment(at: at(200))

        #expect(intervention.accumulatedLatency == nil)
        #expect(intervention.openSegment != nil)
        #expect(intervention.wallClockSpan == nil)
    }

    /// One softly-measured leg makes the sum soft. The record still exists and
    /// still counts as an interrupt — it is only barred from the latency series.
    @Test("A bracketed leg disqualifies the whole record from the latency series")
    func bracketedLegPoisonsExactness() {
        var intervention = Intervention(cooldown: 300)
        intervention.beginSegment(at: at(0))
        intervention.closeSegment(at: at(30), precision: .exact)
        intervention.beginSegment(at: at(200))
        intervention.closeSegment(at: at(500), precision: .bracketed(earliest: at(400), latest: at(600)))
        intervention.resolve(at: at(800), as: .cooldownCompleted)

        #expect(intervention.isExactlyMeasured == false)
        #expect(intervention.accumulatedLatency == 330)  // still computable, just not trustworthy
        #expect(intervention.relapseCount == 1)
    }

    @Test("An unobserved interrupt is never exactly measured")
    func unobservedIsNotExact() {
        var intervention = Intervention(cooldown: 300)
        intervention.beginSegment(at: at(0))
        intervention.closeSegment(at: at(60), precision: .unobserved)
        intervention.resolve(at: at(360), as: .cooldownCompleted)

        #expect(intervention.isExactlyMeasured == false)
    }

    @Test("Closing with nothing open is refused rather than silently accepted")
    func closingWithoutOpenSegmentFails() {
        var intervention = Intervention(cooldown: 300)
        #expect(intervention.closeSegment(at: at(10), precision: .exact) == false)

        intervention.beginSegment(at: at(0))
        #expect(intervention.closeSegment(at: at(10), precision: .exact) == true)
        #expect(intervention.closeSegment(at: at(20), precision: .exact) == false)
    }

    @Test("An abandoned intervention keeps its segments")
    func abandonedKeepsData() {
        var intervention = Intervention(cooldown: 300)
        intervention.beginSegment(at: at(0))
        intervention.closeSegment(at: at(45), precision: .exact)
        intervention.resolve(at: at(86_400), as: .abandoned)

        #expect(intervention.resolution == .abandoned)
        #expect(intervention.segments.count == 1)
        #expect(intervention.accumulatedLatency == 45)
    }

    @Test("Cooldown is captured per intervention so later settings changes don't rewrite history")
    func cooldownIsSnapshotted() {
        let intervention = Intervention(cooldown: 300)
        #expect(intervention.cooldown == 300)
        let debugIntervention = Intervention(origin: .debugImmediate, cooldown: 5)
        #expect(debugIntervention.cooldown == 5)
        #expect(debugIntervention.origin == .debugImmediate)
    }

    @Test("Round-trips through Codable intact")
    func codableRoundTrip() throws {
        var intervention = Intervention(cooldown: 300)
        intervention.beginSegment(at: at(0))
        intervention.closeSegment(at: at(30), precision: .exact)
        intervention.beginSegment(at: at(200))
        intervention.closeSegment(at: at(260), precision: .bracketed(earliest: at(240), latest: at(300)))
        intervention.resolve(at: at(560), as: .cooldownCompleted)

        let data = try JSONEncoder().encode(intervention)
        let decoded = try JSONDecoder().decode(Intervention.self, from: data)
        #expect(decoded == intervention)
    }
}
