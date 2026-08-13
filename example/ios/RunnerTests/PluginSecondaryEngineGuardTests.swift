import Flutter
import XCTest

@testable import tracelet_ios
@testable import TraceletSDK

// MARK: - Mock Flutter types

/// Minimal mock of `FlutterBinaryMessenger`, accepting all channel
/// registrations without side effects.
private final class MockBinaryMessenger: NSObject, FlutterBinaryMessenger {
    /// Tracks channels that had message handlers registered.
    var registeredChannels: [String] = []

    func send(onChannel channel: String, message: Data?) {}

    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        callback?(nil)
    }

    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection {
        registeredChannels.append(channel)
        return FlutterBinaryMessengerConnection(0)
    }

    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

/// Minimal mock of `FlutterPluginRegistrar`. Returns a
/// ``MockBinaryMessenger`` and records `addApplicationDelegate` calls.
private final class MockPluginRegistrar: NSObject, FlutterPluginRegistrar {
    let mockMessenger = MockBinaryMessenger()
    var applicationDelegates: [FlutterPlugin] = []

    var viewController: UIViewController? { nil }

    func messenger() -> any FlutterBinaryMessenger { mockMessenger }

    func textures() -> any FlutterTextureRegistry {
        fatalError("textures() not expected in guard tests")
    }

    func register(_ factory: any FlutterPlatformViewFactory, withId factoryId: String) {}

    func register(
        _ factory: any FlutterPlatformViewFactory,
        withId factoryId: String,
        gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicy
    ) {}

    func publish(_ value: NSObject) {}

    func addMethodCallDelegate(_ delegate: any FlutterPlugin, channel: FlutterMethodChannel) {}

    func addApplicationDelegate(_ delegate: any FlutterPlugin) {
        applicationDelegates.append(delegate)
    }

    @available(iOS 13.0, *)
    func addSceneDelegate(_ delegate: any FlutterSceneLifeCycleDelegate) {}

    func lookupKey(forAsset asset: String) -> String { asset }

    func lookupKey(forAsset asset: String, fromPackage package: String) -> String { asset }
}

// MARK: - Tests

