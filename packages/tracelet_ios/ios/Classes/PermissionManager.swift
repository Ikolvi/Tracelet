import CoreLocation
import Foundation
import UIKit

/// Permission management for location, motion, and battery optimizations.
final class PermissionManager {
    private let locationManager = CLLocationManager()

    // MARK: - Authorization status

    /// Returns: DENIED(0), DENIED_FOREVER(1), WHEN_IN_USE(2), ALWAYS(3)
    func getAuthorizationStatus() -> Int {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        switch status {
        case .notDetermined: return 0
        case .restricted: return 1
        case .denied: return 1
        case .authorizedWhenInUse: return 2
        case .authorizedAlways: return 3
        @unknown default: return 0
        }
    }

    // MARK: - Request permission

    /// Requests location permission. Returns current status code.
    func requestPermission() -> Int {
        let current = getAuthorizationStatus()
        if current == 0 {
            // Not determined — request When In Use first
            locationManager.requestWhenInUseAuthorization()
        } else if current == 2 {
            // When In Use — upgrade to Always
            locationManager.requestAlwaysAuthorization()
        }
        return getAuthorizationStatus()
    }

    /// Request temporary full accuracy (iOS 14+).
    func requestTemporaryFullAccuracy(purposeKey: String) -> Int {
        if #available(iOS 14.0, *) {
            locationManager.requestTemporaryFullAccuracyAuthorization(
                withPurposeKey: purposeKey
            )
        }
        return getAuthorizationStatus()
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
