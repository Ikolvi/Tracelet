/**
 * Structured error codes returned by the native Tracelet module.
 *
 * Usage:
 * ```ts
 * try {
 *   await Tracelet.start();
 * } catch (e) {
 *   if (e.code === TraceletError.ERR_NOT_READY) {
 *     await Tracelet.ready(config);
 *   }
 * }
 * ```
 */
export enum TraceletError {
  /** ready() has not been called before start/stop/startGeofences/startPeriodic. */
  ERR_NOT_READY = 'ERR_NOT_READY',

  /** Location permission is missing — call requestPermission() first. */
  ERR_PERMISSION_DENIED = 'ERR_PERMISSION_DENIED',

  /** getCurrentPosition() failed (timeout, provider unavailable, etc.). */
  ERR_LOCATION = 'ERR_LOCATION',

  /** HTTP sync failed. */
  ERR_SYNC = 'ERR_SYNC',

  /** Geofence operation failed (limit exceeded, invalid params). */
  ERR_GEOFENCE = 'ERR_GEOFENCE',

  /** Persistence read/write error. */
  ERR_PERSISTENCE = 'ERR_PERSISTENCE',
}
