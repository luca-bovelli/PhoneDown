import Foundation
import Testing
@testable import PhoneDownKit

private let base = Date(timeIntervalSince1970: 1_772_000_000)

private func event(_ kind: DeviceEventKind, at seconds: TimeInterval, uptime: TimeInterval? = nil) -> DeviceEvent {
    DeviceEvent(
        date: base.addingTimeInterval(seconds),
        uptime: uptime ?? seconds,
        kind: kind
    )
}

@Suite("Lock signal comparison")
struct SignalComparisonTests {

    @Test("Signals firing close together are one episode")
    func signalsGroupIntoEpisodes() {
        let events = [
            event(.screenOff, at: 100),
            event(.deviceLocked, at: 100.3),
            event(.protectedDataUnavailable, at: 110),
        ]
        let episodes = SignalComparison.lockEpisodes(in: events)

        #expect(episodes.count == 1)
        #expect(episodes[0].signalCount == 3)
        #expect(episodes[0].protectedDataLag == 10)
    }

    @Test("Signals far apart are separate episodes")
    func distantSignalsSplit() {
        let events = [
            event(.screenOff, at: 100),
            event(.protectedDataUnavailable, at: 105),
            event(.screenOff, at: 900),
            event(.protectedDataUnavailable, at: 903),
        ]
        let episodes = SignalComparison.lockEpisodes(in: events)

        #expect(episodes.count == 2)
        #expect(episodes[0].protectedDataLag == 5)
        #expect(episodes[1].protectedDataLag == 3)
    }

    /// A second screen-off means the phone locked again, not that the first
    /// lock got a second opinion. Without this the two would merge and the lag
    /// would be computed across unrelated events.
    @Test("A repeated signal starts a new episode even inside the tolerance")
    func repeatedSignalSplitsEpisode() {
        let events = [
            event(.screenOff, at: 100),
            event(.screenOff, at: 110),
        ]
        let episodes = SignalComparison.lockEpisodes(in: events)
        #expect(episodes.count == 2)
    }

    @Test("An episode seen by only one signal reports no lag")
    func partialEpisodeHasNoLag() {
        let events = [event(.screenOff, at: 100)]
        let episodes = SignalComparison.lockEpisodes(in: events)

        #expect(episodes.count == 1)
        #expect(episodes[0].signalCount == 1)
        #expect(episodes[0].protectedDataLag == nil)
    }

    @Test("Unlock events are not treated as locks")
    func unlocksAreExcluded() {
        let events = [
            event(.screenOff, at: 100),
            event(.screenOn, at: 200),
            event(.protectedDataAvailable, at: 201),
        ]
        let episodes = SignalComparison.lockEpisodes(in: events)
        #expect(episodes.count == 1)
    }

    /// The spread is the decisive number: a constant offset can be subtracted,
    /// a variable one cannot.
    @Test("Lag summary reports spread, not just the mean")
    func lagSummary() {
        let events = [
            event(.screenOff, at: 100), event(.protectedDataUnavailable, at: 110),
            event(.screenOff, at: 500), event(.protectedDataUnavailable, at: 502),
            event(.screenOff, at: 900), event(.protectedDataUnavailable, at: 918),
        ]
        let summary = SignalComparison.protectedDataLagSummary(of: SignalComparison.lockEpisodes(in: events))

        #expect(summary != nil)
        #expect(summary!.samples == 3)
        #expect(abs(summary!.mean - 10) < 0.001)
        #expect(summary!.min == 2)
        #expect(summary!.max == 18)
    }

    @Test("No paired episodes yields no summary rather than a zero")
    func emptySummaryIsNil() {
        let events = [event(.screenOff, at: 100)]
        let summary = SignalComparison.protectedDataLagSummary(of: SignalComparison.lockEpisodes(in: events))
        #expect(summary == nil)
    }
}

@Suite("Observation gaps")
struct ObservationGapTests {

    @Test("A long silence between heartbeats is a gap")
    func gapDetected() {
        let events = [
            event(.heartbeat, at: 0),
            event(.heartbeat, at: 60),
            event(.heartbeat, at: 4000),   // the app was gone
        ]
        let gaps = SignalComparison.gaps(in: events, heartbeatInterval: 60)

        #expect(gaps.count == 1)
        #expect(gaps[0].duration == 3940)
        #expect(gaps[0].spannedReboot == false)
    }

    @Test("Regular heartbeats produce no gaps")
    func noGapsWhenAlive() {
        let events = (0..<20).map { event(.heartbeat, at: Double($0) * 60) }
        #expect(SignalComparison.gaps(in: events, heartbeatInterval: 60).isEmpty)
    }

    /// Uptime running backwards is the one unambiguous fingerprint of a reboot,
    /// and a reboot explains a gap that a jetsam kill does not.
    @Test("Uptime running backwards marks the gap as a reboot")
    func rebootDetected() {
        let events = [
            event(.heartbeat, at: 0, uptime: 90_000),
            event(.appLaunched, at: 4000, uptime: 12),
        ]
        let gaps = SignalComparison.gaps(in: events, heartbeatInterval: 60)

        #expect(gaps.count == 1)
        #expect(gaps[0].spannedReboot)
    }
}

@Suite("Event log")
struct EventLogTests {

    private func temporaryLog() -> EventLog {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonedown-tests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).jsonl")
        return EventLog(url: url)
    }

    @Test("Appended events read back in order")
    func appendAndRead() {
        let log = temporaryLog()
        log.append(.appLaunched)
        log.append(.screenOff, detail: "displayStatus=0")
        log.append(.screenOn)

        let events = log.allEvents()
        #expect(events.count == 3)
        #expect(events.map(\.kind) == [.appLaunched, .screenOff, .screenOn])
        #expect(events[1].detail == "displayStatus=0")
    }

    /// The process being observed can be killed mid-write. A torn final line
    /// must cost that one event, not the whole history.
    @Test("A torn final line does not destroy the log")
    func tornLineIsSkipped() throws {
        let log = temporaryLog()
        log.append(.appLaunched)
        log.append(.heartbeat)

        let handle = try FileHandle(forWritingTo: log.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"kind":"screenOf"#.utf8))
        try handle.close()

        #expect(log.allEvents().count == 2)
    }

    @Test("Export produces decodable JSON of every event")
    func exportRoundTrips() throws {
        let log = temporaryLog()
        log.append(.appLaunched)
        log.append(.screenOff)

        let data = try log.exportJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([DeviceEvent].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded.map(\.kind) == [.appLaunched, .screenOff])
    }

    @Test("Clearing empties the log without breaking further appends")
    func clearWorks() {
        let log = temporaryLog()
        log.append(.appLaunched)
        log.clear()
        #expect(log.allEvents().isEmpty)

        log.append(.heartbeat)
        #expect(log.allEvents().count == 1)
    }
}
