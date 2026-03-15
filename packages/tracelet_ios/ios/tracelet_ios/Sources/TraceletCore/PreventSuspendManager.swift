import AVFoundation
import Foundation

/// Prevents iOS from suspending the app by playing a silent audio loop
/// in the background using AVAudioSession .playback category.
///
/// This keeps the app alive when in the background, even when no
/// location updates are arriving (e.g., stationary state). Only enabled
/// when `AppConfig.preventSuspend` is `true`.
///
/// ⚠️ Apple has flagged this pattern in the past. Use with caution
/// and only when necessary for reliable background operation.
public final class PreventSuspendManager {
    private let configManager: ConfigManager
    private var audioPlayer: AVAudioPlayer?
    private var isRunning = false

    public init(configManager: ConfigManager) {
        self.configManager = configManager
    }

    /// Start the silent audio loop if `preventSuspend` is enabled.
    public func start() {
        guard configManager.getPreventSuspend() else { return }
        guard !isRunning else { return }

        do {
            // Configure audio session for background playback
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            // Generate a silent WAV in memory (1 second, mono, 8kHz, 16-bit)
            let silentData = generateSilentWAV(durationSeconds: 1.0, sampleRate: 8000)
            audioPlayer = try AVAudioPlayer(data: silentData)
            audioPlayer?.numberOfLoops = -1 // Loop forever
            audioPlayer?.volume = 0.0
            audioPlayer?.play()

            isRunning = true
            NSLog("[Tracelet] preventSuspend started — silent audio loop active")
        } catch {
            NSLog("[Tracelet] preventSuspend failed to start: \(error.localizedDescription)")
        }
    }

    /// Stop the silent audio loop.
    public func stop() {
        guard isRunning else { return }
        audioPlayer?.stop()
        audioPlayer = nil
        isRunning = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        NSLog("[Tracelet] preventSuspend stopped")
    }

    // MARK: - Silent WAV generation

    /// Generates a minimal WAV file with silence (all zero samples).
    private func generateSilentWAV(durationSeconds: Double, sampleRate: Int) -> Data {
        let numChannels: Int = 1
        let bitsPerSample: Int = 16
        let bytesPerSample = bitsPerSample / 8
        let numSamples = Int(durationSeconds * Double(sampleRate))
        let dataSize = numSamples * numChannels * bytesPerSample
        let fileSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM format
        data.append(contentsOf: withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        let byteRate = sampleRate * numChannels * bytesPerSample
        data.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        let blockAlign = numChannels * bytesPerSample
        data.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        data.append(Data(count: dataSize)) // All zeros = silence

        return data
    }
}
