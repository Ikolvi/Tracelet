package com.ikolvi.tracelet.sdk.wrapper
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import android.util.Log
import java.util.concurrent.ConcurrentHashMap

// --- INTERFACES ---

interface TraceletLocationClient {
    fun requestLocationUpdates(request: TraceletLocationRequest, callback: TraceletLocationCallback, looper: Looper)
    fun removeLocationUpdates(callback: TraceletLocationCallback)
    fun getCurrentLocation(priority: Int, cancellationToken: TraceletCancellationToken?, onSuccess: (Location?) -> Unit)
    fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit)
}

data class TraceletLocationRequest(
    val priority: Int,
    val intervalMillis: Long,
    val minUpdateDistanceMeters: Float = 0f,
    val minUpdateIntervalMillis: Long = intervalMillis,
    val maxUpdateDelayMillis: Long = 0L
)

interface TraceletLocationCallback {
    fun onLocationResult(locations: List<Location>)
    fun onLocationAvailability(isLocationAvailable: Boolean)
}

interface TraceletCancellationToken {
    val isCancelled: Boolean
    fun cancel()
    fun onCanceled(listener: () -> Unit)
}

object TraceletLocationPriority {
    const val PRIORITY_HIGH_ACCURACY = 100
    const val PRIORITY_BALANCED_POWER_ACCURACY = 102
    const val PRIORITY_LOW_POWER = 104
    const val PRIORITY_PASSIVE = 105
}

class TraceletCancellationTokenSource {
    var isCancelled = false; private set
    private var cancelListener: (() -> Unit)? = null
    val token: TraceletCancellationToken = object : TraceletCancellationToken {
        override val isCancelled: Boolean get() = this@TraceletCancellationTokenSource.isCancelled
        override fun cancel() { this@TraceletCancellationTokenSource.isCancelled = true; cancelListener?.invoke() }
        override fun onCanceled(listener: () -> Unit) { cancelListener = listener; if (this@TraceletCancellationTokenSource.isCancelled) listener.invoke() }
    }
    fun cancel() { token.cancel() }
}

interface TraceletGeofencingClient {
    fun addGeofences(request: TraceletGeofencingRequest, pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit)
    fun removeGeofences(pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit)
    fun removeGeofences(requestIds: List<String>, onSuccess: () -> Unit, onFailure: (Exception) -> Unit)
}

data class TraceletGeofence(val requestId: String, val latitude: Double, val longitude: Double, val radiusMeters: Float, val expirationTime: Long, val transitionTypes: Int, val loiteringDelayMs: Int)
data class TraceletGeofencingRequest(val geofences: List<TraceletGeofence>, val initialTrigger: Int)

interface TraceletActivityRecognitionClient {
    fun requestActivityUpdates(detectionIntervalMillis: Long, callbackIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit)
    fun removeActivityUpdates(callbackIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit)
    fun requestActivityTransitionUpdates(request: TraceletActivityTransitionRequest, pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit)
    fun removeActivityTransitionUpdates(pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit)
}

data class TraceletActivityTransitionRequest(val transitions: List<TraceletActivityTransition>)
data class TraceletActivityTransition(val activityType: Int, val transitionType: Int)

interface TraceletEventExtractor {
    fun extractGeofencingEvent(intent: Intent): TraceletGeofencingEvent?
    fun extractActivityRecognitionResult(intent: Intent): TraceletActivityRecognitionResult?
    fun extractActivityTransitionResult(intent: Intent): TraceletActivityTransitionResult?
}

data class TraceletGeofencingEvent(val hasError: Boolean, val errorCode: Int, val geofenceTransition: Int, val triggeringGeofences: List<TraceletGeofence>?, val triggeringLocation: Location?)
data class TraceletActivityRecognitionResult(val probableActivities: List<TraceletDetectedActivity>, val mostProbableActivity: TraceletDetectedActivity)
data class TraceletDetectedActivity(val type: Int, val confidence: Int)
data class TraceletActivityTransitionResult(val transitionEvents: List<TraceletActivityTransitionEvent>)
data class TraceletActivityTransitionEvent(val activityType: Int, val transitionType: Int, val elapsedRealTimeNanos: Long)

