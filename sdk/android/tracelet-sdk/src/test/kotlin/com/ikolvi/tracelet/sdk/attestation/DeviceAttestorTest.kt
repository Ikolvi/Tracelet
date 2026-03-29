package com.ikolvi.tracelet.sdk.attestation

import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
class DeviceAttestorTest {

    @Test
    fun isAvailable_returnsTrueWhenPlayIntegrityOnClasspath() {
        // play-integrity is in testImplementation, so it should be available
        assertTrue(DeviceAttestor.isAvailable())
    }
}
