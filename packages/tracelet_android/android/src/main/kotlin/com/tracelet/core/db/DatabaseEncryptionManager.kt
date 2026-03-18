package com.tracelet.core.db

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.SecureRandom

/**
 * Manages at-rest database encryption keys and state.
 *
 * Keys are stored securely using EncryptedSharedPreferences backed by
 * the Android Keystore. The MasterKey is AES-256-GCM.
 */
class DatabaseEncryptionManager(private val context: Context) {

    companion object {
        private const val TAG = "TraceletEncryption"
        private const val PREFS_NAME = "com.tracelet.encryption"
        private const val KEY_DB_KEY = "database_key"
        private const val KEY_IS_ENCRYPTED = "is_encrypted"
    }

    private val masterKey: MasterKey by lazy {
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
    }

    private val prefs: SharedPreferences by lazy {
        EncryptedSharedPreferences.create(
            context,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    /** Check if the database has been encrypted. */
    fun isDatabaseEncrypted(): Boolean {
        return prefs.getBoolean(KEY_IS_ENCRYPTED, false)
    }

    /**
     * Get or create the database encryption key.
     *
     * If [customKey] is non-null, it is used directly. Otherwise, a stored
     * key is returned if one exists, or a new 256-bit random key is generated,
     * stored in EncryptedSharedPreferences, and returned.
     */
    fun getOrCreateKey(customKey: String?): ByteArray {
        if (!customKey.isNullOrEmpty()) {
            return customKey.toByteArray(Charsets.UTF_8)
        }

        val existing = prefs.getString(KEY_DB_KEY, null)
        if (existing != null) {
            return Base64.decode(existing, Base64.NO_WRAP)
        }

        // Generate a new 256-bit (32 byte) random key
        val key = ByteArray(32)
        SecureRandom().nextBytes(key)
        val encoded = Base64.encodeToString(key, Base64.NO_WRAP)
        prefs.edit().putString(KEY_DB_KEY, encoded).apply()
        Log.i(TAG, "Generated new database encryption key")
        return key
    }

    /** Retrieve the stored encryption key, or null if none exists. */
    fun getStoredKey(): ByteArray? {
        val stored = prefs.getString(KEY_DB_KEY, null) ?: return null
        return Base64.decode(stored, Base64.NO_WRAP)
    }

    /** Mark the database as encrypted in persistent storage. */
    fun markEncrypted() {
        prefs.edit().putBoolean(KEY_IS_ENCRYPTED, true).apply()
        Log.i(TAG, "Database marked as encrypted")
    }

    /** Get the database password bytes for SQLCipher, or empty array if not encrypted. */
    fun getDatabasePassword(customKey: String?): ByteArray {
        if (!customKey.isNullOrEmpty()) {
            return customKey.toByteArray(Charsets.UTF_8)
        }
        if (!isDatabaseEncrypted()) {
            return ByteArray(0) // Unencrypted mode
        }
        return getStoredKey() ?: ByteArray(0)
    }
}
