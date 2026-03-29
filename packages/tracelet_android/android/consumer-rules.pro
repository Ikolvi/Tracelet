# Tracelet Android Plugin — ProGuard/R8 Consumer Rules
# These rules are automatically applied to host apps using this plugin.
# Only keep classes that must survive shrinking (manifest-referenced, reflection).

# Keep the plugin entry point (Flutter engine looks this up)
-keep class com.ikolvi.tracelet.flutter.TraceletAndroidPlugin { *; }

# Keep BuildConfig (required for AGP 8.5+)
-keep class com.ikolvi.tracelet.flutter.BuildConfig { *; }

# Keep services and receivers referenced in AndroidManifest.xml
-keep class com.ikolvi.tracelet.sdk.service.LocationService { *; }
-keep class com.ikolvi.tracelet.flutter.service.HeadlessTaskService { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.BootReceiver { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.PeriodicAlarmReceiver { *; }

# Keep the public SDK API surface (used via reflection by Pigeon/MethodChannel)
-keep class com.ikolvi.tracelet.sdk.TraceletSdk { *; }
-keep class com.ikolvi.tracelet.sdk.TraceletEventSender { *; }
-keep class com.ikolvi.tracelet.sdk.TraceletListener { *; }

# Keep Pigeon-generated API classes (Flutter ↔ Native bridge)
-keep class com.ikolvi.tracelet.TraceletApi$* { *; }
-keep class com.ikolvi.tracelet.flutter.TraceletHostApiImpl { *; }

# Keep model classes used in Pigeon serialization
-keep class com.ikolvi.tracelet.sdk.model.** { *; }

# SQLCipher (optional — only applied if present on classpath)
-dontwarn net.zetetic.database.**
-keep class net.zetetic.database.** { *; }

# Play Integrity (optional — only applied if present on classpath)
-dontwarn com.google.android.play.core.integrity.**

# Security-crypto (optional — only needed with SQLCipher)
-dontwarn androidx.security.crypto.**

# Keep Kotlin metadata for interfaces used via reflection
-keepattributes *Annotation*
