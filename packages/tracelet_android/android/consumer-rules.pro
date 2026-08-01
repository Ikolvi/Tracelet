# Tracelet Android Plugin — ProGuard/R8 Consumer Rules
# These rules are automatically applied to host apps using this plugin.
# Only keep classes that must survive shrinking (manifest-referenced, reflection).

# Keep the plugin entry point (Flutter engine looks this up)
-keep class com.ikolvi.tracelet.flutter.TraceletAndroidPlugin { *; }

# Keep BuildConfig (required for AGP 8.5+)
-keep class com.ikolvi.tracelet.flutter.BuildConfig { *; }

# Keep services, receivers, and providers referenced in AndroidManifest.xml
-keep class com.ikolvi.tracelet.sdk.service.LocationService { *; }
-keep class com.ikolvi.tracelet.flutter.service.HeadlessTaskService { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.BootReceiver { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.PeriodicAlarmReceiver { *; }
-keep class com.ikolvi.tracelet.flutter.TraceletStartupProvider { *; }

# Keep the public SDK API surface (used via reflection by Pigeon/MethodChannel)
-keep class com.ikolvi.tracelet.sdk.TraceletSdk { *; }
-keep class com.ikolvi.tracelet.sdk.TraceletEventSender { *; }
-keep class com.ikolvi.tracelet.sdk.TraceletListener { *; }

# Bootstrap / cold-boot recovery (must survive R8 full mode)
-keep class com.ikolvi.tracelet.sdk.TraceletBootstrap { *; }
-keep class com.ikolvi.tracelet.sdk.ListenerEventSender { *; }
-keep class com.ikolvi.tracelet.sdk.HeadlessDispatcher { *; }

# Kotlin interface default method implementations
-keep class com.ikolvi.tracelet.sdk.TraceletListener$DefaultImpls { *; }

# Keep Pigeon-generated API classes (Flutter ↔ Native bridge)
-keep class com.ikolvi.tracelet.** { *; }
-keep class com.ikolvi.tracelet.flutter.TraceletHostApiImpl { *; }

# Keep model classes used in Pigeon serialization
-keep class com.ikolvi.tracelet.sdk.model.** { *; }

# SQLCipher (optional — only applied if present on classpath)
-dontwarn net.zetetic.database.**
-keep class net.zetetic.database.** { *; }

# Play Integrity (optional — only applied if present on classpath)
-dontwarn com.google.android.play.core.integrity.**

# GMS availability probe (TraceletServices.isGmsAvailable).
#
# The probe resolves GoogleApiAvailability reflectively so play-services-base
# stays a soft dependency. R8 rewrites the Class.forName string literal to the
# renamed class but does NOT rewrite the getMethod("getInstance") argument, so
# without this rule the lookup throws NoSuchMethodException in every minified
# release build. The SDK then wrongly concludes Play services is absent and
# drops to the AOSP fallback (raw LocationManager, coarse NETWORK_PROVIDER
# fixes, deprecated addProximityAlert, no activity recognition).
-keep class com.google.android.gms.common.GoogleApiAvailability { *; }

# Security-crypto (optional — only needed with SQLCipher)
-dontwarn androidx.security.crypto.**

# Keep Kotlin metadata for interfaces used via reflection
-keepattributes *Annotation*

# Explicitly keep Pigeon interfaces, codecs, and generated objects
-keep interface com.ikolvi.tracelet.TraceletHostApi { *; }
-keep interface com.ikolvi.tracelet.TraceletEventApi { *; }
-keep class com.ikolvi.tracelet.TraceletHostApi$* { *; }
-keep class com.ikolvi.tracelet.TraceletEventApi$* { *; }
-keep class com.ikolvi.tracelet.TraceletApiPigeonCodec { *; }
-keep class com.ikolvi.tracelet.TraceletApi_gKt { *; }
-keep class com.ikolvi.tracelet.TraceletApiKt { *; }
-keep class com.ikolvi.tracelet.Tl** { *; }


# Keep JNA classes (required by uniffi-rs bindings)
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { *; }
-keep class uniffi.tracelet_core.** { *; }

-dontwarn java.awt.**
-dontwarn com.sun.jna.**
