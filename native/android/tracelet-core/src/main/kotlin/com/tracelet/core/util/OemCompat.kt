package com.tracelet.core.util

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.util.Log

/**
 * OEM compatibility layer for aggressive Chinese manufacturer power management.
 *
 * Addresses background-kill behaviors from Huawei (PowerGenie), Xiaomi (MIUI/HyperOS),
 * OnePlus (OxygenOS), Samsung (One UI), Oppo (ColorOS), and Vivo (FuntouchOS).
 *
 * Key mitigations:
 * - Huawei wakelock tag hack to bypass PowerGenie process killing
 * - Xiaomi autostart permission detection
 * - OEM-specific settings deep-links for user-facing configuration
 * - Manufacturer identification for runtime adaptation
 *
 * @see <a href="https://dontkillmyapp.com">Don't Kill My App</a>
 */
object OemCompat {

    private const val TAG = "OemCompat"

    // =========================================================================
    // Manufacturer detection
    // =========================================================================

    /** Normalized lowercase manufacturer string. */
    val manufacturer: String = Build.MANUFACTURER.lowercase()

    private val huaweiNames = setOf("huawei", "honor")
    private val xiaomiNames = setOf("xiaomi", "redmi", "poco")
    private val oppoNames = setOf("oppo", "realme")

    val isHuawei: Boolean = manufacturer in huaweiNames
    val isXiaomi: Boolean = manufacturer in xiaomiNames
    val isSamsung: Boolean = manufacturer == "samsung"
    val isOnePlus: Boolean = manufacturer == "oneplus"
    val isOppo: Boolean = manufacturer in oppoNames
    val isVivo: Boolean = manufacturer == "vivo"

    /** True if the device is from an OEM known for aggressive background killing. */
    val isAggressiveOem: Boolean = isHuawei || isXiaomi || isSamsung || isOnePlus || isOppo || isVivo

    /**
     * Returns an OEM aggression rating (1-5 scale, matching dontkillmyapp.com).
     * 0 = stock Android / unknown (no aggressive behavior expected).
     */
    val aggressionRating: Int
        get() = when {
            isHuawei -> 5
            isXiaomi -> 5
            isOnePlus -> 5
            isSamsung -> 4
            isOppo -> 3
            isVivo -> 3
            else -> 0
        }

    // =========================================================================
    // Huawei PowerGenie wakelock tag hack
    // =========================================================================

