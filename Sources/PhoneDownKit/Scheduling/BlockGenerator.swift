import Foundation

/// Draws trigger times for a block.
///
/// Times are independent uniform draws across the whole block. There is
/// deliberately no minimum gap, no jitter around an even spacing, and no
/// waking-hours window: clustering is a property of a Poisson-like process, not
/// a defect, and a draw that lands at 4am and catches real scrolling is the most
/// valuable one in the set. Draws landing on a locked phone cost nothing.
public struct BlockGenerator: Sendable {
    /// Block length. Fixed at 12h so blocks land on 00:00 and 12:00 boundaries.
    public static let blockHours: Double = 12

    public static let minimumRate: Double = 0.5
    public static let maximumRate: Double = 4.0
    public static let rateStep: Double = 0.25
    public static let defaultRate: Double = 2.0

    public init() {}

    /// Number of draws for a block. `block_hours × rate`, rounded.
    public static func drawCount(hours: Double, rate: Double) -> Int {
        max(0, Int((hours * rate).rounded()))
    }

    /// The start of the block containing `date`, on a fixed 12h clock boundary.
    public static func blockStart(containing date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let midday = calendar.date(byAdding: .hour, value: Int(blockHours), to: startOfDay)!
        return date < midday ? startOfDay : midday
    }

    /// Draw a block covering the 12 hours from `start`.
    public func makeBlock<G: RandomNumberGenerator>(
        start: Date,
        rate: Double,
        generatedAt: Date,
        calendar: Calendar = .current,
        using rng: inout G
    ) -> ScheduleBlock {
        let end = calendar.date(byAdding: .hour, value: Int(Self.blockHours), to: start)!
        let blockID = UUID()
        let span = end.timeIntervalSince(start)
        let count = Self.drawCount(hours: Self.blockHours, rate: rate)

        let times = (0..<count)
            .map { _ in start.addingTimeInterval(Double.random(in: 0..<span, using: &rng)) }
            .sorted()

        return ScheduleBlock(
            id: blockID,
            start: start,
            end: end,
            rate: rate,
            generatedAt: generatedAt,
            triggers: times.map { ScheduledTrigger(blockID: blockID, fireAt: $0) }
        )
    }

    /// Clamp an arbitrary rate onto the slider's step grid.
    public static func normalizedRate(_ rate: Double) -> Double {
        let clamped = min(max(rate, minimumRate), maximumRate)
        return (clamped / rateStep).rounded() * rateStep
    }
}

/// Seedable RNG so scheduler tests assert on a real distribution rather than
/// mocking the draw away. A test that stubs the randomness isn't testing the
/// thing that can actually be wrong here.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // SplitMix64 tolerates a zero seed poorly; nudge it off zero.
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
