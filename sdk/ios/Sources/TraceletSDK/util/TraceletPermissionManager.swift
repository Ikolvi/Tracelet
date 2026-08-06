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

    /// Config source for `disableLocationAuthorizationAlert` (#304).
    ///
    /// Injected by `TraceletSdk` rather than constructed here: `ConfigManager`
    /// is not a singleton, and this manager must read the *same* instance the
    /// SDK applies `setConfig` to. Left `nil` the flag simply does not apply, so
    /// a standalone permission manager keeps prompting as before.
    public weak var configManager: ConfigManager?

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
    public func requestPermission(requestAlways: Bool = false, result: @escaping PermissionCallback) {
        let current = getAuthorizationStatus()

        // #304: honour `disableLocationAuthorizationAlert`. The flag was
        // documented, plumbed all the way to ConfigManager, and then never read
        // — every request path below presented the system prompt regardless, so
        // apps that wanted to own their own pre-permission UX could not suppress
        // it. Report the current status instead of prompting, which is what a
        // caller that has opted out of the alert needs in order to decide
        // whether to route the user to Settings itself.
        if configManager?.getDisableLocationAuthorizationAlert() == true {
            TraceletLog.debug(
                "permission: request suppressed — disableLocationAuthorizationAlert is on "
                    + "(status=\(current))"
            )
            result(current)
            return
        }

        switch current {
        case 0: // notDetermined
            // If the permission is notDetermined, the app was either just installed or 
            // permissions were reset in Settings. We must clear the "already asked" flag.
            UserDefaults.standard.set(false, forKey: "TraceletHasRequestedAlways")
            statusBeforeRequest = current
            pendingResult = result
            if requestAlways {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
        case 2: // whenInUse → upgrade to Always
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "TraceletHasRequestedAlways") {
                // Already asked before. iOS will suppress the prompt.
                // Return immediately so the Dart side can redirect to Settings.
                result(current)
            } else {
                defaults.set(true, forKey: "TraceletHasRequestedAlways")
                statusBeforeRequest = current
                pendingResult = result
                locationManager.requestAlwaysAuthorization()
                
                // Fallback: If iOS 13+ defers the prompt, locationManagerDidChangeAuthorization
                // may never fire with a new status. Start a timer to resolve anyway.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self = self, let pending = self.pendingResult else { return }
                    // If the callback hasn't resolved after 1.5s, the prompt was deferred or ignored.
                    self.pendingResult = nil
                    self.statusBeforeRequest = nil
                    pending(self.getAuthorizationStatus())
                }
            }
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
            // iOS 13+ may defer the Always prompt entirely and keep the status
            // as whenInUse. If we just return here, the pendingResult might
            // hang forever. We'll start a 1-second fallback timer when we 
            // request the upgrade.
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
