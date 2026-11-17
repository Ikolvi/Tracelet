
# Tracelet Plugin Rules
-keep class com.ikolvi.tracelet.** { *; }
-keep interface com.ikolvi.tracelet.** { *; }
-keep class uniffi.tracelet_core.** { *; }

# Keep Pigeon Generated Classes
-keep class com.ikolvi.tracelet.TraceletHostApi { *; }
-keep class com.ikolvi.tracelet.TraceletEventApi { *; }
-keep class com.ikolvi.tracelet.TraceletHostApi$* { *; }
-keep class com.ikolvi.tracelet.TraceletEventApi$* { *; }
-keep class com.ikolvi.tracelet.TraceletApiPigeonCodec { *; }
-keep class com.ikolvi.tracelet.TraceletApi_gKt { *; }
-keep class com.ikolvi.tracelet.TraceletApiKt { *; }
-keep class com.ikolvi.tracelet.Tl** { *; }

-dontwarn java.awt.**
-dontwarn com.sun.jna.**

# The Example's #459 probe sends controlled fixes through the native engine.
-keepclassmembers class com.ikolvi.tracelet.sdk.location.LocationEngine {
    private void onLocationReceived(android.location.Location, java.lang.String, boolean);
}
