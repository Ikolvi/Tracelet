# Tracelet Android Plugin — ProGuard/R8 Consumer Rules
# These rules are automatically applied to host apps using this plugin.

# Keep all Tracelet plugin and SDK classes
-keep class com.ikolvi.tracelet.flutter.** { *; }
-keep class com.ikolvi.tracelet.sdk.** { *; }

# Keep the service and receiver classes that are referenced in AndroidManifest
-keep class com.ikolvi.tracelet.sdk.service.LocationService { *; }
-keep class com.ikolvi.tracelet.flutter.service.HeadlessTaskService { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.BootReceiver { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver { *; }
-keep class com.ikolvi.tracelet.sdk.receiver.PeriodicAlarmReceiver { *; }

# Keep the plugin entry point
-keep class com.ikolvi.tracelet.flutter.TraceletAndroidPlugin { *; }

# Keep BuildConfig (required for AGP 8.5+)
-keep class com.ikolvi.tracelet.flutter.BuildConfig { *; }

# Room database — keep entities and DAOs
-keep class com.tracelet.core.db.** { *; }

# Keep Kotlin metadata for reflection
-keepattributes *Annotation*
-keepattributes KotlinMetadata