/// Verifies that when a secondary FlutterEngine registers a new
/// ``TraceletIosPlugin``, the primary instance's SDK event sender,
/// callbacks, and lifecycle delegate are NOT overwritten.
///
/// This is the iOS equivalent of the Android
/// `PluginSecondaryEngineGuardTest.kt`.
final class PluginSecondaryEngineGuardTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset the primary instance before every test so each test
        // starts with a clean slate.
        TraceletIosPlugin.primaryInstance = nil
    }

    override func tearDown() {
        // Clean up static state.
        TraceletIosPlugin.primaryInstance = nil
        super.tearDown()
    }

    // MARK: - Primary instance initialisation

    /// First `register(with:)` must set `primaryInstance` and initialise the SDK.
    func testPrimaryInstance_initializesSDK() {
        let registrar = MockPluginRegistrar()

        TraceletIosPlugin.register(with: registrar)

        // primaryInstance must be set.
        XCTAssertNotNil(
            TraceletIosPlugin.primaryInstance,
            "First register(with:) must set primaryInstance"
        )

        // SDK should have been initialized (configManager created).
        XCTAssertNotNil(
            TraceletSdk.shared.configManager,
            "First register(with:) must call initialize() on the SDK"
        )

        // The event sender should be an EventDispatcher (our Flutter bridge).
        let sender = TraceletSdk.shared.getEventSender()
        XCTAssertTrue(
            sender is EventDispatcher,
            "Event sender should be EventDispatcher after primary registration"
        )
    }

    // MARK: - Secondary does not overwrite event sender

    /// A second `register(with:)` must NOT replace the event sender that
    /// was wired to the primary/foreground engine's BinaryMessenger.
    func testSecondaryInstance_doesNotReplaceEventSender() {
        let primaryRegistrar = MockPluginRegistrar()
        TraceletIosPlugin.register(with: primaryRegistrar)

        // Capture the event sender set by the primary registration.
        let primarySender = TraceletSdk.shared.getEventSender()

        // Simulate a secondary engine registration (e.g., Firebase background isolate).
        let secondaryRegistrar = MockPluginRegistrar()
        TraceletIosPlugin.register(with: secondaryRegistrar)

        // The event sender must still be the primary's dispatcher.
        let currentSender = TraceletSdk.shared.getEventSender()
        XCTAssertTrue(
            primarySender === currentSender,
            "Secondary register(with:) must NOT replace the primary event sender"
        )
    }

    // MARK: - Primary instance identity is preserved

    /// The `primaryInstance` reference must not change when a secondary
    /// engine registers.
    func testPrimaryInstance_survivesSecondaryRegistration() {
        let primaryRegistrar = MockPluginRegistrar()
        TraceletIosPlugin.register(with: primaryRegistrar)

        let capturedPrimary = TraceletIosPlugin.primaryInstance

        // Secondary registration
        let secondaryRegistrar = MockPluginRegistrar()
        TraceletIosPlugin.register(with: secondaryRegistrar)

        XCTAssertTrue(
            TraceletIosPlugin.primaryInstance === capturedPrimary,
            "primaryInstance must not change after secondary register(with:)"
        )
    }

    // MARK: - addApplicationDelegate only for primary

    /// Only the primary instance should be registered as the app delegate.
    func testSecondaryInstance_doesNotAddApplicationDelegate() {
        let primaryRegistrar = MockPluginRegistrar()
        TraceletIosPlugin.register(with: primaryRegistrar)

        XCTAssertEqual(
            primaryRegistrar.applicationDelegates.count, 1,
            "Primary registrar must receive exactly one addApplicationDelegate call"
        )

        let secondaryRegistrar = MockPluginRegistrar()
        TraceletIosPlugin.register(with: secondaryRegistrar)

        XCTAssertEqual(
            secondaryRegistrar.applicationDelegates.count, 0,
            "Secondary registrar must NOT receive addApplicationDelegate"
        )
    }

    // MARK: - Detach must hand delivery back to the headless runner

    /// #364 (iOS half): once the primary engine detaches, its dispatcher must
    /// stop claiming it can deliver.
    ///
    /// `PluginEventDispatcher` decides "can a Flutter engine receive this?" by
    /// whether `eventApi` is non-nil, and `detachFromEngine` left it set — bound
    /// to a messenger whose engine is gone. The SDK keeps that dispatcher as its
    /// event sender and keeps tracking under `stopOnTerminate: false`, so every
    /// subsequent event was posted into a dead engine instead of falling
    /// through to the `HeadlessRunner`, and the registered headless task heard
    /// nothing for the rest of the process.
    func testPrimaryDetach_routesEventsToTheHeadlessFallback() {
        let registrar = MockPluginRegistrar()
        TraceletIosPlugin.register(with: registrar)

        guard let dispatcher = TraceletSdk.shared.getEventSender() as? PluginEventDispatcher else {
            return XCTFail("primary registration must install a PluginEventDispatcher")
        }

        var fellBackTo: [String] = []
        dispatcher.headlessFallback = { eventName, _ in fellBackTo.append(eventName) }

        // While the engine is attached the event belongs to Dart, not the
        // headless task — the fallback must stay out of the way.
        dispatcher.sendLocation(["coords": ["latitude": 1.0, "longitude": 2.0]])
        XCTAssertEqual(
            fellBackTo, [],
            "an attached engine must still receive events directly"
        )

        TraceletIosPlugin.primaryInstance?.detachFromEngine(for: registrar)

        dispatcher.sendLocation(["coords": ["latitude": 1.0, "longitude": 2.0]])
        XCTAssertEqual(
            fellBackTo, ["location"],
            "after detach, events must reach the headless task instead of a dead engine"
        )
    }

    // MARK: - Pigeon HostApi registered on both engines

    /// The Pigeon HostApi must be set up on EVERY engine's messenger so
    /// host API calls from background isolates still work.
    func testPigeonHostApi_registeredOnBothEngines() {
        let primaryRegistrar = MockPluginRegistrar()
        TraceletIosPlugin.register(with: primaryRegistrar)

        let primaryChannels = primaryRegistrar.mockMessenger.registeredChannels

        let secondaryRegistrar = MockPluginRegistrar()
        TraceletIosPlugin.register(with: secondaryRegistrar)

        let secondaryChannels = secondaryRegistrar.mockMessenger.registeredChannels

        // Both messengers must have at least one Pigeon channel registered.
        XCTAssertFalse(
            primaryChannels.isEmpty,
            "Primary messenger must have Pigeon channels registered"
        )
        XCTAssertFalse(
            secondaryChannels.isEmpty,
            "Secondary messenger must have Pigeon channels registered"
        )
    }
}
