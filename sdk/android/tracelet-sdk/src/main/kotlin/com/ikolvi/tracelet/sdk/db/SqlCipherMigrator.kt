package com.ikolvi.tracelet.sdk.db

import android.util.Log

/**
 * Isolates all SQLCipher references into a single class.
 *
 * This class is never loaded by the JVM unless [migrate] is called,
 * so apps that ship without the `sqlcipher-android` AAR will not
 * get a [NoClassDefFoundError] at startup.
 */
internal object SqlCipherMigrator {

    private const val TAG = "SqlCipherMigrator"

    /**
     * Returns `true` if the `sqlcipher-android` library is on the classpath.
     *
     * Uses [Class.forName] so this method itself does **not** trigger class
     * loading of any SQLCipher types.
     */
    @JvmStatic
    fun isAvailable(): Boolean = try {
        Class.forName("net.zetetic.database.sqlcipher.SQLiteDatabase")
        true
    } catch (_: ClassNotFoundException) {
        false
    }

    /**
     * Runs the actual ATTACH/sqlcipher_export migration.
     *
     * @param dbPath       Absolute path to the unencrypted database file.
     * @param encryptedPath Destination path for the encrypted copy.
     * @param key           Encryption key bytes.
     */
    @JvmStatic
    fun migrate(dbPath: String, encryptedPath: String, key: ByteArray) {
        val unencryptedDb = net.zetetic.database.sqlcipher.SQLiteDatabase.openDatabase(
            dbPath, "", null,
            net.zetetic.database.sqlcipher.SQLiteDatabase.OPEN_READWRITE, null, null
        )

        val hexKey = key.joinToString("") { "%02x".format(it) }
        unencryptedDb.rawExecSQL("ATTACH DATABASE '$encryptedPath' AS encrypted KEY x'$hexKey'")
        unencryptedDb.rawExecSQL("SELECT sqlcipher_export('encrypted')")
        unencryptedDb.rawExecSQL("DETACH DATABASE encrypted")
        unencryptedDb.close()

        Log.i(TAG, "SQLCipher migration completed")
    }
}
