import AVFoundation
import PhoneDownKit

/// Holds the process alive by keeping an audio session playing.
///
/// This is the mechanism that makes the whole instrument possible and it is
/// also the reason the app can never ship on the App Store: guideline 2.5.4
/// requires apps declaring background audio to play audible content, and this
/// deliberately plays nothing you can hear. That trade is made knowingly.
///
/// The session mixes with others, so it never interrupts music or takes over
/// the now-playing controls.
final class KeepAliveSession {
    private let engine = AVAudioEngine()
    private let log: EventLog
    private var sourceNode: AVAudioSourceNode?
    private var isRunning = false

    init(log: EventLog) {
        self.log = log
        observeInterruptions()
    }

    func start() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let format = engine.outputNode.inputFormat(forBus: 0)
            let node = makeSilentSourceNode(format: format)
            engine.attach(node)
            engine.connect(node, to: engine.outputNode, format: format)
            sourceNode = node

            try engine.start()
            isRunning = true
            log.append(.keepAliveStarted, detail: "sampleRate=\(format.sampleRate)")
        } catch {
            log.append(.keepAliveFailed, detail: String(describing: error))
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        if let sourceNode { engine.detach(sourceNode) }
        sourceNode = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    /// Renders a tone at roughly -80 dBFS — far below anything audible, but not
    /// digital silence. iOS has been observed to deprioritise sessions pushing
    /// literal zeroes, and being deprioritised here means being suspended, which
    /// is the one failure this class exists to prevent. If the spike shows the
    /// session surviving on true silence, drop the amplitude to zero.
    private func makeSilentSourceNode(format: AVAudioFormat) -> AVAudioSourceNode {
        let sampleRate = format.sampleRate
        var phase: Double = 0
        let increment = 2 * Double.pi * 20 / sampleRate   // 20 Hz, below hearing
        let amplitude: Float = 0.0001

        return AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let value = amplitude * Float(sin(phase))
                phase += increment
                if phase > 2 * .pi { phase -= 2 * .pi }
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    data[frame] = value
                }
            }
            return noErr
        }
    }

    /// A phone call or another app taking exclusive audio will interrupt the
    /// session. Without resuming afterwards the process quietly loses its
    /// reason to stay alive and gets suspended at the next opportunity.
    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard
                let self,
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }

            switch type {
            case .began:
                self.isRunning = false
                self.log.append(.keepAliveInterrupted)
            case .ended:
                self.start()
                self.log.append(.keepAliveResumed)
            @unknown default:
                break
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.isRunning = false
            self.log.append(.keepAliveInterrupted, detail: "mediaServicesReset")
            self.start()
        }
    }
}
