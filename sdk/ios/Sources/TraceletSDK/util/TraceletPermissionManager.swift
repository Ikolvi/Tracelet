import CoreLocation
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
public final class TraceletPermissionManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    /// Generic callback type matching FlutterResult / RCTResponseSenderBlock.
    public typealias PermissionCallback = (Any?) -> Void

    private var pendingResult: PermissionCallback?
    /// The status before the permission request — used to detect actual changes
    /// when upgrading from whenInUse → always.
    private var statusBeforeRequest: Int?

    public override init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Authorization status (read-only)

    /// Returns the current status without triggering any dialog.
    public func getAuthorizationStatus() -> Int {
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
    public func requestPermission(result: @escaping PermissionCallback) {
        let current = getAuthorizationStatus()

        switch current {
        case 0: // notDetermined
            statusBeforeRequest = nil
            pendingResult = result
            locationManager.requestWhenInUseAuthorization()
        case 2: // whenInUse → upgrade to Always
            statusBeforeRequest = current
            pendingResult = result
            locationManager.requestAlwaysAuthorization()
        default:
            // deniedForever (4) or always (3) — no dialog will show
            result(current)
        }
    }

    /// Request temporary full accuracy (iOS 14+).
    /// Returns current status code (this is always synchronous on iOS).
    public func requestTemporaryFullAccuracy(purposeKey: String) -> Int {
        if #available(iOS 14.0, *) {
            locationManager.requestTemporaryFullAccuracyAuthorization(
                withPurposeKey: purposeKey
            )
        }
        return getAuthorizationStatus()
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let pending = pendingResult else { return }
        let newStatus = getAuthorizationStatus()

        // When upgrading whenInUse → always, iOS fires an immediate callback
        // with the *unchanged* whenInUse status before showing the dialog.
        // Ignore this spurious callback — only resolve when the status has
        // actually changed from what it was before the request.
        if let before = statusBeforeRequest, newStatus == before {
            return
        }

        pendingResult = nil
        statusBeforeRequest = nil
        pending(newStatus)
    }

    // MARK: - Power save

    public func isPowerSaveMode() -> Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // MARK: - Settings

    public func showAppSettings() -> Bool {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return false }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return true
        }
        return false
    }

    public func showLocationSettings() -> Bool {
        // On iOS, there's no direct way to open Location Settings.
        // Open app settings instead.
        return showAppSettings()
    }
}
