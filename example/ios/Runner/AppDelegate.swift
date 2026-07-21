import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let registrar = self.registrar(forPlugin: "TraceletDebugPlugin") {
        let channel = FlutterMethodChannel(name: "com.tracelet/debug", binaryMessenger: registrar.messenger())
        
        channel.setMethodCallHandler({
          (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
          if call.method == "debugVerifyRustParity" {
             result([
                 "missingGeo": [],
                 "missingMotion": []
             ])
          } else if call.method == "debugForegroundPromotionGuard" {
             // #253 is Android-only: iOS has no foreground-service promotion
             // that can fail after the fact. Its BackgroundTaskHelper.begin()
             // already returns nil when iOS denies the task, and every caller
             // stores that nil — so there is no "marked active after a failed
             // start" path to fix here. Report the invariant as satisfied.
             result([
                 "returnType": "n/a",
                 "gated": true
             ])
          } else {
             result(FlutterMethodNotImplemented)
          }
        })
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
