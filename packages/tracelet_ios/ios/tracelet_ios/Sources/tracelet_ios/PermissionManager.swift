import CoreLocation
import Flutter
import Foundation
import UIKit

/// Pure permission primitives — **no custom dialogs**.
///
/// Status codes match the Dart `AuthorizationStatus` enum:
///
/// | Code | Dart name        | Meaning |
/// |------|------------------|---------|
/// | 0    | notDetermined    | Never asked |
/// | 1    | denied           | Denied but can ask again (unused on iOS) |
/// | 2    | whenInUse        | Foreground granted |
/// | 3    | always           | Background granted |
/// | 4    | deniedForever    | Permanently denied — must open Settings |
final class PermissionManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var pendingResult: FlutterResult?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Authorization status (read-only)

    /// Returns the current status without triggering any dialog.
    func getAuthorizationStatus() -> Int {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        switch status {
        case .notDetermined:       return 0  // notDetermined
        case .restricted:          return 4  // deniedForever (MDM / parental)
        case .denied:              return 4  // deniedForever (user disabled in settings)
        case .authorizedWhenInUse: return 2  // whenInUse
        case .authorizedAlways:    return 3  // always
        @unknown default:          return 0
        }
    }

    // MARK: - Async permission request

    /// Triggers the OS permission dialog and resolves `result` with the
    /// actual status AFTER the user responds.
    ///
    /// - notDetermined → requests foreground (When In Use)
    /// - whenInUse → requests background (Always)
    /// - denied/always → returns immediately (no dialog)
    func requestPermission(result: @escaping FlutterResult) {
        let current = getAuthorizationStatus()

        switch current {
        case 0: // notDetermined
            pendingResult = result
            locationManager.requestWhenInUseAuthorization()
        case 2: // whenInUse → upgrade to Always
            pendingResult = result
            locationManager.requestAlwaysAuthorization()
        default:
            // deniedForever (4) or always (3) — no dialog will show
            result(current)
        }
    }

    /// Request temporary full accuracy (iOS 14+).
    /// Returns current status code (this is always synchronous on iOS).
    func requestTemporaryFullAccuracy(purposeKey: String) -> Int {
        if #available(iOS 14.0, *) {
            locationManager.requestTemporaryFullAccuracyAuthorization(
                withPurposeKey: purposeKey
            )
        }
        return getAuthorizationStatus()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let pending = pendingResult else { return }
        pendingResult = nil
        pending(getAuthorizationStatus())
    }

    // MARK: - Power save

    func isPowerSaveMode() -> Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // MARK: - Settings

    func showAppSettings() -> Bool {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return false }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return true
        }
        return false
    }

    func showLocationSettings() -> Bool {
        // On iOS, there's no direct way to open Location Settings.
        // Open app settings instead.
        return showAppSettings()
    }
}