interface TraceletServicesProvider {
    fun getLocationClient(context: Context): TraceletLocationClient
    fun getGeofencingClient(context: Context): TraceletGeofencingClient
    fun getActivityRecognitionClient(context: Context): TraceletActivityRecognitionClient
    fun getEventExtractor(): TraceletEventExtractor
}

/**
 * The three independent questions the Play services availability probe asks,
 * extracted behind an interface so the decision policy in
 * [TraceletServices.resolveGmsAvailability] can be exercised without a real GMS
 * install — including simulating a minified release build, where the reflective
 * lookup throws even though Play services is perfectly healthy.
 */
internal interface GmsProbe {
    /** Whether the GMS location classes are linked into this APK. */
    fun locationClassesLinked(): Boolean

    /**
     * The `GoogleApiAvailability.isGooglePlayServicesAvailable` result code
     * (`0` == `ConnectionResult.SUCCESS`).
     *
     * Throws when the probe itself cannot run. Most importantly this throws
     * [NoSuchMethodException] in a minified build where R8 has renamed the
     * reflected method, which says nothing about whether GMS is present.
     */
    fun availabilityResultCode(context: Context): Int

    /**
     * Whether the Play services package is installed and enabled, asked
     * directly of the OS package manager.
     *
     * Immune to R8 because it never reflects into our own shrunk code, which
     * makes it a trustworthy second opinion when [availabilityResultCode] fails.
     */
    fun playServicesPackageEnabled(context: Context): Boolean
}

/** Production [GmsProbe] backed by real class loading, reflection and the package manager. */
internal object DefaultGmsProbe : GmsProbe {
    private const val GMS_PACKAGE = "com.google.android.gms"

    override fun locationClassesLinked(): Boolean = try {
        Class.forName("com.google.android.gms.location.LocationServices")
        true
    } catch (e: Throwable) {
        false
    }

    override fun availabilityResultCode(context: Context): Int {
        // Reflection (rather than a typed call) keeps play-services-base a soft
        // dependency: the SDK ships it compileOnly, so a direct reference would
        // risk NoClassDefFoundError in apps that omit GMS entirely.
        val apiAvailabilityClass = Class.forName("com.google.android.gms.common.GoogleApiAvailability")
        val getInstanceMethod = apiAvailabilityClass.getMethod("getInstance")
        val availabilityInstance = getInstanceMethod.invoke(null)
        val isAvailableMethod = apiAvailabilityClass.getMethod("isGooglePlayServicesAvailable", Context::class.java)
        return isAvailableMethod.invoke(availabilityInstance, context) as Int
    }

    override fun playServicesPackageEnabled(context: Context): Boolean = try {
        context.packageManager.getApplicationInfo(GMS_PACKAGE, 0).enabled
    } catch (e: Throwable) {
        false
    }
}

object TraceletServices {
    private var provider: TraceletServicesProvider? = null

