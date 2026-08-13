import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The foreign background FlutterEngine, created by the plugin that actually
/// creates one in the field (#364, #371).
///
/// `FirebaseMessaging.onBackgroundMessage()` does more than remember a handler:
/// the native side stores the callback handles and immediately calls
/// `FlutterFirebaseMessagingBackgroundService.startBackgroundIsolate()`, which
/// constructs a second `FlutterEngine` in this process. Flutter's plugin
/// auto-registration attaches Tracelet to it, and the service holds it for the
/// rest of the process — so it is still attached when the app is swiped from
/// recents. That surviving engine is the precondition for #371's failing
/// branch, and it is why the reporter sees the bug only on runs where a
/// background message landed.
///
/// A real app calls this from `main()`. The example arms it on demand instead,
/// so every other issue card keeps running against the ordinary
/// one-engine topology — but arming is **sticky**: the handle the plugin
/// persists is how [restoreIfArmed] knows to re-register on the next launch,
/// which is what makes the swipe-kill test repeatable without touching the UI
/// first.
///
/// No Firebase project configuration is involved. `onBackgroundMessage` runs
/// through a stub platform instance, so no `Firebase.initializeApp()`, no
/// `google-services.json`, and no network are needed to get the engine — this
/// is the plugin's own code path, not a stand-in for it.
class ForeignFcmEngine {
  ForeignFcmEngine._();

  static const _debug = MethodChannel('com.tracelet/debug');

  static bool _registered = false;

  /// Whether this isolate has registered the handler in this session.
  static bool get registeredInThisSession => _registered;

  /// Registers the FCM background handler, creating the foreign engine.
  ///
  /// Returns null on success, or a human-readable reason it could not run.
  static Future<String?> arm() async {
    if (!Platform.isAndroid) {
      return 'firebase_messaging only creates a background FlutterEngine on '
          'Android; there is no foreign-engine path to arm here.';
    }
    if (_registered) return null;
    try {
      FirebaseMessaging.onBackgroundMessage(
        traceletExampleFcmBackgroundHandler,
      );
      _registered = true;
      return null;
    } on Object catch (e) {
      return '$e';
    }
  }

  /// Re-registers when a previous session armed it, so the foreign engine is
  /// back before the app is swiped away again.
  ///
  /// Reads the handle firebase_messaging itself persisted rather than a flag of
  /// our own: that is the same state the plugin consults, so "armed" cannot
  /// drift from "the plugin will build an engine".
  static Future<void> restoreIfArmed() async {
    if (!Platform.isAndroid) return;
    try {
      final state = await _debug.invokeMapMethod<String, dynamic>(
        'debugIssue371FanOutState',
      );
      if (state?['foreignEngineArmed'] == true) {
        await arm();
      }
    } on PlatformException catch (e) {
      debugPrint('[#371] could not read the armed flag: ${e.message}');
    }
  }

  /// Clears the persisted handles, returning the example app to a single
  /// engine on the next launch.
  static Future<void> disarm() async {
    if (!Platform.isAndroid) return;
    await _debug.invokeMethod<void>('debugIssue371DisarmForeignEngine');
    _registered = false;
  }
}

/// The app-side background message handler.
///
/// Never invoked by the example — the repro spawns the engine without a
/// RemoteMessage — but it must exist and be a top-level entry point, because
/// registering it is what creates the engine.
@pragma('vm:entry-point')
Future<void> traceletExampleFcmBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM background] message ${message.messageId}');
}
