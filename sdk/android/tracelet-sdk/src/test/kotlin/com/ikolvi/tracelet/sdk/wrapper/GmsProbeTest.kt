package com.ikolvi.tracelet.sdk.wrapper

import android.content.Context
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.robolectric.RobolectricTestRunner
import java.io.File
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Regression coverage for the Play services availability probe.
 *
 * The probe decides which location backend the whole SDK uses:
 * `PlayServicesProvider` (FusedLocationProvider, GeofencingClient, real activity
 * recognition) or `AospServicesProvider` (raw LocationManager, the deprecated
 * `addProximityAlert`, and a stubbed activity-recognition client).
 *
 * A false negative is therefore expensive: it silently degrades fix quality and
 * feeds coarse NETWORK_PROVIDER fixes into the geofence evaluator, which shows
 * up downstream as drift-induced false geofence EXITs.
 *
 * The bug these tests pin down: `DefaultGmsProbe.availabilityResultCode` looks
 * the method up reflectively via `getMethod("getInstance")`. R8 rewrites the
 * `Class.forName` *string literal* to the renamed class but leaves the
 * `getMethod` argument alone, so in a minified release build the class resolves
 * while the method lookup throws `NoSuchMethodException`. Field reports carry
 * the tell verbatim, e.g. `v2.d.getInstance []` on a Galaxy S23 (SM-S911B) —
 * a device that unquestionably ships Play services.
 */
@RunWith(RobolectricTestRunner::class)
class GmsProbeTest {

    private val context: Context = mock()

    /**
     * Fake probe with each of the three questions independently controllable.
     *
     * [availabilityThrows] simulates the probe machinery breaking, which is
     * deliberately distinct from GMS genuinely being absent.
     */
    private class FakeGmsProbe(
        private val classesLinked: Boolean = true,
        private val resultCode: Int = 0,
        private val availabilityThrows: Throwable? = null,
        private val packageEnabled: Boolean = true,
    ) : GmsProbe {
        var packageCheckCalls = 0
            private set

        override fun locationClassesLinked(): Boolean = classesLinked

        override fun availabilityResultCode(context: Context): Int {
            availabilityThrows?.let { throw it }
            return resultCode
        }

        override fun playServicesPackageEnabled(context: Context): Boolean {
            packageCheckCalls++
            return packageEnabled
        }
    }

    /** The exact failure a minified release build produces (obfuscated class, original method name). */
    private fun r8RenamedMethod() = NoSuchMethodException("v2.d.getInstance []")

    // ── Happy paths (already correct before the fix) ─────────────────────────

    @Test
    fun `reports available when classes are linked and the framework returns SUCCESS`() {
        val probe = FakeGmsProbe(classesLinked = true, resultCode = 0)
        assertTrue(TraceletServices.resolveGmsAvailability(context, probe))
    }

    @Test
    fun `reports unavailable when the GMS location classes are not linked into the app`() {
        // A genuinely GMS-free build. No amount of package checking should
        // override this: without the classes there is nothing to call into.
        val probe = FakeGmsProbe(classesLinked = false, packageEnabled = true)
        assertFalse(TraceletServices.resolveGmsAvailability(context, probe))
    }

    @Test
    fun `reports unavailable when the framework reports a non-SUCCESS result code`() {
        // 1 == ConnectionResult.SERVICE_MISSING. The probe worked and gave a
        // definitive answer, so it must be honoured.
        val probe = FakeGmsProbe(classesLinked = true, resultCode = 1)
        assertFalse(TraceletServices.resolveGmsAvailability(context, probe))
    }

    @Test
    fun `does not consult the package manager when the reflective probe succeeds`() {
        val probe = FakeGmsProbe(classesLinked = true, resultCode = 0)
        TraceletServices.resolveGmsAvailability(context, probe)
        assertTrue(probe.packageCheckCalls == 0, "expected no package-manager fallback on the happy path")
    }

    // ── The R8 regression ───────────────────────────────────────────────────

    @Test
    fun `survives R8 renaming the reflected method when Play services is installed`() {
        // The reported field failure: reflection is broken, but the device has
        // healthy Play services. Concluding "GMS absent" here is what silently
        // downgrades the entire location stack to the AOSP fallback.
        val probe = FakeGmsProbe(
            classesLinked = true,
            availabilityThrows = r8RenamedMethod(),
            packageEnabled = true,
        )
        assertTrue(
            TraceletServices.resolveGmsAvailability(context, probe),
            "a broken reflective probe must not be treated as 'GMS absent' when " +
                "the OS reports Play services installed and enabled",
        )
    }

    @Test
    fun `falls back to the package manager when the reflective probe throws`() {
        val probe = FakeGmsProbe(
            classesLinked = true,
            availabilityThrows = r8RenamedMethod(),
            packageEnabled = true,
        )
        TraceletServices.resolveGmsAvailability(context, probe)
        assertTrue(probe.packageCheckCalls == 1, "expected exactly one package-manager fallback")
    }

    @Test
    fun `reports unavailable when reflection throws and Play services is genuinely missing`() {
        // The fallback must not blindly answer "available" — on a real GMS-free
        // device (China ROM, GrapheneOS, bare AOSP) both signals say no.
        val probe = FakeGmsProbe(
            classesLinked = true,
            availabilityThrows = r8RenamedMethod(),
            packageEnabled = false,
        )
        assertFalse(TraceletServices.resolveGmsAvailability(context, probe))
    }

    @Test
    fun `recovers from any probe failure mode, not just NoSuchMethodException`() {
        // R8 can also strip the class outright, and OEM builds have been seen
        // throwing from inside GoogleApiAvailability itself. The policy is about
        // "the probe could not answer", regardless of how it failed.
        val failures = listOf(
            NoSuchMethodException("v2.d.getInstance []"),
            ClassNotFoundException("com.google.android.gms.common.GoogleApiAvailability"),
            NoClassDefFoundError("com/google/android/gms/common/GoogleApiAvailability"),
            IllegalStateException("boom"),
        )
        for (failure in failures) {
            val probe = FakeGmsProbe(
                classesLinked = true,
                availabilityThrows = failure,
                packageEnabled = true,
            )
            assertTrue(
                TraceletServices.resolveGmsAvailability(context, probe),
                "expected recovery from ${failure.javaClass.simpleName}",
            )
        }
    }

    // ── Keep-rule guard ─────────────────────────────────────────────────────

    /**
     * The package-manager fallback stops the reflective probe from being fatal,
     * but the reflective path is still the one that yields a precise answer
     * (installed-but-disabled, needs-update, and so on). Keeping
     * `GoogleApiAvailability` lets it keep working in minified builds instead of
     * permanently limping along on the fallback.
     *
     * `consumerProguardFiles` propagates these rules to host apps, so the rule
     * has to live in the consumer file to reach the app that does the minifying.
     */
    @Test
    fun `consumer proguard rules keep GoogleApiAvailability for the reflective probe`() {
        val candidates = listOf(
            File("consumer-rules.pro"),
            File("sdk/android/tracelet-sdk/consumer-rules.pro"),
            File("../tracelet-sdk/consumer-rules.pro"),
        )
        val rules = candidates.firstOrNull { it.exists() }
        requireNotNull(rules) {
            "consumer-rules.pro not found; looked in ${candidates.map { it.absolutePath }}"
        }
        val contents = rules.readText()
        assertTrue(
            contents.contains("-keep class com.google.android.gms.common.GoogleApiAvailability"),
            "consumer-rules.pro must keep GoogleApiAvailability, otherwise R8 renames " +
                "getInstance() and the reflective availability probe breaks in every " +
                "minified release build",
        )
    }
}
