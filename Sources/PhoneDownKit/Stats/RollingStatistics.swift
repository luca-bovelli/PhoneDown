import Foundation

/// Rolling aggregates over dated samples.
///
/// Every window here is a span of days ending at the sample being reported, so
/// a point on a rolling line always answers "what did the last N days look like
/// as of this moment" — never "what did the last N samples look like".
public enum RollingStatistics {

    /// Mean of every sample falling in `(date - window, date]`, evaluated at
    /// each sample. Samples must be sorted by date.
    public static func rollingAverage(
        of samples: [DatedValue],
        window: RollingWindow
    ) -> [DatedValue] {
        rolling(samples, window: window) { slice in
            slice.isEmpty ? nil : slice.reduce(0) { $0 + $1.value } / Double(slice.count)
        }
    }

    /// Failures per day: how many samples in the window exceeded `threshold`,
    /// divided by the window length.
    ///
    /// The spec calls this a proportion but asks for it *expressed as failures
    /// per day*. Those are different quantities, so both are available —
    /// `failuresPerDay` is the one meant for display, `failureProportion` is
    /// the unitless form. Using the proportion where a rate is expected would
    /// make a quiet day look identical to a heavy one.
    public static func rollingFailuresPerDay(
        of samples: [DatedValue],
        window: RollingWindow,
        threshold: Double
    ) -> [DatedValue] {
        rolling(samples, window: window) { slice in
            Double(slice.filter { $0.value > threshold }.count) / Double(window.days)
        }
    }

    /// Proportion of samples in the window that exceeded `threshold`, 0...1.
    public static func rollingFailureProportion(
        of samples: [DatedValue],
        window: RollingWindow,
        threshold: Double
    ) -> [DatedValue] {
        rolling(samples, window: window) { slice in
            slice.isEmpty ? nil : Double(slice.filter { $0.value > threshold }.count) / Double(slice.count)
        }
    }

    /// Mean over the window ending at `asOf`. The headline number.
    public static func average(
        of samples: [DatedValue],
        window: RollingWindow,
        asOf date: Date
    ) -> Double? {
        let slice = samples.filter { $0.date > date.addingTimeInterval(-window.duration) && $0.date <= date }
        guard !slice.isEmpty else { return nil }
        return slice.reduce(0) { $0 + $1.value } / Double(slice.count)
    }

    /// Change between the window ending at `asOf` and the window immediately
    /// before it. Nil when either side is empty — a delta against nothing is
    /// not a trend, and rendering one as "0%" would invent a story.
    public static func trendDelta(
        of samples: [DatedValue],
        window: RollingWindow,
        asOf date: Date
    ) -> TrendDelta? {
        let previousEnd = date.addingTimeInterval(-window.duration)
        guard
            let current = average(of: samples, window: window, asOf: date),
            let previous = average(of: samples, window: window, asOf: previousEnd)
        else { return nil }
        return TrendDelta(current: current, previous: previous)
    }

    // MARK: - Shared traversal

    private static func rolling(
        _ samples: [DatedValue],
        window: RollingWindow,
        reduce: (ArraySlice<DatedValue>) -> Double?
    ) -> [DatedValue] {
        guard !samples.isEmpty else { return [] }
        var result: [DatedValue] = []
        result.reserveCapacity(samples.count)
        var lower = 0

        for upper in samples.indices {
            let cutoff = samples[upper].date.addingTimeInterval(-window.duration)
            while lower < upper && samples[lower].date <= cutoff { lower += 1 }
            if let value = reduce(samples[lower...upper]) {
                result.append(DatedValue(date: samples[upper].date, value: value))
            }
        }
        return result
    }
}

/// A window-over-window change.
public struct TrendDelta: Equatable, Sendable {
    public let current: Double
    public let previous: Double

    public init(current: Double, previous: Double) {
        self.current = current
        self.previous = previous
    }

    public var absolute: Double { current - previous }

    /// Relative change. Nil when the previous window averaged zero — dividing
    /// by it would produce an infinity that renders as a plausible-looking
    /// percentage.
    public var relative: Double? {
        previous == 0 ? nil : (current - previous) / abs(previous)
    }

    /// For latency, lower is better. Callers holding a higher-is-better metric
    /// pass `lowerIsBetter: false`.
    public func isImprovement(lowerIsBetter: Bool = true) -> Bool {
        lowerIsBetter ? absolute < 0 : absolute > 0
    }
}
