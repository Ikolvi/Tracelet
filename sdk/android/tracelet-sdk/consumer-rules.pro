# Tracelet SDK — Consumer ProGuard/R8 Rules
# Only keep what's strictly necessary for runtime.

# Public API surface
-keep class com.ikolvi.tracelet.sdk.TraceletSdk { *; }
-keep class com.ikolvi.tracelet.sdk.TraceletListener { *; }
-keep class com.ikolvi.tracelet.sdk.TraceletEventSender { *; }

# Model classes used in serialization
-keep class com.ikolvi.tracelet.sdk.model.** { *; }

# Bootstrap / cold-boot recovery (must survive R8 full mode)
-keep class com.ikolvi.tracelet.sdk.TraceletBootstrap { *; }
-keep class com.ikolvi.tracelet.sdk.ListenerEventSender { *; }
-keep class com.ikolvi.tracelet.sdk.HeadlessDispatcher { *; }

# Kotlin interface default method implementations
-keep class com.ikolvi.tracelet.sdk.TraceletListener$DefaultImpls { *; }

# Manifest-referenced components
-keep class com.ikolvi.tracelet.sdk.service.LocationService { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.** { *; }

# SQLCipher (optional — only applied if present on classpath)
-dontwarn net.zetetic.database.**
-keep class net.zetetic.database.** { *; }

# Play Integrity (optional — only applied if present on classpath)
-dontwarn com.google.android.play.core.integrity.**
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.gms.**

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

# WorkManager (needs keep for reflection-based initialization)
-keep class * extends androidx.work.ListenableWorker { *; }

# Keep JNA classes (required by uniffi-rs bindings)
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { *; }
-keep class uniffi.tracelet_core.** { *; }
-keep class uniffi.tracelet_sync.** { *; }

-dontwarn java.awt.**
-dontwarn com.sun.jna.**
