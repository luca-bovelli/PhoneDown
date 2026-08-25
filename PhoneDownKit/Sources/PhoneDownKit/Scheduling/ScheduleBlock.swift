import Foundation

/// A trigger time drawn for a block, plus what became of it.
public struct ScheduledTrigger: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let blockID: UUID
    public let fireAt: Date
    public var outcome: TriggerOutcome?

    public init(id: UUID = UUID(), blockID: UUID, fireAt: Date, outcome: TriggerOutcome? = nil) {
        self.id = id
        self.blockID = blockID
        self.fireAt = fireAt
        self.outcome = outcome
    }

    public var isPending: Bool { outcome == nil }
}

/// What happened to a trigger when its time came.
///
/// A skip is a terminal state. The spec is explicit that a trigger landing on a
/// locked phone is *recorded and dropped*, never deferred or re-queued — a
/// deferred trigger would drift the draw distribution toward waking hours and
/// destroy the property that makes the schedule unpredictable.
public enum TriggerOutcome: Codable, Equatable, Sendable {
    /// Fired and became an intervention.
    case fired(interventionID: UUID)
    /// The phone was not in use. Costs nothing, recorded, dropped.
    case skippedNotInUse
    /// A Hall Pass was active. Full version only.
    case suppressedByPass(passID: UUID)
    /// Nothing was listening when this trigger's time passed — the process was
    /// gone and no system-side gate fired either. Distinct from a skip: a skip
    /// is a real observation, this is a hole. Kept separate so the fired/skipped
    /// series can never be quietly inflated by our own downtime.
    case missedNoObserver
}

/// A durable, inspectable block of drawn trigger times.
///
/// Blocks are generated ahead of time and persisted whole. The list survives
/// termination and reboot because it lives in storage, not in a timer.
public struct ScheduleBlock: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let start: Date
    public let end: Date
    /// Draws per hour in force when this block was drawn. Recorded so that
    /// changing the rate later doesn't make historical blocks unreadable.
    public let rate: Double
    public let generatedAt: Date
    public var triggers: [ScheduledTrigger]

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        rate: Double,
        generatedAt: Date,
        triggers: [ScheduledTrigger] = []
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.rate = rate
        self.generatedAt = generatedAt
        self.triggers = triggers
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    public var pendingTriggers: [ScheduledTrigger] {
        triggers.filter(\.isPending)
    }
}