    /**
     * Decides whether the Play services location stack should be used.
     *
     * Split out from [isGmsAvailable] so the policy is unit-testable against a
     * fake [GmsProbe].
     */
    internal fun resolveGmsAvailability(context: Context, probe: GmsProbe): Boolean {
        // 1. Are the GMS location classes linked into this build at all? If not
        //    there is nothing to call into, and that verdict is final.
        if (!probe.locationClassesLinked()) {
            TraceletLog.info("GMS location classes are not linked into this build. Using AOSP fallback.")
            return false
        }

        // 2. Ask the framework whether Play services is usable on this device.
        return try {
            val resultCode = probe.availabilityResultCode(context)
            TraceletLog.debug("GooglePlayServices availability check resultCode: $resultCode")
            // ConnectionResult.SUCCESS is 0
            resultCode == 0
        } catch (e: Throwable) {
            // 3. The probe itself could not answer. Crucially this is NOT the
            //    same as "GMS is absent": in a minified build R8 rewrites the
            //    Class.forName string literal to the renamed class but leaves
            //    getMethod("getInstance") untouched, so the lookup throws
            //    NoSuchMethodException on devices with perfectly healthy Play
            //    services. Treating that as absent silently downgrades the
            //    entire location stack to the AOSP fallback, costing fix quality
            //    and feeding coarse network fixes to the geofence evaluator.
            //
            //    Ask the OS directly instead — a package query cannot be broken
            //    by our own shrinker.
            val installed = probe.playServicesPackageEnabled(context)
            TraceletLog.warning(
                "GooglePlayServices availability probe failed " +
                    "(${e.javaClass.simpleName}: ${e.message}); " +
                    "falling back to a package-manager check — installed=$installed. " +
                    "In a minified build, keep GoogleApiAvailability so the probe " +
                    "can report precise availability: " +
                    "-keep class com.google.android.gms.common.GoogleApiAvailability { *; }"
            )
            installed
        }
    }

    /**
     * Checks if GMS classes are compiled in AND if GMS is actually 
     * active on the physical device at runtime.
     */
    fun isGmsAvailable(context: Context): Boolean = resolveGmsAvailability(context, DefaultGmsProbe)

    fun getInstance(context: Context): TraceletServicesProvider = getProvider(context)

    fun getProvider(context: Context): TraceletServicesProvider {
        if (provider == null) {
            provider = try {
                if (isGmsAvailable(context)) {
                    TraceletLog.info("GMS Location classes detected & active on device. Loading PlayServicesProvider.")
                    Class.forName("com.ikolvi.tracelet.sdk.wrapper.PlayServicesProvider")
                        .getDeclaredConstructor()
                        .newInstance() as TraceletServicesProvider
                } else {
                    TraceletLog.info("GMS Location NOT available on device. Using AOSP fallback.")
                    AospServicesProvider()
                }
            } catch (e: Throwable) {
                TraceletLog.error("Failed to initialize GMS provider, falling back to AOSP: ${e.message}")
                AospServicesProvider()
            }
        }
        return provider!!
    }

    fun setProvider(customProvider: TraceletServicesProvider?) {
        provider = customProvider
    }
}

// --- AOSP FALLBACK IMPLEMENTATIONS ---

class AospServicesProvider : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = AospLocationClient(context)
    override fun getGeofencingClient(context: Context) = AospGeofencingClient(context)
    override fun getActivityRecognitionClient(context: Context) = AospActivityRecognitionClient()
    override fun getEventExtractor() = AospEventExtractor()
}

class AospLocationClient(context: Context) : TraceletLocationClient {
    private val locationManager: LocationManager? = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
    private val listeners = ConcurrentHashMap<TraceletLocationCallback, LocationListener>()

