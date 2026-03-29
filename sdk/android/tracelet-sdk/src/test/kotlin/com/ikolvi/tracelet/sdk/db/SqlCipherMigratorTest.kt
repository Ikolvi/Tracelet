package com.ikolvi.tracelet.sdk.db

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.robolectric.RobolectricTestRunner
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse

@RunWith(RobolectricTestRunner::class)
class SqlCipherMigratorTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun isAvailable_returnsFalseWithoutSqlCipherRuntime() {
        // sqlcipher-android is compileOnly — not on the test runtime classpath.
        // This verifies the Class.forName detection works correctly.
        assertFalse(SqlCipherMigrator.isAvailable())
    }

    @Test
    fun encryptDatabase_throwsWhenSqlCipherUnavailable() {
        val db = TraceletDatabase.getInstance(context)
        val encMgr = mock(DatabaseEncryptionManager::class.java)

        val ex = assertFailsWith<IllegalStateException> {
            db.encryptDatabase(ByteArray(32), encMgr)
        }
        assert(ex.message!!.contains("sqlcipher-android"))
    }
}
