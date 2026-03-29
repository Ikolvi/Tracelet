# Tracelet SDK — Consumer ProGuard/R8 Rules
# Only keep what's strictly necessary for runtime.

# Public API surface
-keep class com.ikolvi.tracelet.sdk.TraceletSdk { *; }
-keep class com.ikolvi.tracelet.sdk.TraceletListener { *; }
-keep class com.ikolvi.tracelet.sdk.TraceletEventSender { *; }

# Model classes used in serialization
-keep class com.ikolvi.tracelet.sdk.model.** { *; }

# Manifest-referenced components
-keep class com.ikolvi.tracelet.sdk.service.LocationService { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.** { *; }

# SQLCipher (optional — only applied if present on classpath)
-dontwarn net.zetetic.database.**
-keep class net.zetetic.database.** { *; }

# Play Integrity (optional — only applied if present on classpath)
-dontwarn com.google.android.play.core.integrity.**

# Security-crypto (optional — only needed with SQLCipher)
-dontwarn androidx.security.crypto.**

# WorkManager (needs keep for reflection-based initialization)
-keep class * extends androidx.work.ListenableWorker { *; }
