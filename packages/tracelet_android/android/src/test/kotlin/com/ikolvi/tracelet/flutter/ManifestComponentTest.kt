package com.ikolvi.tracelet.flutter

import com.ikolvi.tracelet.sdk.receiver.BootReceiver
import com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver
import com.ikolvi.tracelet.sdk.receiver.PeriodicAlarmReceiver
import com.ikolvi.tracelet.sdk.service.LocationService
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Validates that AndroidManifest component class names match their actual
 * package locations. Prevents regressions where a class is moved to a
 * different package without updating the manifest (Issue #31).
 *
 * A mismatch causes ClassNotFoundException at runtime — e.g. when Android
 * tries to instantiate BootReceiver after a device reboot.
 */
internal class ManifestComponentTest {

    /**
     * The fully qualified class names that AndroidManifest.xml must declare.
     * If any of these change, the manifest must be updated to match.
     */
    @Test
    fun bootReceiver_packageMatchesManifestDeclaration() {
        assertEquals(
            "com.ikolvi.tracelet.sdk.receiver.BootReceiver",
            BootReceiver::class.java.name,
            "BootReceiver package changed — update AndroidManifest.xml"
        )
    }

    @Test
    fun geofenceBroadcastReceiver_packageMatchesManifestDeclaration() {
        assertEquals(
            "com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver",
            GeofenceBroadcastReceiver::class.java.name,
            "GeofenceBroadcastReceiver package changed — update AndroidManifest.xml"
        )
    }

    @Test
    fun periodicAlarmReceiver_packageMatchesManifestDeclaration() {
        assertEquals(
            "com.ikolvi.tracelet.sdk.receiver.PeriodicAlarmReceiver",
            PeriodicAlarmReceiver::class.java.name,
            "PeriodicAlarmReceiver package changed — update AndroidManifest.xml"
        )
    }

    @Test
    fun locationService_packageMatchesManifestDeclaration() {
        assertEquals(
            "com.ikolvi.tracelet.sdk.service.LocationService",
            LocationService::class.java.name,
            "LocationService package changed — update AndroidManifest.xml"
        )
    }

    @Test
    fun headlessTaskService_packageMatchesManifestDeclaration() {
        assertEquals(
            "com.ikolvi.tracelet.flutter.service.HeadlessTaskService",
            HeadlessTaskService::class.java.name,
            "HeadlessTaskService package changed — update AndroidManifest.xml"
        )
    }
}
