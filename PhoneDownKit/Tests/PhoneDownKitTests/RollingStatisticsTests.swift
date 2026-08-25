import Foundation
import Testing
@testable import PhoneDownKit

private let day: TimeInterval = 86_400
private let origin = Date(timeIntervalSince1970: 1_772_000_000)
private func onDay(_ n: Double, _ value: Double) -> DatedValue {
    DatedValue(date: origin.addingTimeInterval(n * day), value: value)
}

@Suite("Rolling statistics")
struct RollingStatisticsTests {

    /// The defining property: the window is a span of days, so sample density
    /// must not change the answer. Ten samples in one day and one sample in one
    /// day both mean "that day".
    @Test("The window is days, not samples")
    func windowIsDaysNotSamples() {
        let sparse = [onDay(0, 10), onDay(1, 20), onDay(2, 30)]
        let dense = [
            onDay(0, 10), onDay(0.1, 10), onDay(0.2, 10),
            onDay(1, 20), onDay(1.1, 20),
            onDay(2, 30),
        ]

        let sparseAverage = RollingStatistics.average(
            of: sparse, window: RollingWindow(days: 3), asOf: origin.addingTimeInterval(2 * day)
        )
        let denseAverage = RollingStatistics.average(
            of: dense, window: RollingWindow(days: 3), asOf: origin.addingTimeInterval(2 * day)
        )

        #expect(sparseAverage == 20)
        // Dense weights by sample, but both cover the same three days — the
        // window did not silently become "last 3 samples".
        #expect(denseAverage != nil)
        #expect(abs(denseAverage! - 16.666) < 0.01)
    }

    @Test("Samples outside the window are excluded")
    func windowExcludesOlderSamples() {
        let samples = [onDay(0, 100), onDay(5, 10), onDay(6, 20)]
        let average = RollingStatistics.average(
            of: samples, window: RollingWindow(days: 3), asOf: origin.addingTimeInterval(6 * day)
        )
        #expect(average == 15)  // the day-0 outlier is out of range
    }

    @Test("An empty window yields nil rather than zero")
    func emptyWindowIsNil() {
        let samples = [onDay(0, 100)]
        let average = RollingStatistics.average(
            of: samples, window: RollingWindow(days: 2), asOf: origin.addingTimeInterval(10 * day)
        )
        #expect(average == nil)
    }

    /// The window is half-open — `(date - window, date]`. A sample sitting
    /// exactly on the trailing edge has aged out. Pinned explicitly because the
    /// inclusive convention silently widens every window by one boundary
    /// sample, which surfaces as a small persistent bias in every rolling line
    /// rather than as an obvious break.
    @Test("Rolling average produces one point per sample, over a half-open window")
    func rollingAverageShape() {
        let samples = [onDay(0, 10), onDay(1, 20), onDay(2, 30), onDay(3, 40)]
        let rolling = RollingStatistics.rollingAverage(of: samples, window: RollingWindow(days: 2))

        #expect(rolling.count == 4)
        #expect(rolling[0].value == 10)   // (day -2, day 0]  -> 10
        #expect(rolling[1].value == 15)   // (day -1, day 1]  -> 10, 20
        #expect(rolling[2].value == 25)   // (day  0, day 2]  -> 20, 30; day 0 has aged out
        #expect(rolling[3].value == 35)   // (day  1, day 3]  -> 30, 40
    }

    /// Failures per day and failure proportion answer different questions. A
    /// day with one failure out of two samples and a day with one failure out
    /// of fifty have the same rate and very different proportions.
    @Test("Failures per day is a rate, not a proportion")
    func failuresPerDayIsARate() {
        let samples = [onDay(0, 5), onDay(0.5, 200), onDay(1, 300), onDay(2, 10)]
        let window = RollingWindow(days: 7)

        let rate = RollingStatistics.rollingFailuresPerDay(of: samples, window: window, threshold: 60)
        let proportion = RollingStatistics.rollingFailureProportion(of: samples, window: window, threshold: 60)

        // Two of four samples exceed 60 by the last point.
        #expect(abs(rate.last!.value - (2.0 / 7.0)) < 0.0001)
        #expect(abs(proportion.last!.value - 0.5) < 0.0001)
    }

