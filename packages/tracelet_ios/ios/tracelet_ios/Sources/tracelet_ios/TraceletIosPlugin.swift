import Flutter
import UIKit
#if canImport(TraceletSDK)
import TraceletSDK
#endif

/// TraceletIosPlugin — Thin Flutter bridge that delegates all work to ``TraceletSdk``.
///
/// This plugin owns only Flutter-specific concerns:
/// - ``PluginEventDispatcher`` (Pigeon FlutterApi → Dart)
/// - ``HeadlessRunner`` (background Dart execution)
/// - Pigeon HostApi dispatch
/// - Killed-state auto-resume via `UIApplicationDelegate`
///
/// All tracking logic lives in the standalone ``TraceletSdk`` (SPM package).
public class TraceletIosPlugin: NSObject, FlutterPlugin {

    /// Timeout for Dart callback round-trips (headers refresh, sync body).
    private static let dartCallbackTimeout: TimeInterval = 10.0

    /// Reference to the primary (foreground) plugin instance.
    ///
    /// When a background FlutterEngine is created (e.g., by
    /// FirebaseMessaging.onBackgroundMessage or any other plugin that
    /// spawns a background isolate), ``GeneratedPluginRegistrant``
    /// registers all plugins on that engine, triggering a second
    /// ``register(with:)`` on a NEW instance. That instance
    /// must NOT overwrite the SDK's event sender or callbacks —
    /// those belong to the foreground engine's messenger.
    ///
    /// `internal` (not `private`) so `@testable import` can verify the guard
    /// in PluginSecondaryEngineGuardTests.
    static var primaryInstance: TraceletIosPlugin?

    private var eventDispatcher: PluginEventDispatcher!
    private var headlessRunner: HeadlessRunner!

    /// Shorthand for the SDK singleton.
    private var sdk: TraceletSdk { TraceletSdk.shared }

    // MARK: - FlutterPlugin registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TraceletIosPlugin()

        // ── Primary instance guard ───────────────────────────────────────
        // When a background FlutterEngine is created (by Firebase background
        // messaging, WorkManager, or any other plugin that spawns a background
        // isolate), GeneratedPluginRegistrant registers ALL plugins on that
        // engine, calling register(with:) with a NEW instance.
        //
        // That secondary instance's messenger is connected to the BACKGROUND
        // Dart isolate, not the main one where the user's event listeners
        // live. If we let it overwrite the SDK event sender or re-initialize
        // subsystems, all events get routed to the wrong (short-lived)
        // isolate and Dart callbacks stop firing.
        //
        // Guard: Only the first (primary/foreground) instance — or a
        // replacement after the primary is deallocated — initializes the
        // SDK and wires callbacks. Secondary instances only register the
        // Pigeon HostApi on their own messenger (so host API calls from
        // background isolates still work) but do NOT touch the SDK singleton.
        let isPrimary = primaryInstance == nil
        if isPrimary {
            primaryInstance = instance

            // Flutter-specific event channels
            instance.eventDispatcher = PluginEventDispatcher()
            instance.eventDispatcher.register(messenger: registrar.messenger())

            // Headless runner for background Dart execution
            instance.headlessRunner = HeadlessRunner()

            // Inject Flutter PluginEventDispatcher as the SDK's event sender
            TraceletSdk.shared.setEventSender(instance.eventDispatcher)

            // Initialize SDK subsystems so httpSyncManager (and others) exist
            // before we wire callbacks below. Without this, the optional-chaining
            // assignments (httpSyncManager?.onXxx = ...) silently no-op because
            // httpSyncManager is still nil — it's only created in initialize().
            TraceletSdk.shared.initialize()

            // Set configManager on headless runner AFTER initialize() creates it.
            instance.headlessRunner.configManager = TraceletSdk.shared.configManager

            // Register bootstrap factories for killed-state relaunch.
            // Wire headlessFallback so any future consumer of the factory
            // (e.g. SDK background bootstrap) gets a properly routed dispatcher.
            TraceletBootstrapIOS.eventSenderFactory = {
                let dispatcher = PluginEventDispatcher()
                let runner = HeadlessRunner()
                dispatcher.headlessFallback = { eventName, eventData in
                    runner.dispatchEvent(["name": eventName, "event": eventData])
                }
                return dispatcher
            }
            TraceletBootstrapIOS.headlessDispatcherFactory = { HeadlessRunner() }

            // Wire headless fallback — when no Dart UI listener, route to HeadlessRunner
            instance.eventDispatcher.headlessFallback = { [weak instance] eventName, eventData in
                guard let runner = instance?.headlessRunner else { return }
                runner.dispatchEvent(["name": eventName, "event": eventData])
            }

            registrar.addApplicationDelegate(instance)

            NSLog("[Tracelet] register: primary instance — SDK initialized, callbacks wired")
        } else {
            NSLog("[Tracelet] register: secondary instance — skipping SDK init & callback wiring")
        }

        // Register Pigeon-generated type-safe API on EVERY engine so host
        // API calls from background isolates (e.g. setDynamicHeaders) still work.
        let hostApiHeadless = isPrimary ? instance.headlessRunner! : HeadlessRunner()
        let hostApi = TraceletHostApiImpl(headlessRunner: hostApiHeadless)
        TraceletHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: hostApi)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        NSLog("[Tracelet] detachFromEngine")
        TraceletHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)

        if TraceletIosPlugin.primaryInstance === self {
            TraceletIosPlugin.primaryInstance = nil

            sdk.destroyAll()
            NSLog("[Tracelet] detachFromEngine: primary instance — destroyAll() called")
        } else {
            NSLog("[Tracelet] detachFromEngine: secondary instance — skipping SDK destroy")
        }
    }

    // MARK: - UIApplicationDelegate (killed-state relaunch)

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]? = nil
    ) -> Bool {
        let launchedForLocation = (launchOptions?[UIApplication.LaunchOptionsKey.location] as? Bool) == true
        NSLog("[Tracelet] didFinishLaunchingWithOptions: launchedForLocation=\(launchedForLocation)")
        if launchedForLocation {
            NSLog("[Tracelet] Killed-state relaunch detected — calling autoResumeTracking()")
            sdk.autoResumeTracking()
        }
        return true
    }

    // MARK: - UIApplicationDelegate (will terminate)

    public func applicationWillTerminate(_ application: UIApplication) {
        NSLog("[Tracelet] applicationWillTerminate: ensuring significant location monitoring persists")
        sdk.onAppWillTerminate()
    }
}
