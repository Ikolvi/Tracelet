# Tracelet Android Plugin — ProGuard/R8 Consumer Rules
# These rules are automatically applied to host apps using this plugin.

# Keep all Tracelet plugin and core classes
-keep class com.tracelet.tracelet_android.** { *; }
-keep class com.tracelet.core.** { *; }

# Keep the service and receiver classes that are referenced in AndroidManifest
-keep class com.tracelet.core.service.LocationService { *; }
-keep class com.tracelet.tracelet_android.service.HeadlessTaskService { *; }
-keep class com.tracelet.core.receiver.BootReceiver { *; }
-keep class com.tracelet.core.receiver.GeofenceBroadcastReceiver { *; }
-keep class com.tracelet.core.receiver.PeriodicAlarmReceiver { *; }

# Keep the plugin entry point
-keep class com.tracelet.tracelet_android.TraceletAndroidPlugin { *; }

# Keep BuildConfig (required for AGP 8.5+)
-keep class com.tracelet.tracelet_android.BuildConfig { *; }

# Room database — keep entities and DAOs
-keep class com.tracelet.core.db.** { *; }

# Keep Kotlin metadata for reflection
-keepattributes *Annotation*
-keepattributes KotlinMetadata
