import Foundation

/// One physical lock, as reported by however many signals noticed it.
///
/// The three candidate signals fire at slightly different moments for the same
/// event. Grouping them into an episode is what makes "how far apart are they"
/// a question with an answer.
public struct LockEpisode: Equatable, Sendable {
    public let screenOff: DeviceEvent?
    public let deviceLocked: DeviceEvent?
    public let protectedDataUnavailable: DeviceEvent?

    /// Earliest signal in the episode. Whatever fired first is the closest
    /// thing we have to ground truth for when the phone actually went dark.
    public var earliest: DeviceEvent? {
        [screenOff, deviceLocked, protectedDataUnavailable]
            .compactMap { $0 }
            .min { $0.uptime < $1.uptime }
    }

    /// How far the public signal lagged the screen going dark, in seconds.
    ///
    /// This is the number the whole spike exists to produce. Small and stable
    /// means the private notify key can be deleted; large or jittery means it
    /// cannot.
    public var protectedDataLag: TimeInterval? {
        guard let screenOff, let protectedDataUnavailable else { return nil }
        return protectedDataUnavailable.uptime - screenOff.uptime
    }

    public var signalCount: Int {
        [screenOff, deviceLocked, protectedDataUnavailable].compactMap { $0 }.count
    }
}

/// A window during which nothing was recorded, so the process was probably gone.
public struct ObservationGap: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let duration: TimeInterval
    /// True when the process restarted with a lower uptime than it ended with,
    /// which only happens across a reboot.
    public let spannedReboot: Bool
}

public enum SignalComparison {

    /// Group lock-like events into episodes. Signals for the same physical lock
    /// arrive close together; `tolerance` is how close.
    public static func lockEpisodes(
        in events: [DeviceEvent],
        tolerance: TimeInterval = 30
    ) -> [LockEpisode] {
        let locks = events
            .filter { DeviceEvent.lockLike.contains($0.kind) }
            .sorted { $0.uptime < $1.uptime }

        var episodes: [LockEpisode] = []
        var current: [DeviceEvent] = []

        func flush() {
            guard !current.isEmpty else { return }
            episodes.append(LockEpisode(
                screenOff: current.first { $0.kind == .screenOff },
                deviceLocked: current.first { $0.kind == .deviceLocked },
                protectedDataUnavailable: current.first { $0.kind == .protectedDataUnavailable }
            ))
            current = []
        }

        for event in locks {
            if let last = current.last, event.uptime - last.uptime > tolerance {
                flush()
            }
            // A repeat of a signal already in this group means a new episode,
            // not a second opinion on the same one.
            if current.contains(where: { $0.kind == event.kind }) {
                flush()
            }
            current.append(event)
        }
        flush()
        return episodes
    }

    /// Mean and spread of the public signal's lag behind screen-off.
    ///
    /// The spread matters more than the mean. A constant offset can simply be
    /// subtracted; a variable one is noise on a metric measured in seconds and
    /// cannot be calibrated away.
    public static func protectedDataLagSummary(
        of episodes: [LockEpisode]
    ) -> (samples: Int, mean: TimeInterval, min: TimeInterval, max: TimeInterval)? {
        let lags = episodes.compactMap(\.protectedDataLag)
        guard !lags.isEmpty else { return nil }
        return (
            samples: lags.count,
            mean: lags.reduce(0, +) / Double(lags.count),
            min: lags.min()!,
            max: lags.max()!
        )
    }

    /// Find stretches where the process was not running.
    ///
    /// Heartbeats are the proof of life; a gap longer than a couple of
    /// intervals means the app was gone. This is how a swipe-away or a jetsam
    /// kill becomes visible after the fact.
    public static func gaps(
        in events: [DeviceEvent],
        heartbeatInterval: TimeInterval,
        slack: Double = 2.5
    ) -> [ObservationGap] {
        let sorted = events.sorted { $0.date < $1.date }
        guard sorted.count > 1 else { return [] }

        var result: [ObservationGap] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let elapsed = b.date.timeIntervalSince(a.date)
            guard elapsed > heartbeatInterval * slack else { continue }
            result.append(ObservationGap(
                start: a.date,
                end: b.date,
                duration: elapsed,
                spannedReboot: b.uptime < a.uptime
            ))
        }
        return result
    }
}
