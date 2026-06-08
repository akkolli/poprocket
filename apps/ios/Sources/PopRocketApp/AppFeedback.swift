import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum AppFeedback {
    enum PreferenceKey {
        static let hapticsEnabled = "poprocket.feedback.haptics.enabled"
        static let tonesEnabled = "poprocket.feedback.tones.enabled"
    }

    static let defaultHapticsEnabled = true
    static let defaultTonesEnabled = false

    static var hapticsEnabled: Bool {
        get {
            userDefaults.object(forKey: PreferenceKey.hapticsEnabled) as? Bool ?? defaultHapticsEnabled
        }
        set {
            userDefaults.set(newValue, forKey: PreferenceKey.hapticsEnabled)
        }
    }

    static var tonesEnabled: Bool {
        get {
            userDefaults.object(forKey: PreferenceKey.tonesEnabled) as? Bool ?? defaultTonesEnabled
        }
        set {
            userDefaults.set(newValue, forKey: PreferenceKey.tonesEnabled)
        }
    }

    static func selection() {
        guard hapticsEnabled else {
            return
        }
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func actionStarted() {
        guard hapticsEnabled else {
            return
        }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        if hapticsEnabled {
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        }
        playTone(.success)
    }

    static func warning() {
        if hapticsEnabled {
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
        }
        playTone(.warning)
    }

    static func failure() {
        if hapticsEnabled {
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
        }
        playTone(.failure)
    }

    static func destructive() {
        if hapticsEnabled {
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
        }
        playTone(.destructive)
    }

    private static func playTone(_ tone: FeedbackTone) {
        guard tonesEnabled else {
            return
        }
        #if canImport(AVFoundation)
        FeedbackToneEngine.shared.play(tone)
        #endif
    }

    private static let userDefaults = UserDefaults.standard
}

private enum FeedbackTone {
    case success
    case warning
    case failure
    case destructive

    var audioEvents: [FeedbackAudioEvent] {
        switch self {
        case .success:
            return [
                FeedbackAudioEvent(time: 0.00, duration: 0.050, frequency: 520, volume: 0.050),
                FeedbackAudioEvent(time: 0.070, duration: 0.055, frequency: 660, volume: 0.045)
            ]
        case .warning:
            return [
                FeedbackAudioEvent(time: 0.00, duration: 0.080, frequency: 392, volume: 0.042)
            ]
        case .failure:
            return [
                FeedbackAudioEvent(time: 0.00, duration: 0.060, frequency: 330, volume: 0.045),
                FeedbackAudioEvent(time: 0.085, duration: 0.070, frequency: 277, volume: 0.040)
            ]
        case .destructive:
            return [
                FeedbackAudioEvent(time: 0.00, duration: 0.065, frequency: 294, volume: 0.038)
            ]
        }
    }
}

private struct FeedbackAudioEvent {
    let time: TimeInterval
    let duration: TimeInterval
    let frequency: Double
    let volume: Float
}

#if canImport(AVFoundation)
@MainActor
private final class FeedbackToneEngine {
    static let shared = FeedbackToneEngine()

    private let sampleRate = 44_100
    private let minimumToneInterval: TimeInterval = 0.22
    private let maximumConcurrentPlayers = 2
    private var lastPlayedAt: Date?
    private var players: [AVAudioPlayer] = []

    func play(_ tone: FeedbackTone) {
        guard canPlayToneNow else {
            return
        }
        do {
            try configureAudioSession()
            players.removeAll { !$0.isPlaying }
            if players.count >= maximumConcurrentPlayers {
                players.removeFirst(players.count - maximumConcurrentPlayers + 1)
            }
            let player = try AVAudioPlayer(data: wavData(for: tone.audioEvents))
            player.prepareToPlay()
            player.play()
            players.append(player)
            lastPlayedAt = Date()
        } catch {
            players.removeAll()
        }
    }

    private var canPlayToneNow: Bool {
        guard let lastPlayedAt else {
            return true
        }
        return Date().timeIntervalSince(lastPlayedAt) >= minimumToneInterval
    }

    private func configureAudioSession() throws {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, options: [.mixWithOthers])
        try session.setActive(true, options: [])
        #endif
    }

    private func wavData(for events: [FeedbackAudioEvent]) -> Data {
        let totalDuration = (events.map { $0.time + $0.duration }.max() ?? 0) + 0.030
        let sampleCount = max(1, Int(Double(sampleRate) * totalDuration))
        var samples: [Int16] = Array(repeating: 0, count: sampleCount)

        for event in events {
            let startIndex = max(0, Int(event.time * Double(sampleRate)))
            let eventSampleCount = max(1, Int(event.duration * Double(sampleRate)))
            let endIndex = min(sampleCount, startIndex + eventSampleCount)
            guard startIndex < endIndex else {
                continue
            }

            for index in startIndex..<endIndex {
                let localIndex = index - startIndex
                let phase = (Double(localIndex) / Double(sampleRate)) * event.frequency * 2.0 * Double.pi
                let envelope = envelopeValue(index: localIndex, count: eventSampleCount)
                let value = sin(phase) * Double(event.volume) * envelope
                let mixed = Double(samples[index]) + value * Double(Int16.max)
                samples[index] = Int16(max(Double(Int16.min), min(Double(Int16.max), mixed)))
            }
        }

        return makeWAVData(samples: samples)
    }

    private func envelopeValue(index: Int, count: Int) -> Double {
        let attackCount = max(1, Int(Double(sampleRate) * 0.006))
        let releaseCount = max(1, Int(Double(sampleRate) * 0.020))
        if index < attackCount {
            return Double(index) / Double(attackCount)
        }
        let releaseStart = max(0, count - releaseCount)
        if index >= releaseStart {
            return max(0, Double(count - index) / Double(releaseCount))
        }
        return 1
    }

    private func makeWAVData(samples: [Int16]) -> Data {
        var data = Data()
        let byteRate = UInt32(sampleRate * 2)
        let dataByteCount = UInt32(samples.count * 2)

        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36) + dataByteCount)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(dataByteCount)
        samples.forEach { data.appendLittleEndian($0) }

        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
#endif
