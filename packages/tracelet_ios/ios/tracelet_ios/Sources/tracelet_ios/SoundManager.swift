import AudioToolbox
import AVFoundation
import Foundation

/// Debug sound feedback using SystemSoundID.
///
/// Only plays sounds when debug mode is enabled.
final class SoundManager {
    private let configManager: ConfigManager
    private var sounds: [String: SystemSoundID] = [:]

    init(configManager: ConfigManager) {
        self.configManager = configManager
    }

    func start() {
        // Pre-load common sounds (using system sound IDs)
    }

    func stop() {
        for (_, soundId) in sounds {
            AudioServicesDisposeSystemSoundID(soundId)
        }
        sounds.removeAll()
    }

    // MARK: - Play sound

    func playSound(_ name: String) -> Bool {
        guard configManager.isDebug() else { return false }

        // Map sound names to system sound IDs
        let soundId = systemSoundId(for: name)
        if soundId > 0 {
            AudioServicesPlaySystemSound(SystemSoundID(soundId))
            return true
        }
        return false
    }

    func playLocationRecorded() {
        guard configManager.isDebug() else { return }
        AudioServicesPlaySystemSound(1057) // Tink sound
    }

    func playMotionChange(isMoving: Bool) {
        guard configManager.isDebug() else { return }
        if isMoving {
            AudioServicesPlaySystemSound(1113) // Begin recording
        } else {
            AudioServicesPlaySystemSound(1114) // End recording
        }
    }

    func playGeofence(action: String) {
        guard configManager.isDebug() else { return }
        switch action {
        case "ENTER":
            AudioServicesPlaySystemSound(1025) // Short beep
        case "EXIT":
            AudioServicesPlaySystemSound(1023) // Long beep
        case "DWELL":
            AudioServicesPlaySystemSound(1054) // Tweet
        default:
            break
        }
    }

    func playHttpResult(success: Bool) {
        guard configManager.isDebug() else { return }
        if success {
            AudioServicesPlaySystemSound(1001) // Success chime
        } else {
            AudioServicesPlaySystemSound(1073) // Error tone
        }
    }

    // MARK: - Helpers

    private func systemSoundId(for name: String) -> Int {
        switch name.lowercased() {
        case "location": return 1057
        case "motion_start": return 1113
        case "motion_stop": return 1114
        case "geofence_enter": return 1025
        case "geofence_exit": return 1023
        case "geofence_dwell": return 1054
        case "http_success": return 1001
        case "http_failure": return 1073
        case "error": return 1073
        default: return 0
        }
    }
}
