import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  // Lifecycle
  ready(config: Object): Promise<Object>;
  start(): Promise<Object>;
  stop(): Promise<Object>;
  startGeofences(): Promise<Object>;
  startPeriodic(): Promise<Object>;
  getState(): Promise<Object>;
  setConfig(config: Object): Promise<Object>;
  reset(config?: Object): Promise<Object>;

  // Location
  getCurrentPosition(options: Object): Promise<Object>;
  getLastKnownLocation(options?: Object): Promise<Object | null>;
  watchPosition(options: Object): Promise<number>;
  stopWatchPosition(watchId: number): Promise<boolean>;
  changePace(isMoving: boolean): Promise<boolean>;
  getOdometer(): Promise<number>;
  setOdometer(value: number): Promise<Object>;

  // Geofencing
  addGeofence(geofence: Object): Promise<boolean>;
  addGeofences(geofences: Object[]): Promise<boolean>;
  removeGeofence(identifier: string): Promise<boolean>;
  removeGeofences(): Promise<boolean>;
  getGeofences(): Promise<Object[]>;
  getGeofence(identifier: string): Promise<Object | null>;
  geofenceExists(identifier: string): Promise<boolean>;

  // Persistence
  getLocations(query?: Object): Promise<Object[]>;
  getCount(): Promise<number>;
  destroyLocations(): Promise<boolean>;
  destroyLocation(uuid: string): Promise<boolean>;
  insertLocation(location: Object): Promise<string>;

  // HTTP Sync
  sync(): Promise<Object[]>;

  // Permissions
  requestPermission(): Promise<number>;
  getPermissionStatus(): Promise<number>;
  requestNotificationPermission(): Promise<number>;
  getNotificationPermissionStatus(): Promise<number>;
  requestMotionPermission(): Promise<number>;
  getMotionPermissionStatus(): Promise<number>;
  requestTemporaryFullAccuracy(purposeKey: string): Promise<number>;
  canScheduleExactAlarms(): Promise<boolean>;

  // Utilities
  isPowerSaveMode(): Promise<boolean>;
  getProviderState(): Promise<Object>;
  getSensors(): Promise<Object>;
  getDeviceInfo(): Promise<Object>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TraceletReactNative');
