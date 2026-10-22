package com.ikolvi.tracelet.sdk.crash

import android.content.Context
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * #439: the unlock request reports the running app's id and signing cert, so
 * the license server can refuse a prod license bound to another app.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
class CrashModelUnlockIdentityTest {

    @Test
    fun `payload carries platform, package and cert`() {
        val json = JSONObject(
            CrashModelLoader.unlockPayload(
                "key.sig", null, CrashModelLoader.AppIdentity("com.pamamap.app", "ab".repeat(32)),
            ),
        )
        assertEquals("key.sig", json.getString("licenseKey"))
        assertEquals("android", json.getString("platform"))
        assertEquals("com.pamamap.app", json.getString("pkg"))
        assertEquals("ab".repeat(32), json.getString("certSha256"))
        assertFalse(json.has("integrityToken"))
    }

    @Test
    fun `an unreadable cert is omitted, not sent empty`() {
        val json = JSONObject(
            CrashModelLoader.unlockPayload("k", "tok", CrashModelLoader.AppIdentity("com.a", null)),
        )
        assertFalse(json.has("certSha256"))
        assertEquals("tok", json.getString("integrityToken"))
    }

    @Test
    fun `without an identity the payload is what 3_8_8 sent`() {
        val json = JSONObject(CrashModelLoader.unlockPayload("k", null, null))
        assertEquals(setOf("licenseKey"), json.keys().asSequence().toSet())
    }

    @Test
    fun `escapes quotes in the license key`() {
        val json = JSONObject(CrashModelLoader.unlockPayload("a\"b", null, null))
        assertEquals("a\"b", json.getString("licenseKey"))
    }

    @Test
    fun `app identity reports the running package`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        assertEquals(context.packageName, CrashModelLoader.appIdentity(context).pkg)
    }
}
