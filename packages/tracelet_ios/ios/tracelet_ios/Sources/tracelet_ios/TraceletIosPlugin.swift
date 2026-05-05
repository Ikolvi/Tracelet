import Flutter
import UIKit
import TraceletSDK

/// TraceletIosPlugin — Thin Flutter bridge that delegates all work to ``TraceletSdk``.
///
/// This plugin owns only Flutter-specific concerns:
/// - ``EventDispatcher`` (Pigeon FlutterApi → Dart)
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

    private var eventDispatcher: EventDispatcher!
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
            instance.eventDispatcher = EventDispatcher()
            instance.eventDispatcher.register(messenger: registrar.messenger())

            // Headless runner for background Dart execution
            instance.headlessRunner = HeadlessRunner()

            // Inject Flutter EventDispatcher as the SDK's event sender
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
                let dispatcher = EventDispatcher()
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

            // Wire custom sync body builder → Dart MethodChannel (foreground)
            // Falls back to headless runner when UI engine is not available.
            //
            // NOTE: Uses raw MethodChannel instead of Pigeon because this requires
            // a synchronous native→Dart→native round-trip with a return value.
            // Pigeon's FlutterApi is fire-and-forget and doesn't support return
            // values. See: .github/copilot-instructions.md Golden Rule #2 exception.
            let syncBodyChannel = FlutterMethodChannel(
                name: "com.tracelet/sync_body",
                binaryMessenger: registrar.messenger()
            )
            HttpSyncManager.onBuildCustomSyncBody = { [weak instance] locations in
                // Try foreground engine first
                if !Thread.isMainThread {
                    let semaphore = DispatchSemaphore(value: 0)
                    var result: String? = nil

                    DispatchQueue.main.async {
                        syncBodyChannel.invokeMethod("buildSyncBody", arguments: locations) { response in
                            result = response as? String
                            semaphore.signal()
                        }
                    }

                    let timeout = semaphore.wait(timeout: .now() + dartCallbackTimeout)
                    if timeout == .timedOut {
                        NSLog("[Tracelet] buildSyncBody timed out waiting for Dart response")
                    }
                    if result != nil { return result }
                }

                // Fallback to headless runner
                return instance?.headlessRunner.requestCustomSyncBody(locations, timeout: dartCallbackTimeout)
            }

            // Wire fresh-headers request → foreground MethodChannel, headless fallback
            HttpSyncManager.onRequestFreshHeaders = { [weak instance] in
                // Try foreground engine first
                if !Thread.isMainThread {
                    let semaphore = DispatchSemaphore(value: 0)
                    var refreshed = false

                    DispatchQueue.main.async {
                        syncBodyChannel.invokeMethod("requestFreshHeaders", arguments: nil) { response in
                            refreshed = (response as? Bool) ?? false
                            semaphore.signal()
                        }
                    }

                    let timeout = semaphore.wait(timeout: .now() + dartCallbackTimeout)
                    if timeout == .timedOut {
                        NSLog("[Tracelet] requestFreshHeaders timed out waiting for Dart response")
                    }
                    if refreshed { return }
                }

                // Fallback to headless runner
                _ = instance?.headlessRunner.requestHeadersRefresh(timeout: dartCallbackTimeout)
            }

            // Wire 401 auth refresh → foreground token refresh, headless fallback
            HttpSyncManager.onAuthorizationRequired = { [weak instance] in
                // Try foreground engine first
                if !Thread.isMainThread {
                    let semaphore = DispatchSemaphore(value: 0)
                    var refreshed = false

                    DispatchQueue.main.async {
                        syncBodyChannel.invokeMethod("requestTokenRefresh", arguments: nil) { response in
                            refreshed = (response as? Bool) ?? false
                            semaphore.signal()
                        }
                    }

                    let timeout = semaphore.wait(timeout: .now() + dartCallbackTimeout)
                    if timeout == .timedOut {
                        NSLog("[Tracelet] requestTokenRefresh timed out waiting for Dart response")
                    }
                    if refreshed { return true }
                }

                // Fallback to headless runner
                return instance?.headlessRunner.requestHeadersRefresh(timeout: dartCallbackTimeout) ?? false
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

            // Clear SDK callbacks that reference this engine's MethodChannel
            HttpSyncManager.onAuthorizationRequired = nil
            HttpSyncManager.onRequestFreshHeaders = nil
            HttpSyncManager.onBuildCustomSyncBody = nil

            sdk.destroyAll()
            NSLog("[Tracelet] detachFromEngine: primary instance — SDK callbacks cleared, destroyAll() called")
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
