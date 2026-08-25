import Foundation
import UIKit
import PhoneDownKit

/// Watches every candidate lock signal at once and records each separately.
///
/// The spike exists to answer one question: can the public `protectedData`
/// notification replace the private Darwin notify keys? So the signals are
/// never merged here. Merging them is the conclusion we are trying to earn, and
/// a monitor that decided in advance would have nothing to report.
final class LockSignalMonitor {

    /// Screen backlight on/off. The closest available proxy for "the phone
    /// stopped being used", and it fires for a screen timeout exactly as it
    /// does for a button press — which is the equivalence the spec asks for.
    private static let displayStatusKey = "com.apple.iokit.hid.displayStatus"

    /// Lock state proper. Not the same event as the backlight going out.
    private static let lockStateKey = "com.apple.springboard.lockstate"

    private let log: EventLog
    private var tokens: [Int32] = []

    init(log: EventLog) {
        self.log = log
    }

    func start() {
        // The polarity of both keys is asserted from convention, not from Apple
        // documentation that exists. The raw value goes into `detail` on every
        // event so the first real run confirms or corrects it, rather than us
        // trusting a guess forever.
        registerDarwin(Self.displayStatusKey) { [log] state in
            log.append(
                state == 1 ? .screenOn : .screenOff,
                detail: "\(Self.displayStatusKey)=\(state)"
            )
        }

        registerDarwin(Self.lockStateKey) { [log] state in
            log.append(
                state == 1 ? .deviceLocked : .deviceUnlocked,
                detail: "\(Self.lockStateKey)=\(state)"
            )
        }

        observePublicSignals()
    }

    func stop() {
        for token in tokens { notify_cancel(token) }
        tokens = []
    }

    // MARK: - Darwin

    private func registerDarwin(_ key: String, handler: @escaping (UInt64) -> Void) {
        var token: Int32 = NOTIFY_TOKEN_INVALID
        // Delivered on a background queue: these fire at the instant the screen
        // goes dark, and hopping to main first would add scheduling latency to
        // the exact measurement being taken.
        let status = notify_register_dispatch(
            key,
            &token,
            DispatchQueue.global(qos: .userInitiated)
        ) { token in
            var state: UInt64 = 0
            notify_get_state(token, &state)
            handler(state)
        }

        if status == NOTIFY_STATUS_OK {
            tokens.append(token)
        } else {
            log.append(.keepAliveFailed, detail: "notify_register_dispatch(\(key)) status=\(status)")
        }
    }

    // MARK: - Public API

    /// The documented alternative. Fires when iOS evicts the data-protection
    /// keys, which happens on lock — but not necessarily at the same instant
    /// the screen went dark, and that gap is the thing being measured.
    private func observePublicSignals() {
        let center = NotificationCenter.default

        center.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: nil
        ) { [log] _ in
            log.append(.protectedDataUnavailable)
        }

        center.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: nil
        ) { [log] _ in
            log.append(.protectedDataAvailable)
        }
    }
}
