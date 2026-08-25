import Foundation
import Testing
@testable import PhoneDownKit

private func utcCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}

private func date(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")!
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: iso)!
}

@Suite("Block generation")
struct BlockGeneratorTests {

    @Test("A block draws block_hours x rate times")
    func drawCountMatchesRate() {
        let cases: [(rate: Double, expected: Int)] = [
            (0.5, 6), (1.0, 12), (2.0, 24), (2.25, 27), (4.0, 48),
        ]
        for (rate, expected) in cases {
            #expect(BlockGenerator.drawCount(hours: 12, rate: rate) == expected,
                    "rate \(rate)")
        }
    }

    @Test("Every drawn time lands inside the block, and they come back sorted")
    func drawsAreInBoundsAndSorted() {
        var rng = SeededGenerator(seed: 42)
        let start = date("2026-03-04T00:00:00Z")
        let block = BlockGenerator().makeBlock(
            start: start, rate: 4.0, generatedAt: start,
            calendar: utcCalendar(), using: &rng
        )

        #expect(block.triggers.count == 48)
        #expect(block.end == date("2026-03-04T12:00:00Z"))
        for trigger in block.triggers {
            #expect(trigger.fireAt >= block.start)
            #expect(trigger.fireAt < block.end)
        }
        #expect(block.triggers.map(\.fireAt) == block.triggers.map(\.fireAt).sorted())
    }

    /// The draws must be uniform across the block, not spread evenly. Those are
    /// different things and only one of them is specified. Bucketing a large
    /// sample and checking every bucket is populated within a loose band catches
    /// an accidental even-spacing or a truncated range without making the test
    /// flaky on an unlucky seed.
    @Test("Draws are uniform across the whole block")
    func drawsAreUniform() {
        var rng = SeededGenerator(seed: 7)
        let start = date("2026-03-04T00:00:00Z")
        let generator = BlockGenerator()
        let bucketCount = 12
        var buckets = [Int](repeating: 0, count: bucketCount)

        for _ in 0..<400 {
            let block = generator.makeBlock(
                start: start, rate: 4.0, generatedAt: start,
                calendar: utcCalendar(), using: &rng
            )
            for trigger in block.triggers {
                let offset = trigger.fireAt.timeIntervalSince(start)
                let bucket = min(bucketCount - 1, Int(offset / (block.duration / Double(bucketCount))))
                buckets[bucket] += 1
            }
        }

        let total = buckets.reduce(0, +)
        #expect(total == 400 * 48)
        let expectedPerBucket = Double(total) / Double(bucketCount)
        for (index, count) in buckets.enumerated() {
            let ratio = Double(count) / expectedPerBucket
            #expect(ratio > 0.85 && ratio < 1.15, "bucket \(index) held \(count), expected ~\(Int(expectedPerBucket))")
        }
    }

    /// Clustering is correct behaviour, not a defect to be smoothed away. If a
    /// minimum-gap constraint ever gets added this test starts failing, which is
    /// exactly what should happen.
    @Test("No minimum gap is enforced — tight clusters occur")
    func clusteringHappens() {
        var rng = SeededGenerator(seed: 99)
        let start = date("2026-03-04T00:00:00Z")
        let generator = BlockGenerator()
        var sawTightCluster = false

        for _ in 0..<200 where !sawTightCluster {
            let block = generator.makeBlock(
                start: start, rate: 4.0, generatedAt: start,
                calendar: utcCalendar(), using: &rng
            )
            let times = block.triggers.map(\.fireAt)
            for (a, b) in zip(times, times.dropFirst()) where b.timeIntervalSince(a) < 60 {
                sawTightCluster = true
                break
            }
        }

        #expect(sawTightCluster, "expected at least one sub-minute gap across 200 blocks")
    }

    @Test("Blocks land on fixed 12-hour clock boundaries")
    func blockBoundaries() {
        let cal = utcCalendar()
        #expect(BlockGenerator.blockStart(containing: date("2026-03-04T00:00:00Z"), calendar: cal)
                == date("2026-03-04T00:00:00Z"))
        #expect(BlockGenerator.blockStart(containing: date("2026-03-04T11:59:59Z"), calendar: cal)
                == date("2026-03-04T00:00:00Z"))
        #expect(BlockGenerator.blockStart(containing: date("2026-03-04T12:00:00Z"), calendar: cal)
                == date("2026-03-04T12:00:00Z"))
        #expect(BlockGenerator.blockStart(containing: date("2026-03-04T23:59:59Z"), calendar: cal)
                == date("2026-03-04T12:00:00Z"))
    }

    @Test("Rate is clamped onto the slider's step grid")
    func rateNormalization() {
        let cases: [(input: Double, expected: Double)] = [
            (0.1, 0.5), (0.5, 0.5), (2.0, 2.0), (2.3, 2.25), (2.4, 2.5), (4.0, 4.0), (9.9, 4.0),
        ]
        for (input, expected) in cases {
            #expect(abs(BlockGenerator.normalizedRate(input) - expected) < 0.0001,
                    "input \(input)")
        }
    }

    @Test("The same seed reproduces the same block")
    func generationIsDeterministic() {
        let start = date("2026-03-04T00:00:00Z")
        let generator = BlockGenerator()
        var a = SeededGenerator(seed: 12345)
        var b = SeededGenerator(seed: 12345)
        let first = generator.makeBlock(start: start, rate: 2.0, generatedAt: start, calendar: utcCalendar(), using: &a)
        let second = generator.makeBlock(start: start, rate: 2.0, generatedAt: start, calendar: utcCalendar(), using: &b)
        #expect(first.triggers.map(\.fireAt) == second.triggers.map(\.fireAt))
    }

    /// A 12h block at the top of the slider must stay under the 64-notification
    /// cap, or the top end of the rate slider silently loses triggers.
    @Test("A max-rate block fits under the iOS pending-notification cap")
    func maxRateBlockFitsUnderNotificationCap() {
        let perBlock = BlockGenerator.drawCount(hours: BlockGenerator.blockHours, rate: BlockGenerator.maximumRate)
        #expect(perBlock == 48)
        #expect(perBlock < 64)
        // Two blocks pending at once would not fit, which is why registration
        // rolls rather than registering a whole block at a time.
        #expect(perBlock * 2 > 64)
    }
}
