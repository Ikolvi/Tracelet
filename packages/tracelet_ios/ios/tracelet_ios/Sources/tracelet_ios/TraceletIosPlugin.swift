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

    private var eventDispatcher: EventDispatcher!
    private var headlessRunner: HeadlessRunner!

    /// Shorthand for the SDK singleton.
    private var sdk: TraceletSdk { TraceletSdk.shared }

    // MARK: - FlutterPlugin registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TraceletIosPlugin()

        // Flutter-specific event channels
        instance.eventDispatcher = EventDispatcher()
        instance.eventDispatcher.register(messenger: registrar.messenger())

        // Headless runner for background Dart execution
        instance.headlessRunner = HeadlessRunner()
        instance.headlessRunner.configManager = TraceletSdk.shared.configManager

        // Inject Flutter EventDispatcher as the SDK's event sender
        TraceletSdk.shared.setEventSender(instance.eventDispatcher)

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

        // Wire 401 auth refresh → headless headers callback
        TraceletSdk.shared.httpSyncManager?.onAuthorizationRequired = { [weak instance] in
            instance?.headlessRunner.requestHeadersRefresh(timeout: 10.0) ?? false
        }

        registrar.addApplicationDelegate(instance)

        // Register Pigeon-generated type-safe API
        let hostApi = TraceletHostApiImpl(headlessRunner: instance.headlessRunner)
        TraceletHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: hostApi)
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
