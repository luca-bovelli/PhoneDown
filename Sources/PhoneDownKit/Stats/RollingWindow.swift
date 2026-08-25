import Foundation

/// A rolling window, defined in **days**.
///
/// Deliberately not a sample count. The user reads trends in days; how many
/// samples happen to fall in a span is an implementation detail of the draw
/// rate and shouldn't leak into how a trend is expressed. A quiet week and a
/// busy week must mean the same span.
public struct RollingWindow: Codable, Equatable, Hashable, Sendable {
    public let days: Int

    public init(days: Int) {
        self.days = max(1, days)
    }

    public static let `default` = RollingWindow(days: 7)

    public var duration: TimeInterval { Double(days) * 86_400 }
}

/// A window attached to a specific chart, which may or may not match the global
/// default. Charts that differ must be marked in the UI, so the divergence is
/// carried as data rather than being recomputed by the view.
public struct ChartWindow: Codable, Equatable, Sendable {
    public var window: RollingWindow
    public var isOverridden: Bool

    public init(window: RollingWindow = .default, isOverridden: Bool = false) {
        self.window = window
        self.isOverridden = isOverridden
    }

    public static func inheriting(_ global: RollingWindow) -> ChartWindow {
        ChartWindow(window: global, isOverridden: false)
    }

    public mutating func override(with window: RollingWindow, globalDefault: RollingWindow) {
        self.window = window
        self.isOverridden = window != globalDefault
    }

    /// Re-evaluate against a changed global default. A chart that was pinned to
    /// 7 days stops counting as overridden the moment the default becomes 7.
    public mutating func reconcile(withGlobalDefault global: RollingWindow) {
        isOverridden = window != global
    }
}

/// A value with the moment it belongs to.
public struct DatedValue: Codable, Equatable, Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}
