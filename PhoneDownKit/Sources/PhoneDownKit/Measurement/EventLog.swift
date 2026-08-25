import Foundation

/// Append-only, crash-safe event log.
///
/// Written as JSON Lines and flushed on every append. The process this log
/// observes can be killed at any moment without warning — a buffered writer
/// would lose exactly the events that explain the death.
public final class EventLog: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        prepareFile()
    }

    public var fileURL: URL { url }

    /// Record an event. Safe to call from any thread, including the arbitrary
    /// queues Darwin notifications arrive on.
    public func append(_ kind: DeviceEventKind, detail: String? = nil, date: Date = Date()) {
        let event = DeviceEvent(
            date: date,
            uptime: ProcessInfo.processInfo.systemUptime,
            kind: kind,
            detail: detail
        )
        append(event)
    }

    public func append(_ event: DeviceEvent) {
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)  // newline

        lock.lock()
        defer { lock.unlock() }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    /// Every event recorded, oldest first. Malformed lines are skipped rather
    /// than aborting the read — a torn final line from a kill mid-write must
    /// not cost us the entire history.
    public func allEvents() -> [DeviceEvent] {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: url) else { return [] }
        return data
            .split(separator: 0x0A)
            .compactMap { try? decoder.decode(DeviceEvent.self, from: Data($0)) }
    }

    /// The whole log as a single JSON array, for the share sheet.
    public func exportJSON() throws -> Data {
        let export = JSONEncoder()
        export.dateEncodingStrategy = .iso8601
        export.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try export.encode(allEvents())
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? Data().write(to: url, options: .atomic)
    }

    // MARK: - Setup

    private func prepareFile() {
        let manager = FileManager.default
        try? manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        applyProtection()
    }

    /// The log must be writable while the device is locked, because the events
    /// worth catching are the ones that happen at exactly that moment. Under
    /// the default protection class the file becomes unwritable seconds after
    /// lock and every lock event would be silently dropped.
    private func applyProtection() {
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
