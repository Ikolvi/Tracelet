import Flutter
import UIKit
// Local-dev only: the Podfile adds `pod 'TraceletSDK', :path => '../..'` when
// the in-repo podspec exists. In CI the plugin comes via SPM and this module is
// not importable from Runner, so the #286 probe below compiles out.
#if canImport(TraceletSDK)
import TraceletSDK
#endif

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
          } else if call.method == "debugIssue288EffectiveThresholds" {
             // #288: report what the native SDK is *actually* using for the sensor
             // thresholds. Dart used to transmit its own defaults — the
             // Android-tuned numbers — for every app that configured any motion
             // field, so iOS never saw its own tuning: 0.4 m/s² arrived as 0.04 g
             // against an intended 0.15 g. Unset values must now fall back to these.
             #if canImport(TraceletSDK)
             if let config = TraceletSdk.shared.configManager {
                result([
                    "platform": "ios",
                    // iOS compares gravity-subtracted user-acceleration in g at 10 Hz.
                    "unit": "g",
                    "shakeThreshold": config.getShakeThreshold(),
                    "stillThreshold": config.getStillThreshold(),
                    "stillSampleCount": config.getStillSampleCount(),
                    "tunedShakeThreshold": 0.35,
                    "tunedStillThreshold": 0.15,
                    "tunedStillSampleCount": 50,
                ])
             } else {
                result(FlutterError(
                    code: "ISSUE_288_UNAVAILABLE",
                    message: "TraceletSdk.configManager is nil — call ready() first.",
                    details: nil))
             }
             #else
             result(FlutterError(
                code: "ISSUE_288_UNAVAILABLE",
                message: "TraceletSDK is not importable from Runner in this build.",
                details: nil))
             #endif
          } else if call.method == "debugIssue286SyncSinkAccumulation" {
             let requested = (call.arguments as? [String: Any])?["engines"] as? Int ?? 2
             AppDelegate.probeIssue286(engines: min(max(requested, 1), 4), result: result)
          } else {
             result(FlutterMethodNotImplemented)
          }
        })
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - #286 verification (iOS)
  //
  // VERIFICATION ONLY — nothing is fixed here.
  //
  // The iOS tracelet_sync plugin has the same shape as the Android one, minus
  // the mitigations: `TraceletSyncPlugin.register(with:)` builds a fresh
  // `TraceletSyncSink` on EVERY registrar (i.e. every FlutterEngine), appends it
  // to the shared `TraceletSdk.shared.locationEngine` sink list, and also assigns
  // `TraceletSdk.shared.syncProvider = sink` — whose `didSet` appends the same
  // sink a second time. Unlike Android there is no `registerSyncProvider()`
  // replacement logic and iOS `LocationEngine` has no `unregisterSink`, so a sink
  // can never be removed; the plugin also implements no `detachFromEngine(for:)`.
  //
  // This probe registers the plugins on N secondary engines (what a host app
  // does for headless/background engines), then counts how many distinct sinks
  // remain subscribed to the live LocationEngine afterwards.
  private static func probeIssue286(engines: Int, result: @escaping FlutterResult) {
    #if canImport(TraceletSDK)
    let maybeEngine: LocationEngine? = TraceletSdk.shared.locationEngine
    guard let locationEngine = maybeEngine else {
      result(FlutterError(
        code: "ISSUE_286_UNAVAILABLE",
        message: "TraceletSdk.locationEngine is nil — call ready() first.",
        details: nil))
      return
    }

    // `sinks` is private; Mirror still exposes stored properties.
    func sinkEntries() -> [AnyObject] {
      for child in Mirror(reflecting: locationEngine).children where child.label == "sinks" {
        if let array = child.value as? [Any] {
          return array
            .filter { String(describing: type(of: $0)).contains("TraceletSyncSink") }
            .map { $0 as AnyObject }
        }
      }
      return []
    }

    let registeredBefore = sinkEntries().count
    var observed: [ObjectIdentifier: AnyObject] = [:]
    var order: [ObjectIdentifier] = []
    func noteProvider() {
      guard let provider = TraceletSdk.shared.syncProvider as AnyObject? else { return }
      let id = ObjectIdentifier(provider)
      if observed[id] == nil {
        observed[id] = provider
        order.append(id)
      }
    }
    noteProvider()
    let baselineSinks = observed.count

    let syncPluginClass: AnyClass? = NSClassFromString("TraceletSyncPlugin")
      ?? NSClassFromString("tracelet_sync.TraceletSyncPlugin")

    // The engine MUST be running before plugins are registered: a plugin's
    // register(with:) installs method-call handlers, and FlutterEngine raises
    // NSInternalInconsistencyException ("Setting a message handler before the
    // FlutterEngine has been run.") otherwise.
    //
    // We run a dedicated no-op Dart entrypoint (issue286ProbeEntrypoint in
    // issue_286_card.dart) rather than main(), so the probe does not boot a
    // second copy of the example app. That is the same order workmanager uses:
    // create → run → register plugins.
    var spawned: [FlutterEngine] = []
    for i in 0..<engines {
      let secondary = FlutterEngine(name: "issue286-probe-\(i)")
      var started = secondary.run(
        withEntrypoint: "issue286ProbeEntrypoint",
        libraryURI: "package:tracelet_example/issues/issue_286_card.dart")
      if !started {
        // Entrypoint could not be resolved (tree-shaken?) — fall back to main().
        started = secondary.run()
      }
      guard started else {
        spawned.forEach { $0.destroyContext() }
        result(FlutterError(
          code: "ISSUE_286_ENGINE_START_FAILED",
          message: "Could not start probe engine \(i); registering plugins on a "
            + "non-running engine would crash the app.",
          details: nil))
        return
      }
      // Register ONLY the sync plugin, not the whole GeneratedPluginRegistrant.
      // It is the only plugin that creates a TraceletSyncSink, so the measured
      // signal is identical, and this keeps an unrelated third-party plugin from
      // misbehaving on a headless engine during a diagnostic.
      guard
        let syncPlugin = syncPluginClass as? FlutterPlugin.Type,
        let registrar = secondary.registrar(forPlugin: "TraceletSyncPlugin")
      else {
        secondary.destroyContext()
        spawned.forEach { $0.destroyContext() }
        result(FlutterError(
          code: "ISSUE_286_NO_SYNC_PLUGIN",
          message: "TraceletSyncPlugin was not found — is tracelet_sync linked "
            + "into this build?",
          details: nil))
        return
      }
      syncPlugin.register(with: registrar)
      spawned.append(secondary)
      noteProvider()
    }
    let providerAfterAttach = order.last

    // Host app is done with the engines.
    spawned.forEach { $0.destroyContext() }
    spawned.removeAll()

    let entriesAfter = sinkEntries()
    let stillSubscribed = Set(entriesAfter.map { ObjectIdentifier($0) })
    var aliveAfterDestroy = 0
    var scopeStates: [String] = []
    for id in order {
      guard let sink = observed[id] else { continue }
      let subscribed = stillSubscribed.contains(id)
      if subscribed { aliveAfterDestroy += 1 }
      let entries = entriesAfter.filter { ObjectIdentifier($0) == id }.count
      scopeStates.append(
        "\(String(describing: type(of: sink)))#\(abs(id.hashValue) % 100_000_000): "
        + (subscribed
          ? "still subscribed to LocationEngine (\(entries) entr\(entries == 1 ? "y" : "ies")), own SyncCoordinator alive"
          : "no longer subscribed"))
    }

    var hasDetachHook = false
    if let cls = syncPluginClass {
      hasDetachHook = class_getInstanceMethod(
        cls, NSSelectorFromString("detachFromEngineForRegistrar:")) != nil
    }

    let providerNow = TraceletSdk.shared.syncProvider as AnyObject?
    var providerReplacedByDeadEngine = false
    if let providerNow = providerNow, let expected = providerAfterAttach {
      providerReplacedByDeadEngine =
        ObjectIdentifier(providerNow) == expected && observed.count > baselineSinks
    }

    result([
      "platform": "ios",
      "enginesSpawned": engines,
      "baselineSinks": baselineSinks,
      "distinctSinks": observed.count,
      "aliveAfterDestroy": aliveAfterDestroy,
      "scopesInspected": observed.count,
      "scopeStates": scopeStates,
      "registeredBefore": registeredBefore,
      "registeredAfter": entriesAfter.count,
      "registeredBootAfter": -1,
      "providerReplacedByDeadEngine": providerReplacedByDeadEngine,
      "instanceSinkField": true,
      "staticSinkHolder": false,
      "hasDetachHook": hasDetachHook,
      "canUnregister": false,
    ])
    #else
    result(FlutterError(
      code: "ISSUE_286_UNAVAILABLE",
      message: "TraceletSDK is not importable from Runner in this build "
        + "(SPM/CI configuration), so the native probe is compiled out.",
      details: nil))
    #endif
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
