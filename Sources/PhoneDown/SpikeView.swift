import SwiftUI
import PhoneDownKit

/// Deliberately plain. This build is an instrument to be read, not the app.
struct SpikeView: View {
    @EnvironmentObject private var coordinator: SpikeCoordinator

    var body: some View {
        NavigationStack {
            List {
                findings
                events
            }
            .navigationTitle("PhoneDown Spike")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) { coordinator.clear() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: coordinator.log.fileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .refreshable { coordinator.refresh() }
        }
    }

    // MARK: - Findings

    /// The four questions this build exists to answer, on one screen.
    private var findings: some View {
        Section("Findings") {
            if let lag = coordinator.lagSummary {
                row("protectedData lag", "\(fmt(lag.mean))s mean")
                row("  spread", "\(fmt(lag.min))s – \(fmt(lag.max))s over \(lag.samples)")
                // Spread is the decision, not the mean. A constant offset can be
                // subtracted; a variable one is noise on a metric measured in
                // seconds and cannot be calibrated away.
                Text(lag.max - lag.min < 1
                     ? "Stable. The public signal can replace the Darwin key."
                     : "Jittery. The Darwin key is earning its keep.")
                    .font(.footnote)
                    .foregroundStyle(lag.max - lag.min < 1 ? .green : .orange)
            } else {
                Text("No paired lock episodes yet — lock the phone a few times.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            row("Lock episodes", "\(coordinator.episodeCount)")
            row("Observation gaps", "\(coordinator.gaps.count)")

            ForEach(Array(coordinator.gaps.enumerated()), id: \.offset) { _, gap in
                row(
                    gap.spannedReboot ? "  gap (reboot)" : "  gap (died)",
                    "\(Int(gap.duration / 60))m"
                )
            }
        }
    }

    private var events: some View {
        Section("Events (\(coordinator.events.count))") {
            ForEach(coordinator.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(event.kind.rawValue)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text(timestamp(event.date))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let detail = event.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(background(for: event.kind))
            }
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func background(for kind: DeviceEventKind) -> Color {
        if DeviceEvent.lockLike.contains(kind) { return .blue.opacity(0.12) }
        if DeviceEvent.unlockLike.contains(kind) { return .green.opacity(0.10) }
        if kind == .heartbeat { return .clear }
        return .orange.opacity(0.08)
    }

    /// Milliseconds matter here — the whole question is how far apart two
    /// signals fire, and a second-resolution clock would hide the answer.
    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func fmt(_ interval: TimeInterval) -> String {
        String(format: "%.2f", interval)
    }
}
