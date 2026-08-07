import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// On-device verification of the crash-ML chain (#183): AES-256-GCM decrypt of an
/// encrypted forest blob + random-forest tree-walk inference, running through the
/// real Rust core (`CrashModel`) on the device.
///
/// Uses a fixed encrypted blob of a tiny synthetic forest (generated offline) and
/// a deterministic 32-byte key, decrypted natively via the
/// `com.tracelet/debug` → `debugCrashModelPredict` hook (Android example app).
///
/// Run: `flutter test integration_test/crash_model_test.dart -d <android>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const debug = MethodChannel('com.tracelet/debug');

  // Synthetic 2-tree forest over `peak_g`, AES-256-GCM encrypted with the key
  // below ([0x01][nonce:12][ciphertext]). peak_g=3.0 → tree A(>2)=0.9,
  // B(<=5)=0.4 → average 0.65.
  //
  // The declared feature name must be one the SDK can actually supply: the core
  // rejects anything outside its supported set at load (#309), so the old `x0`
  // fixture is no longer a loadable model.
  const blobB64 =
      'AQABAgMEBQYHCAkKCzwgsH6kkbdp6DK1serLCAjivdhT0iZzXlsLhPZuDHOQO0ue0J6cProA1hqI+6USY5V7Bug7otaoWrUQQijP2NzcEfQn//NSCW4x2QaA42rKAtH7TEZPflrTzbLhSt6J0OfaOo7NLaxo+3Jh3i0TVV2APFOHzvQJt3yie+/hjgdi3yBlqOulojRglWqbZuhg7wfYzgRoPbE87TOdEtjosrWip7Ik2aLgJZ5P7Kfz27eXpJOXX6fQUdoAvrSyA6CVyUh8ptc/8fv7anrxktIzvPeJEZQSHzrhxF+htupzZr/WbhH6n7sMIUY6LtRsx3QSDsT23wG/CtKUO0ZWX6atH602spr58b46WxmAAG7QRU4o4O/44a26rYJAckFzfJXWPmQh5BPh8+ImpmEWATy5lI60kWtyeKSSSuVsYNUEf7FJgWSGEDvh3DI7nec=';
  const keyB64 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';

  // The same forest shape, but declaring the feature names an older training
  // notebook exported (`accel_g`/`gyro_dps`/`speed_kmh`). It decrypts and parses
  // cleanly — only the names are wrong — which is exactly the case that used to
  // load "successfully" and then score an all-zero feature vector forever (#309).
  const mismatchedBlobB64 =
      'AQECAwQFBgcICQoLDH7IPLCN4IX0KdFBfUsxi0shJo2h8E9858Ymi0vB0ga2psi5rB7Qifvvx9eN54bUf/2aLpOn/EVTDCY84V5cGC4DD25GzNNnuzAw1h+aTHbVuBIKc9IF0/JWu6RWDNxUS+WjHxXQKGpHz42jC5vaNf62tAv141ehM18Pkq7V/UlGZQldyY+/ABLQ83PQ2O+cbPWmELO9rmIO90MI8zEKM3CaHhezSAcJb6XkoqviSp1RQ75r2qbqDIXoPuAe/w2UwVgv6sOuYBf2oiR+tPX45AxdGqMH6r1ph0wV89XcBQ==';

  test('#183: decrypts + scores the crash model on-device', () async {
    final res = await debug.invokeMapMethod<String, Object?>(
      'debugCrashModelPredict',
      {
        'blob': blobB64,
        'key': keyB64,
        'features': <double>[3],
      },
    );
    expect(res, isNotNull);
    final r = res!;
    expect(r['treeCount'], 2);
    expect(r['proba']! as double, closeTo(0.65, 1e-6));
  });

  test(
    '#183 Phase 2b: loader downloads + verifies sha + decrypts on-device',
    () async {
      // Serve the encrypted blob over loopback; the native loader downloads it,
      // verifies the SHA-256, decrypts (AES-GCM), caches, and scores.
      final blob = base64.decode(blobB64);
      const sha256Hex =
          'df4752e93707f0f685dc8582fac5acaa871a24d015b0c3a1bedc6927479768c2';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.add(blob);
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final res = await debug
          .invokeMapMethod<String, Object?>('debugCrashModelLoad', {
            'url': 'http://127.0.0.1:${server.port}/model.enc',
            'sha256': sha256Hex,
            'key': keyB64,
          });
      expect(res, isNotNull);
      final r = res!;
      expect(r['treeCount'], 2);
      expect(r['proba']! as double, closeTo(0.65, 1e-6));
    },
  );

  test('#183: wrong key fails to decrypt (PlatformException)', () async {
    // All-zero key ≠ the real key → AES-GCM auth fails.
    const wrongKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    await expectLater(
      debug.invokeMapMethod<String, Object?>('debugCrashModelPredict', {
        'blob': blobB64,
        'key': wrongKey,
        'features': <double>[3],
      }),
      throwsA(isA<PlatformException>()),
    );
  });

  test('#309: a model with unsupported feature names is rejected', () async {
    // Decrypts and parses fine; only the feature names are unusable. Loading it
    // must fail so the caller falls back to the rule engine — the alternative is
    // a model that loads, scores an all-zero vector, and (because a probability
    // of 0.0 still satisfies `crashProba >= 0`) holds the detector in ML Replace
    // mode, silently suppressing the g-threshold rule and killing crash
    // detection outright.
    await expectLater(
      debug.invokeMapMethod<String, Object?>('debugCrashModelPredict', {
        'blob': mismatchedBlobB64,
        'key': keyB64,
        'features': <double>[3],
      }),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message ?? '',
          'message',
          contains('accel_g'),
        ),
      ),
    );
  });
}
