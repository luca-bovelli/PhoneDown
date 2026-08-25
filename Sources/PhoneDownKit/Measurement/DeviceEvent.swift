import Foundation

/// Everything the spike is trying to observe.
///
/// The point of this build is to find out which lock signals fire, when, and
/// whether they agree. So every candidate signal is recorded separately and
/// none of them are collapsed into a single "locked" concept — collapsing them
/// is the conclusion, not the starting position.
public enum DeviceEventKind: String, Codable, Sendable, CaseIterable {
    // Process lifecycle. These are what reveal a death and the gap it left.
    case appLaunched
    case appRelaunchedByLocation
    case appBecameActive
    case appResignedActive
    case appEnteredBackground
    case appWillTerminate

    // Keep-alive health.
    case keepAliveStarted
    case keepAliveFailed
    case keepAliveInterrupted
    case keepAliveResumed

    /// Darwin `com.apple.iokit.hid.displayStatus`. Screen backlight on/off.
    /// The closest thing to "the phone stopped being used".
    case screenOff
    case screenOn

    /// Darwin `com.apple.springboard.lockstate`. Lock state proper, which is
    /// not the same event as the backlight going out.
    case deviceLocked
    case deviceUnlocked

    /// Public API. Fires when iOS evicts the data-protection keys. The only
    /// candidate here that is not a private notify key, and therefore the one
    /// we would prefer to ship if its timing holds up.
    case protectedDataUnavailable
    case protectedDataAvailable

    // Resurrection.
    case regionMonitoringStarted
    case regionMonitoringFailed
    case regionBoundaryCrossed

    /// Periodic proof-of-life. Gaps between heartbeats are how a silent death
    /// becomes visible after the fact.
    case heartbeat
}

/// One observation, timestamped twice.
///
/// `date` is wall clock and is what a human reads. `uptime` is monotonic and is
/// what the deltas are computed from — comparing two signals that fired 200ms
/// apart is meaningless if the wall clock moved between them.
public struct DeviceEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let uptime: TimeInterval
    public let kind: DeviceEventKind
    public let detail: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        uptime: TimeInterval,
        kind: DeviceEventKind,
        detail: String? = nil
    ) {
        self.id = id
        self.date = date
        self.uptime = uptime
        self.kind = kind
        self.detail = detail
    }
}

public extension DeviceEvent {
    /// Signals that mean "the phone stopped being used", by whichever route.
    static let lockLike: Set<DeviceEventKind> = [.screenOff, .deviceLocked, .protectedDataUnavailable]
    /// Signals that mean "the phone came back".
    static let unlockLike: Set<DeviceEventKind> = [.screenOn, .deviceUnlocked, .protectedDataAvailable]
}