    @SuppressLint("MissingPermission")
    override fun requestLocationUpdates(request: TraceletLocationRequest, callback: TraceletLocationCallback, looper: Looper) {
        if (locationManager == null) return
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) { callback.onLocationResult(listOf(location)) }
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) { callback.onLocationAvailability(true) }
            override fun onProviderDisabled(provider: String) { callback.onLocationAvailability(false) }
        }
        // Re-registering an existing callback replaces its subscription (the
        // fused client's documented behavior, which the engine's live
        // re-subscription paths rely on) — unregister the superseded listener.
        val previous = listeners.put(callback, listener)
        val providers = if (request.priority == TraceletLocationPriority.PRIORITY_HIGH_ACCURACY) listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER) else listOf(LocationManager.NETWORK_PROVIDER)
        providers.forEach { provider ->
            if (locationManager.isProviderEnabled(provider)) {
                locationManager.requestLocationUpdates(provider, request.intervalMillis, request.minUpdateDistanceMeters, listener, looper)
            }
        }
        if (previous != null) locationManager.removeUpdates(previous)
        callback.onLocationAvailability(true)
    }

    override fun removeLocationUpdates(callback: TraceletLocationCallback) {
        val listener = listeners.remove(callback)
        if (listener != null) locationManager?.removeUpdates(listener)
    }

    @SuppressLint("MissingPermission")
    override fun getCurrentLocation(priority: Int, cancellationToken: TraceletCancellationToken?, onSuccess: (Location?) -> Unit) {
        if (locationManager == null) { onSuccess(null); return }
        val provider = if (priority == TraceletLocationPriority.PRIORITY_HIGH_ACCURACY) LocationManager.GPS_PROVIDER else LocationManager.NETWORK_PROVIDER
        if (!locationManager.isProviderEnabled(provider)) { onSuccess(null); return }
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) { locationManager.removeUpdates(this); onSuccess(location) }
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) { locationManager.removeUpdates(this); onSuccess(null) }
        }
        cancellationToken?.onCanceled { locationManager.removeUpdates(listener) }
        locationManager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
    }

    @SuppressLint("MissingPermission")
    override fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit) {
        if (locationManager == null) { onFailure(Exception("LocationManager not available")); return }
        try {
            val gps = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            val network = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            val best = when {
                gps != null && network != null -> if (gps.time > network.time) gps else network
                gps != null -> gps
                else -> network
            }
            onSuccess(best)
        } catch (e: Exception) { onFailure(e) }
    }
}

class AospGeofencingClient(private val context: Context) : TraceletGeofencingClient {
    private val locationManager: LocationManager? = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

    @SuppressLint("MissingPermission")
    override fun addGeofences(request: TraceletGeofencingRequest, pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) {
        if (locationManager == null) { onFailure(Exception("LocationManager not available")); return }
        try {
            for (geofence in request.geofences) {
                val expiration = if (geofence.expirationTime > 0) geofence.expirationTime else -1L
                locationManager.addProximityAlert(geofence.latitude, geofence.longitude, geofence.radiusMeters, expiration, pendingIntent)
            }
            onSuccess()
        } catch (e: Exception) { onFailure(e) }
    }

    @SuppressLint("MissingPermission")
    override fun removeGeofences(pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) {
        if (locationManager == null) { onFailure(Exception("LocationManager not available")); return }
        try {
            locationManager.removeProximityAlert(pendingIntent)
            onSuccess()
        } catch (e: Exception) { onFailure(e) }
    }

    override fun removeGeofences(requestIds: List<String>, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) { onSuccess() }
}

class AospActivityRecognitionClient : TraceletActivityRecognitionClient {
    override fun requestActivityUpdates(detectionIntervalMillis: Long, callbackIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) { onSuccess() }
    override fun removeActivityUpdates(callbackIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) { onSuccess() }
    override fun requestActivityTransitionUpdates(request: TraceletActivityTransitionRequest, pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) { onSuccess() }
    override fun removeActivityTransitionUpdates(pendingIntent: PendingIntent, onSuccess: () -> Unit, onFailure: (Exception) -> Unit) { onSuccess() }
}

class AospEventExtractor : TraceletEventExtractor {
    override fun extractGeofencingEvent(intent: Intent): TraceletGeofencingEvent? {
        val entering = intent.getBooleanExtra(LocationManager.KEY_PROXIMITY_ENTERING, false)
        return TraceletGeofencingEvent(hasError = false, errorCode = 0, geofenceTransition = if (entering) 1 else 2, triggeringGeofences = null, triggeringLocation = null)
    }
    override fun extractActivityRecognitionResult(intent: Intent): TraceletActivityRecognitionResult? = null
    override fun extractActivityTransitionResult(intent: Intent): TraceletActivityTransitionResult? = null
}
