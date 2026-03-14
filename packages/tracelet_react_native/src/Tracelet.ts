import { NativeEventEmitter, NativeModules } from 'react-native';
import NativeTracelet from './NativeTracelet';
import type { Config } from './types/Config';
import type { State } from './types/State';
import type {
  Location,
  CurrentPositionOptions,
  LastKnownLocationOptions,
  WatchPositionOptions,
  SQLQuery,
} from './types/Location';
import type { Geofence } from './types/Geofence';
import type {
  MotionChangeEvent,
  ActivityChangeEvent,
  ProviderChangeEvent,
  GeofenceEvent,
  GeofencesChangeEvent,
  HeartbeatEvent,
  HttpEvent,
  ConnectivityChangeEvent,
  AuthorizationEvent,
  HeadlessEvent,
  Sensors,
  DeviceInfo,
} from './types/Events';
import type { AuthorizationStatus, AccuracyAuthorization } from './types/Enums';

/** Event subscription handle. Call remove() to unsubscribe. */
export interface Subscription {
  remove(): void;
}

const emitter = new NativeEventEmitter(
  NativeModules['TraceletReactNative'] as never
);

/**
 * Tracelet — production-grade background geolocation for React Native.
 *
 * All methods are static. The underlying native module is a singleton.
 */
export class Tracelet {
  // ── Lifecycle ──────────────────────────────────────────────────────

  static async ready(config: Config): Promise<State> {
    return NativeTracelet.ready(config) as Promise<State>;
  }

  static async start(): Promise<State> {
    return NativeTracelet.start() as Promise<State>;
  }

  static async stop(): Promise<State> {
    return NativeTracelet.stop() as Promise<State>;
  }

  static async startGeofences(): Promise<State> {
    return NativeTracelet.startGeofences() as Promise<State>;
  }

  static async startPeriodic(): Promise<State> {
    return NativeTracelet.startPeriodic() as Promise<State>;
  }

  static async getState(): Promise<State> {
    return NativeTracelet.getState() as Promise<State>;
  }

  static async setConfig(config: Partial<Config>): Promise<State> {
    return NativeTracelet.setConfig(config) as Promise<State>;
  }

  static async reset(config?: Config): Promise<State> {
    return NativeTracelet.reset(config) as Promise<State>;
  }

  // ── Location ───────────────────────────────────────────────────────

  static async getCurrentPosition(
    options?: CurrentPositionOptions
  ): Promise<Location> {
    return NativeTracelet.getCurrentPosition(options ?? {}) as Promise<Location>;
  }

  static async getLastKnownLocation(
    options?: LastKnownLocationOptions
  ): Promise<Location | null> {
    return NativeTracelet.getLastKnownLocation(options) as Promise<Location | null>;
  }

  static async watchPosition(options: WatchPositionOptions): Promise<number> {
    return NativeTracelet.watchPosition(options);
  }

  static async stopWatchPosition(watchId: number): Promise<boolean> {
    return NativeTracelet.stopWatchPosition(watchId);
  }

  static async changePace(isMoving: boolean): Promise<boolean> {
    return NativeTracelet.changePace(isMoving);
  }

  static async getOdometer(): Promise<number> {
    return NativeTracelet.getOdometer();
  }

  static async setOdometer(value: number): Promise<Location> {
    return NativeTracelet.setOdometer(value) as Promise<Location>;
  }

  // ── Geofencing ─────────────────────────────────────────────────────

  static async addGeofence(geofence: Geofence): Promise<boolean> {
    return NativeTracelet.addGeofence(geofence);
  }

  static async addGeofences(geofences: Geofence[]): Promise<boolean> {
    return NativeTracelet.addGeofences(geofences);
  }

  static async removeGeofence(identifier: string): Promise<boolean> {
    return NativeTracelet.removeGeofence(identifier);
  }

  static async removeGeofences(): Promise<boolean> {
    return NativeTracelet.removeGeofences();
  }

  static async getGeofences(): Promise<Geofence[]> {
    return NativeTracelet.getGeofences() as Promise<Geofence[]>;
  }

  static async getGeofence(identifier: string): Promise<Geofence | null> {
    return NativeTracelet.getGeofence(identifier) as Promise<Geofence | null>;
  }

  static async geofenceExists(identifier: string): Promise<boolean> {
    return NativeTracelet.geofenceExists(identifier);
  }

  // ── Persistence ────────────────────────────────────────────────────

  static async getLocations(query?: SQLQuery): Promise<Location[]> {
    return NativeTracelet.getLocations(query) as Promise<Location[]>;
  }

  static async getCount(): Promise<number> {
    return NativeTracelet.getCount();
  }

  static async destroyLocations(): Promise<boolean> {
    return NativeTracelet.destroyLocations();
  }

