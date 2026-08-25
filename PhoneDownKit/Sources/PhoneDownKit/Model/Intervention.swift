import Foundation

/// How precisely a segment's end was observed.
///
/// The measurement backend decides which of these it can produce. An exact
/// observation requires the app process to be alive at the moment the device
/// locked; anything else is a bound, and is kept as a bound rather than being
/// rounded into a number that looks more certain than it is.
public enum LockPrecision: Codable, Equatable, Sendable {
    /// The lock was observed directly, to the second.
    case exact
    /// The lock happened somewhere in this window and we cannot narrow it further.
    case bracketed(earliest: Date, latest: Date)
    /// The interrupt was delivered but nothing observed the lock at all.
    case unobserved

    public var isExact: Bool { self == .exact }
}

/// One notification-to-lock leg of an intervention.
///
/// An intervention has more than one of these when the user unlocked during the
/// cooldown and got interrupted again. The legs accumulate; see `Intervention`.
public struct InterventionSegment: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    /// When the instruction reached the user. The clock starts here.
    public let notifiedAt: Date
    /// When the device stopped being used. Nil while the segment is still open.
    public var lockedAt: Date?
    public var precision: LockPrecision

    public init(
        id: UUID = UUID(),
        notifiedAt: Date,
        lockedAt: Date? = nil,
        precision: LockPrecision = .unobserved
    ) {
        self.id = id
        self.notifiedAt = notifiedAt
        self.lockedAt = lockedAt
        self.precision = precision
    }

    /// Time the user stayed on the phone after being told to put it down.
    public var duration: TimeInterval? {
        lockedAt.map { $0.timeIntervalSince(notifiedAt) }
    }

    public var isOpen: Bool { lockedAt == nil }
}

public enum InterventionOrigin: String, Codable, Sendable {
    case scheduled
    case debugImmediate
    case debugDelayed
}

/// Why an intervention stopped accumulating.
public enum InterventionResolution: String, Codable, Sendable {
    /// The device stayed locked for a full uninterrupted cooldown. The normal close.
    case cooldownCompleted
    /// The user never responded and the intervention was closed by the 24h sweep.
    case abandoned
    /// Closed by the debug harness or by a data reset.
    case discarded
}

/// One "put your phone down" event and everything that followed it.
///
/// The measured quantity is **follow-through, not reaction time**: if the user
/// locks the phone and then picks it back up before the cooldown elapses, the
/// re-interrupt is another segment on the *same* intervention rather than a new
/// independent sample. Penalty time accumulates until they manage one clean
/// cooldown.
///
/// Three numbers come out of this and they answer different questions:
///   - `accumulatedLatency` — total time spent on the phone after being told not
///     to be. The headline. Excludes the locked gaps, which are time genuinely
///     spent off the phone and should not be charged to the user.
///   - `wallClockSpan` — first interrupt to final close, gaps included.
///   - `segments.count` — how many times they came back before it stuck.
public struct Intervention: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let triggerID: UUID?
    public let origin: InterventionOrigin
    /// Cooldown in force for this intervention, captured at creation so that
    /// later settings changes don't retroactively rewrite history.
    public let cooldown: TimeInterval
    public private(set) var segments: [InterventionSegment]
    public private(set) var resolvedAt: Date?
    public private(set) var resolution: InterventionResolution?

    public init(
        id: UUID = UUID(),
        triggerID: UUID? = nil,
        origin: InterventionOrigin = .scheduled,
        cooldown: TimeInterval,
        segments: [InterventionSegment] = [],
        resolvedAt: Date? = nil,
        resolution: InterventionResolution? = nil
    ) {
        self.id = id
        self.triggerID = triggerID
        self.origin = origin
        self.cooldown = cooldown
        self.segments = segments
        self.resolvedAt = resolvedAt
        self.resolution = resolution
    }

    public var startedAt: Date? { segments.first?.notifiedAt }
    public var isResolved: Bool { resolution != nil }
    public var openSegment: InterventionSegment? { segments.last.flatMap { $0.isOpen ? $0 : nil } }

    /// Sum of every notification-to-lock leg. The headline number.
    ///
    /// Nil while any segment is still open — a running total would be a
    /// different quantity from a settled one and mixing them into the same
    /// series would quietly corrupt every average built on it.
    public var accumulatedLatency: TimeInterval? {
        guard !segments.isEmpty, segments.allSatisfy({ !$0.isOpen }) else { return nil }
        return segments.compactMap(\.duration).reduce(0, +)
    }

    /// First interrupt to final close, including the time spent locked.
    public var wallClockSpan: TimeInterval? {
        guard let start = startedAt, let end = resolvedAt else { return nil }
        return end.timeIntervalSince(start)
    }

    /// How many times the user came back before the cooldown finally held.
    public var relapseCount: Int { max(0, segments.count - 1) }

    /// An intervention is only fit for the latency series if every leg was
    /// observed exactly. One bracketed leg poisons the sum, so the whole record
    /// is excluded from the headline rather than contributing a soft number.
    public var isExactlyMeasured: Bool {
        !segments.isEmpty && segments.allSatisfy { $0.precision.isExact && $0.lockedAt != nil }
    }

    // MARK: - Mutation

    public mutating func beginSegment(at date: Date) {
        segments.append(InterventionSegment(notifiedAt: date))
    }

    /// Close the open leg. Returns false if there was nothing open to close,
    /// which is a caller bug worth surfacing rather than swallowing.
    @discardableResult
    public mutating func closeSegment(at date: Date, precision: LockPrecision) -> Bool {
        guard let index = segments.indices.last, segments[index].isOpen else { return false }
        segments[index].lockedAt = date
        segments[index].precision = precision
        return true
    }

    public mutating func resolve(at date: Date, as resolution: InterventionResolution) {
        self.resolvedAt = date
        self.resolution = resolution
    }
}