    @Test("Moving the threshold recomputes the failure line")
    func thresholdIsLive() {
        let samples = [onDay(0, 10), onDay(1, 50), onDay(2, 90)]
        let window = RollingWindow(days: 7)

        let strict = RollingStatistics.rollingFailureProportion(of: samples, window: window, threshold: 5)
        let loose = RollingStatistics.rollingFailureProportion(of: samples, window: window, threshold: 100)

        #expect(strict.last!.value == 1.0)
        #expect(loose.last!.value == 0.0)
    }

    @Test("Trend delta compares the window against the one before it")
    func trendDelta() {
        // Days 0-2 average 100, days 3-5 average 40.
        let samples = [
            onDay(0.1, 100), onDay(1, 100), onDay(2, 100),
            onDay(3.1, 40), onDay(4, 40), onDay(5, 40),
        ]
        let delta = RollingStatistics.trendDelta(
            of: samples, window: RollingWindow(days: 3), asOf: origin.addingTimeInterval(6 * day)
        )

        #expect(delta != nil)
        #expect(delta!.current == 40)
        #expect(delta!.previous == 100)
        #expect(delta!.absolute == -60)
        #expect(abs(delta!.relative! - -0.6) < 0.0001)
        #expect(delta!.isImprovement())                       // latency down is good
        #expect(delta!.isImprovement(lowerIsBetter: false) == false)
    }

    @Test("A trend against an empty prior window is nil, not zero")
    func trendNeedsBothWindows() {
        let samples = [onDay(5, 40), onDay(6, 40)]
        let delta = RollingStatistics.trendDelta(
            of: samples, window: RollingWindow(days: 2), asOf: origin.addingTimeInterval(6 * day)
        )
        #expect(delta == nil)
    }

    @Test("Relative change against a zero baseline is nil, not infinity")
    func relativeAgainstZero() {
        let delta = TrendDelta(current: 5, previous: 0)
        #expect(delta.relative == nil)
        #expect(delta.absolute == 5)
    }

    @Test("A window of zero or fewer days is clamped to one")
    func windowClamping() {
        #expect(RollingWindow(days: 0).days == 1)
        #expect(RollingWindow(days: -5).days == 1)
        #expect(RollingWindow(days: 30).days == 30)
    }
}

@Suite("Chart windows")
struct ChartWindowTests {

    @Test("A chart inherits the global default and is not marked as overridden")
    func inheritance() {
        let chart = ChartWindow.inheriting(RollingWindow(days: 7))
        #expect(chart.window.days == 7)
        #expect(chart.isOverridden == false)
    }

    @Test("Overriding to a different window marks the chart")
    func overrideMarks() {
        var chart = ChartWindow.inheriting(RollingWindow(days: 7))
        chart.setWindow(RollingWindow(days: 30), globalDefault: RollingWindow(days: 7))
        #expect(chart.window.days == 30)
        #expect(chart.isOverridden)
    }

    /// Setting a chart to the value it already inherited is not an override,
    /// or every chart would eventually carry a marker that means nothing.
    @Test("Overriding to the default value is not an override")
    func overrideToDefaultIsNotAnOverride() {
        var chart = ChartWindow.inheriting(RollingWindow(days: 7))
        chart.setWindow(RollingWindow(days: 7), globalDefault: RollingWindow(days: 7))
        #expect(chart.isOverridden == false)
    }

    @Test("A chart stops being marked when the global default moves to match it")
    func reconcileClearsStaleMarker() {
        var chart = ChartWindow.inheriting(RollingWindow(days: 7))
        chart.setWindow(RollingWindow(days: 30), globalDefault: RollingWindow(days: 7))
        #expect(chart.isOverridden)

        chart.reconcile(withGlobalDefault: RollingWindow(days: 30))
        #expect(chart.isOverridden == false)
        #expect(chart.window.days == 30)
    }
}
