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
public class TraceletIosPlugin: NSObject, FlutterPlugin, DartSyncInterceptor {

    /// Timeout for Dart callback round-trips (headers refresh, sync body).
    public static var dartCallbackTimeout: TimeInterval = 10.0
    
    // Whether a foreground custom sync body builder is registered in Dart.
    // If false, we immediately return the sentinel instead of waiting for a 
    // Dart timeout, preventing the sync from aborting when suspended.
    public static var hasCustomSyncBodyBuilder = false

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
    private var syncBodyChannel: FlutterMethodChannel!

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
            
            // Set up sync body channel
            instance.syncBodyChannel = FlutterMethodChannel(name: "com.tracelet/sync_body", binaryMessenger: registrar.messenger())
            
            instance.syncBodyChannel.setMethodCallHandler { call, result in
                if call.method == "setHasCustomSyncBodyBuilder" {
                    if let hasBuilder = call.arguments as? Bool {
                        TraceletIosPlugin.hasCustomSyncBodyBuilder = hasBuilder
                    }
                    result(nil)
                } else {
                    result(FlutterMethodNotImplemented)
                }
            }
            
            TraceletSdk.shared.dartSyncInterceptor = instance

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

            TraceletSdk.shared.logger.debug("register: primary instance — SDK initialized, callbacks wired")
        } else {
            TraceletSdk.shared.logger.debug("register: secondary instance — skipping SDK init & callback wiring")
        }

        // Register Pigeon-generated type-safe API on EVERY engine so host
        // API calls from background isolates (e.g. setDynamicHeaders) still work.
        let hostApiHeadless = isPrimary ? instance.headlessRunner! : HeadlessRunner()
        let hostApi = TraceletHostApiImpl(headlessRunner: hostApiHeadless)
        TraceletHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: hostApi)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        TraceletSdk.shared.logger.debug("detachFromEngine")
        TraceletHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)

        if TraceletIosPlugin.primaryInstance === self {
            TraceletIosPlugin.primaryInstance = nil

            sdk.destroyAll()
            TraceletSdk.shared.logger.debug("detachFromEngine: primary instance — destroyAll() called")
        } else {
            TraceletSdk.shared.logger.debug("detachFromEngine: secondary instance — skipping SDK destroy")
        }
    }

    // MARK: - UIApplicationDelegate (killed-state relaunch)

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]? = nil
    ) -> Bool {
        let launchedForLocation = (launchOptions?[UIApplication.LaunchOptionsKey.location] as? Bool) == true
        TraceletSdk.shared.logger.debug("didFinishLaunchingWithOptions: launchedForLocation=\(launchedForLocation)")
        if launchedForLocation {
            TraceletSdk.shared.logger.debug("Killed-state relaunch detected — calling autoResumeTracking()")
            sdk.autoResumeTracking()
        }
        return true
    }

    // MARK: - UIApplicationDelegate (will terminate)

    public func applicationWillTerminate(_ application: UIApplication) {
        TraceletSdk.shared.logger.debug("applicationWillTerminate: ensuring significant location monitoring persists")
        sdk.onAppWillTerminate()
    }

    // MARK: - DartSyncInterceptor

    public func requestTokenRefresh() -> Bool {
        if TraceletIosPlugin.primaryInstance == nil && !headlessRunner.isRegistered() {
            return false
        }
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        DispatchQueue.main.async {
            self.syncBodyChannel.invokeMethod("requestTokenRefresh", arguments: nil) { result in
                if let res = result as? Bool {
                    success = res
                }
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + TraceletIosPlugin.dartCallbackTimeout)
        return success
    }

    public func requestFreshHeaders() -> Bool {
        if TraceletIosPlugin.primaryInstance == nil {
            if !headlessRunner.isRegistered() { return false }
            TraceletSdk.shared.logger.debug("requestFreshHeaders: primary instance nil, routing to HeadlessRunner")
            return headlessRunner.requestHeadersRefresh(timeout: TraceletIosPlugin.dartCallbackTimeout)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        DispatchQueue.main.async {
            self.syncBodyChannel.invokeMethod("requestFreshHeaders", arguments: nil) { result in
                if let res = result as? Bool {
                    success = res
                }
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + TraceletIosPlugin.dartCallbackTimeout)
        return success
    }

    /// Returns the custom JSON body, ``traceletNoSyncBodyBuilderSentinel`` when
    /// no builder is registered, or `nil` when a registered builder failed
    /// (timed out or threw). Must never return an error object as a body —
    /// that was the Issue #125 bug.
    public func requestSyncBody(locations: [[String: Any]]) -> String? {
        if !TraceletIosPlugin.hasCustomSyncBodyBuilder {
            // No foreground builder registered in Dart. Return the sentinel
            // immediately to bypass the 10-second channel timeout and ensure
            // the sync falls back to the default payload without aborting.
            //
            // #340: this used to return in silence, so a device posting the
            // default payload when the app had registered a builder left no
            // trace of which link had failed — this branch and a nil
            // `dartSyncInterceptor` produced byte-identical evidence.
            //
            // Deliberately TraceletLog, not `TraceletSdk.shared.logger`: that
            // property is `TraceletLogger!` and traps when read before
            // `initialize()`. This branch must stay reachable in that state —
            // returning the sentinel *immediately, touching nothing* is the #125
            // guarantee, and routing the log through the SDK would put a crash in
            // its way. TraceletLog falls back to NSLog until a logger is attached.
            // The Android counterpart broke its own regression test this way.
            //
            // #340: before falling through to the default payload, try the
            // *headless* builder. This flag only ever reflects the foreground
            // isolate, and a process relaunched in the background — iOS's
            // `resume=true` session, launched by a location event with nobody
            // driving the UI — never runs the app code that calls
            // `setSyncBodyBuilder`, so it is false there even when the app
            // registered `registerHeadlessSyncBodyBuilder` at startup. This
            // branch then returned before the `primaryInstance == nil` routing
            // below could be reached, and the device posted the SDK default
            // while the same app on Android posted its own body. Android's
            // engine-less process is covered by HeadlessSyncInterceptor,
            // installed from a ContentProvider at process start; iOS has no
            // equivalent seam, so the fallback belongs here.
            //
            // Guarded so the #125 promise survives: a UserDefaults read only,
            // skipped entirely on the main thread because
            // requestCustomSyncBody answers nil there (it would deadlock), and
            // nil means "abort the sync" — a worse outcome than the default
            // payload this branch exists to permit.
            if let runner = headlessRunner, !Thread.isMainThread,
                runner.isSyncBodyBuilderRegistered()
            {
                TraceletLog.debug(
                    "requestSyncBody: no foreground builder — routing to the headless builder")
                return runner.requestCustomSyncBody(
                    locations,
                    timeout: TraceletIosPlugin.dartCallbackTimeout,
                    telematics: TraceletSdk.shared.getTelematicsForCustomBuilder(),
                )
            }

            TraceletLog.debug(
                "requestSyncBody: no custom sync body builder registered "
                    + "(setSyncBodyBuilder never reached native) — using the default payload")
            return traceletNoSyncBodyBuilderSentinel
        }

        if TraceletIosPlugin.primaryInstance == nil {
            // Background/killed: no foreground engine. Route to the headless
            // runner, which returns the sentinel when no headless sync-body
            // builder is registered and `nil` only when a registered one fails.
            guard let runner = headlessRunner else { return traceletNoSyncBodyBuilderSentinel }
            TraceletSdk.shared.logger.debug("requestSyncBody: primary instance nil, routing to HeadlessRunner")
            return runner.requestCustomSyncBody(
                locations,
                timeout: TraceletIosPlugin.dartCallbackTimeout,
                telematics: TraceletSdk.shared.getTelematicsForCustomBuilder(),
            )
        }
        let semaphore = DispatchSemaphore(value: 0)
        var body: String? = nil
        // #214: deliver telematics alongside locations so custom-schema builders
        // can include driving/crash events. Map shape {locations, telematics};
        // the Dart handler stays backward-compatible with the old bare-List arg.
        // telematics is empty unless syncTelematics is enabled (gated in the SDK).
        let args: [String: Any] = [
            "locations": locations,
            "telematics": TraceletSdk.shared.getTelematicsForCustomBuilder(),
        ]
        DispatchQueue.main.async {
            self.syncBodyChannel.invokeMethod("buildSyncBody", arguments: args) { result in
                switch result {
                case let res as String:
                    // Real JSON body or the no-builder sentinel — passed through
                    // verbatim for the sync provider to interpret.
                    body = res
                case nil:
                    // Dart returned null: a registered builder threw → abort.
                    TraceletSdk.shared.logger.error("requestSyncBody: builder returned null; aborting sync")
                    body = nil
                default:
                    // FlutterMethodNotImplemented (no Dart handler = no builder)
                    // or a channel error → treat as "no builder", fall through.
                    body = traceletNoSyncBodyBuilderSentinel
                }
                semaphore.signal()
            }
        }
        let res = semaphore.wait(timeout: .now() + TraceletIosPlugin.dartCallbackTimeout)
        if res == .timedOut {
            // The foreground Dart isolate didn't answer in time. This usually
            // means the app is backgrounded/suspended when the auto-sync fires —
            // it is NOT the same as "the builder ran and failed". So fall back to
            // the headless runner (its own engine, built for background) instead
            // of aborting the sync outright (Issue #134).
            TraceletSdk.shared.logger.error("requestSyncBody: timed out; falling back to headless")
            guard let runner = headlessRunner else { return nil }
            let headlessBody = runner.requestCustomSyncBody(
                locations,
                timeout: TraceletIosPlugin.dartCallbackTimeout,
                telematics: TraceletSdk.shared.getTelematicsForCustomBuilder(),
            )
            // Sentinel = no headless builder registered. Don't post the default
            // body when a foreground custom builder exists — abort (nil) and let
            // the batch retry on the next sync.
            return headlessBody == traceletNoSyncBodyBuilderSentinel ? nil : headlessBody
        }
        return body
    }
}
