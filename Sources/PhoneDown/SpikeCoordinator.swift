import Foundation
import UIKit
import PhoneDownKit

/// Wires the spike together and owns its lifetime.
///
/// This build is an instrument, not the app. It holds the process open, records
/// every lock signal it can see, and writes an exportable log. Nothing here
/// schedules a trigger or measures a latency — those come after the log says
/// this foundation actually holds.
@MainActor
final class SpikeCoordinator: ObservableObject {

    /// Proof-of-life interval. Gaps longer than a couple of these are how a
    /// silent death becomes visible after the fact, so it has to be frequent
    /// enough to bound the gap usefully and rare enough to cost nothing.
    static let heartbeatInterval: TimeInterval = 60

    let log: EventLog

    private let keepAlive: KeepAliveSession
    private let lockSignals: LockSignalMonitor
    private let resurrection: ResurrectionMonitor
    private var heartbeat: Timer?

    @Published private(set) var events: [DeviceEvent] = []

    init() {
        let url = URL.documentsDirectory.appendingPathComponent("events.jsonl")
        let log = EventLog(url: url)
        self.log = log
        self.keepAlive = KeepAliveSession(log: log)
        self.lockSignals = LockSignalMonitor(log: log)
        self.resurrection = ResurrectionMonitor(log: log)
    }

    func start(relaunchedByLocation: Bool) {
        log.append(
            relaunchedByLocation ? .appRelaunchedByLocation : .appLaunched,
            detail: "uptime=\(Int(ProcessInfo.processInfo.systemUptime))s"
        )

        keepAlive.start()
        lockSignals.start()
        resurrection.start()
        observeLifecycle()
        startHeartbeat()
        refresh()
    }

    func refresh() {
        events = log.allEvents().reversed()
    }

    func clear() {
        log.clear()
        log.append(.appLaunched, detail: "log cleared")
        refresh()
    }

    // MARK: - Findings

    /// The headline the spike exists to produce.
    var lagSummary: (samples: Int, mean: TimeInterval, min: TimeInterval, max: TimeInterval)? {
        SignalComparison.protectedDataLagSummary(
            of: SignalComparison.lockEpisodes(in: log.allEvents())
        )
    }

    var gaps: [ObservationGap] {
        SignalComparison.gaps(in: log.allEvents(), heartbeatInterval: Self.heartbeatInterval)
    }

    var episodeCount: Int {
        SignalComparison.lockEpisodes(in: log.allEvents()).count
    }

    // MARK: - Lifecycle

    private func startHeartbeat() {
        heartbeat?.invalidate()
        let timer = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { [log] _ in
            log.append(.heartbeat)
        }
        // Common mode so the heartbeat keeps ticking while a scroll view is
        // tracking; a gap caused by our own run loop would read as a death.
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        let events: [(Notification.Name, DeviceEventKind)] = [
            (UIApplication.didBecomeActiveNotification, .appBecameActive),
            (UIApplication.willResignActiveNotification, .appResignedActive),
            (UIApplication.didEnterBackgroundNotification, .appEnteredBackground),
            (UIApplication.willTerminateNotification, .appWillTerminate),
        ]

        for (name, kind) in events {
            center.addObserver(forName: name, object: nil, queue: nil) { [log] _ in
                log.append(kind)
            }
        }
    }
}