  static async destroyLocation(uuid: string): Promise<boolean> {
    return NativeTracelet.destroyLocation(uuid);
  }

  static async insertLocation(location: Partial<Location>): Promise<string> {
    return NativeTracelet.insertLocation(location);
  }

  // ── HTTP Sync ──────────────────────────────────────────────────────

  static async sync(): Promise<Location[]> {
    return NativeTracelet.sync() as Promise<Location[]>;
  }

  // ── Permissions ────────────────────────────────────────────────────

  static async requestPermission(): Promise<AuthorizationStatus> {
    return NativeTracelet.requestPermission() as Promise<AuthorizationStatus>;
  }

  static async getPermissionStatus(): Promise<AuthorizationStatus> {
    return NativeTracelet.getPermissionStatus() as Promise<AuthorizationStatus>;
  }

  static async requestNotificationPermission(): Promise<AuthorizationStatus> {
    return NativeTracelet.requestNotificationPermission() as Promise<AuthorizationStatus>;
  }

  static async getNotificationPermissionStatus(): Promise<AuthorizationStatus> {
    return NativeTracelet.getNotificationPermissionStatus() as Promise<AuthorizationStatus>;
  }

  static async requestMotionPermission(): Promise<AuthorizationStatus> {
    return NativeTracelet.requestMotionPermission() as Promise<AuthorizationStatus>;
  }

  static async getMotionPermissionStatus(): Promise<AuthorizationStatus> {
    return NativeTracelet.getMotionPermissionStatus() as Promise<AuthorizationStatus>;
  }

  static async requestTemporaryFullAccuracy(
    purposeKey: string
  ): Promise<AccuracyAuthorization> {
    return NativeTracelet.requestTemporaryFullAccuracy(
      purposeKey
    ) as Promise<AccuracyAuthorization>;
  }

  static async canScheduleExactAlarms(): Promise<boolean> {
    return NativeTracelet.canScheduleExactAlarms();
  }

  // ── Utilities ──────────────────────────────────────────────────────

  static async isPowerSaveMode(): Promise<boolean> {
    return NativeTracelet.isPowerSaveMode();
  }

  static async getProviderState(): Promise<ProviderChangeEvent> {
    return NativeTracelet.getProviderState() as Promise<ProviderChangeEvent>;
  }

  static async getSensors(): Promise<Sensors> {
    return NativeTracelet.getSensors() as Promise<Sensors>;
  }

  static async getDeviceInfo(): Promise<DeviceInfo> {
    return NativeTracelet.getDeviceInfo() as Promise<DeviceInfo>;
  }

  // ── Events ─────────────────────────────────────────────────────────

  static onLocation(callback: (location: Location) => void): Subscription {
    return emitter.addListener('onLocation', callback);
  }

  static onMotionChange(
    callback: (event: MotionChangeEvent) => void
  ): Subscription {
    return emitter.addListener('onMotionChange', callback);
  }

  static onActivityChange(
    callback: (event: ActivityChangeEvent) => void
  ): Subscription {
    return emitter.addListener('onActivityChange', callback);
  }

  static onProviderChange(
    callback: (event: ProviderChangeEvent) => void
  ): Subscription {
    return emitter.addListener('onProviderChange', callback);
  }

  static onGeofence(callback: (event: GeofenceEvent) => void): Subscription {
    return emitter.addListener('onGeofence', callback);
  }

  static onGeofencesChange(
    callback: (event: GeofencesChangeEvent) => void
  ): Subscription {
    return emitter.addListener('onGeofencesChange', callback);
  }

  static onHeartbeat(
    callback: (event: HeartbeatEvent) => void
  ): Subscription {
    return emitter.addListener('onHeartbeat', callback);
  }

  static onHttp(callback: (event: HttpEvent) => void): Subscription {
    return emitter.addListener('onHttp', callback);
  }

  static onSchedule(callback: (event: HeadlessEvent) => void): Subscription {
    return emitter.addListener('onSchedule', callback);
  }

  static onPowerSaveChange(
    callback: (isPowerSave: boolean) => void
  ): Subscription {
    return emitter.addListener('onPowerSaveChange', callback);
  }

  static onConnectivityChange(
    callback: (event: ConnectivityChangeEvent) => void
  ): Subscription {
    return emitter.addListener('onConnectivityChange', callback);
  }

  static onEnabledChange(callback: (enabled: boolean) => void): Subscription {
    return emitter.addListener('onEnabledChange', callback);
  }

  static onNotificationAction(
    callback: (action: string) => void
  ): Subscription {
    return emitter.addListener('onNotificationAction', callback);
  }

  static onAuthorization(
    callback: (event: AuthorizationEvent) => void
  ): Subscription {
    return emitter.addListener('onAuthorization', callback);
  }
}