    /**
     * Acquires a partial wakelock with an OEM-friendly tag.
     *
     * On Huawei EMUI 9+, PowerGenie inspects wakelock tags and whitelists
     * certain system service names. Using `LocationManagerService` as the tag
     * tricks PowerGenie into treating our process as a system location service,
     * preventing it from being killed.
     *
     * On non-Huawei devices, uses a standard tag with no special behavior.
     *
     * @return The acquired wakelock (caller must release when done)
     */
    fun acquireOemSafeWakelock(context: Context, timeout: Long = 10 * 60 * 1000L): PowerManager.WakeLock? {
        return try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                ?: return null

            val tag = if (isHuawei) {
                // Huawei PowerGenie whitelists these tags:
                // LocationManagerService, AudioMix, AudioIn, AudioDirectOut
                "LocationManagerService"
            } else {
                "com.tracelet:location"
            }

            val wakelock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, tag)
            // Always use a timeout to prevent indefinite CPU wakefulness.
            // Default 10 minutes; the service should re-acquire when needed.
            wakelock.acquire(timeout)
            Log.d(TAG, "Acquired OEM-safe wakelock with tag: $tag")
            wakelock
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire wakelock: ${e.message}")
            null
        }
    }

    // =========================================================================
    // Xiaomi autostart detection
    // =========================================================================

    /**
     * Checks if the autostart permission is likely enabled for this app on Xiaomi/MIUI.
     *
     * MIUI does not expose a public API for this; we check if the autostart
     * management activity is resolvable, which indicates autostart management
     * is available on this device. The actual permission state cannot be read
     * programmatically on most MIUI versions.
     *
     * @return `true` if autostart management is available (Xiaomi device),
     *         `null` if not a Xiaomi device or detection failed.
     */
    fun isAutostartAvailable(context: Context): Boolean? {
        if (!isXiaomi) return null

        return try {
            val intent = getAutostartIntent(context)
            intent != null && context.packageManager.resolveActivity(
                intent,
                PackageManager.MATCH_DEFAULT_ONLY
            ) != null
        } catch (e: Exception) {
            Log.e(TAG, "Autostart check failed: ${e.message}")
            null
        }
    }

    /**
     * Returns the intent to launch the Xiaomi autostart management screen,
     * or null if not available.
     */
    private fun getAutostartIntent(context: Context): Intent? {
        return try {
            Intent().apply {
                component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            }
        } catch (e: Exception) {
            null
        }
    }

    // =========================================================================
    // OEM settings deep-links
    // =========================================================================

    /**
     * OEM-specific settings screen definition.
     *
     * @param label Human-readable settings label (e.g., "Autostart")
     * @param intent The intent to launch, or null if not available on this device
     */
    data class OemSettingsScreen(
        val label: String,
        val intent: Intent?,
        val manufacturer: String,
        val description: String
    )

    /**
     * Returns a list of OEM-specific settings screens that the user should
     * configure for reliable background location tracking.
     *
     * Each screen includes the intent to launch it and a description of what
     * the user should do. Intents are validated against the device's package
     * manager — only resolvable intents are included.
     *
     * @return List of available OEM settings screens (empty on stock Android)
     */
    fun getOemSettingsScreens(context: Context): List<OemSettingsScreen> {
        val screens = mutableListOf<OemSettingsScreen>()
        val pm = context.packageManager

        when {
            isXiaomi -> {
                addIfResolvable(screens, pm, OemSettingsScreen(
                    label = "Autostart",
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.miui.securitycenter",
                            "com.miui.permcenter.autostart.AutoStartManagementActivity"
                        )
                    },
                    manufacturer = "Xiaomi",
                    description = "Enable 'Autostart' for this app to allow background tracking after reboot"
                ))
                addIfResolvable(screens, pm, OemSettingsScreen(
                    label = "Battery Saver",
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.miui.powerkeeper",
                            "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"
                        )
                    },
                    manufacturer = "Xiaomi",
                    description = "Set battery saver to 'No restrictions' for this app"
                ))
            }

            isHuawei -> {
                addIfResolvable(screens, pm, OemSettingsScreen(
                    label = "App Launch",
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.huawei.systemmanager",
                            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                        )
                    },
                    manufacturer = "Huawei",
                    description = "Set 'App Launch' to 'Manage manually' and enable Auto-launch, Secondary launch, and Run in background"
                ))
                // Fallback for older EMUI versions
                addIfResolvable(screens, pm, OemSettingsScreen(
                    label = "Protected Apps",
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.huawei.systemmanager",
                            "com.huawei.systemmanager.optimize.process.ProtectActivity"
                        )
                    },
                    manufacturer = "Huawei",
                    description = "Add this app to 'Protected Apps' to prevent it from being killed"
                ))
            }

            isOnePlus -> {
                addIfResolvable(screens, pm, OemSettingsScreen(
                    label = "Battery Optimization",
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.oneplus.security",
                            "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
                        )
                    },
                    manufacturer = "OnePlus",
                    description = "Disable 'Deep Optimization' and 'Sleep Standby Optimization' for this app"
                ))
            }

            isOppo -> {
                addIfResolvable(screens, pm, OemSettingsScreen(
                    label = "Startup Manager",
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.coloros.safecenter",
                            "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                        )
                    },
                    manufacturer = "Oppo",
                    description = "Enable auto-startup for this app"
                ))
                // Fallback for newer ColorOS
                addIfResolvable(screens, pm, OemSettingsScreen(
                    label = "Startup Manager",
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.coloros.safecenter",
                            "com.coloros.safecenter.startupapp.StartupAppListActivity"
                        )
                    },
                    manufacturer = "Oppo",
                    description = "Enable auto-startup for this app"
                ))
            }

            isVivo -> {
                addIfResolvable(screens, pm, OemSettingsScreen(
                    label = "Background Activity",
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.vivo.permissionmanager",
                            "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                        )
                    },
                    manufacturer = "Vivo",
                    description = "Allow background activity for this app"
                ))
                // Fallback
                addIfResolvable(screens, pm, OemSettingsScreen(
                    label = "Background Activity",
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.iqoo.secure",
                            "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"
                        )
                    },
                    manufacturer = "Vivo",
                    description = "Allow background activity for this app"
                ))
            }

            isSamsung -> {
                addIfResolvable(screens, pm, OemSettingsScreen(
                    label = "Battery Settings",
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.samsung.android.lool",
                            "com.samsung.android.sm.battery.ui.BatteryActivity"
                        )
                    },
                    manufacturer = "Samsung",
                    description = "Remove this app from 'Sleeping apps' and 'Deep sleeping apps' lists"
                ))
            }
        }

        return screens
    }

    /**
     * Attempts to open a specific OEM settings screen by label.
     *
     * @param label The label of the settings screen (from [getOemSettingsScreens])
     * @return `true` if the screen was successfully launched
     */
    fun openOemSettingsScreen(context: Context, label: String): Boolean {
        val screens = getOemSettingsScreens(context)
        val screen = screens.firstOrNull { it.label == label } ?: return false
        val intent = screen.intent ?: return false

        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open OEM settings '$label': ${e.message}")
            false
        }
    }

    // =========================================================================
    // Settings health check
    // =========================================================================

    /**
     * Performs a comprehensive health check for background tracking reliability.
     *
     * Returns a map with the following keys:
     * - `manufacturer`: Device manufacturer name
     * - `isAggressiveOem`: Whether this is a known aggressive OEM
     * - `aggressionRating`: 0-5 scale of OEM background-kill aggressiveness
     * - `isIgnoringBatteryOptimizations`: Whether app is exempt from battery optimization
     * - `autostartAvailable`: Whether autostart management is available (Xiaomi only)
     * - `oemSettingsScreens`: List of maps with OEM-specific settings to configure
     */
    fun getSettingsHealth(context: Context): Map<String, Any?> {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val isIgnoringBattery = pm?.isIgnoringBatteryOptimizations(context.packageName) ?: false

        val oemScreens = getOemSettingsScreens(context).map { screen ->
            mapOf(
                "label" to screen.label,
                "manufacturer" to screen.manufacturer,
                "description" to screen.description,
                "available" to (screen.intent != null)
            )
        }

        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "isAggressiveOem" to isAggressiveOem,
            "aggressionRating" to aggressionRating,
            "isIgnoringBatteryOptimizations" to isIgnoringBattery,
            "autostartAvailable" to isAutostartAvailable(context),
            "oemSettingsScreens" to oemScreens
        )
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private fun addIfResolvable(
        screens: MutableList<OemSettingsScreen>,
        pm: PackageManager,
        screen: OemSettingsScreen
    ) {
        val intent = screen.intent ?: return
        try {
            if (pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null) {
                screens.add(screen)
            } else {
                Log.d(TAG, "OEM settings screen not resolvable: ${screen.label}")
            }
        } catch (e: Exception) {
            Log.d(TAG, "OEM settings screen check failed: ${screen.label}: ${e.message}")
        }
    }
}
