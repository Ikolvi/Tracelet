import type { ActivityType, ActivityConfidence, GeofenceAction, AuthorizationStatus } from './Enums';
import type { Location } from './Location';
import type { Geofence } from './Geofence';

/** Motion change event. */
export interface MotionChangeEvent {
  isMoving: boolean;
  location: Location;
}

/** Activity recognition event. */
export interface ActivityChangeEvent {
  activity: ActivityType;
  confidence: ActivityConfidence;
}

/** Location provider state change. */
export interface ProviderChangeEvent {
  enabled: boolean;
  gps: boolean;
  network: boolean;
  status: AuthorizationStatus;
  accuracyAuthorization?: number;
}

/** Geofence transition event. */
export interface GeofenceEvent {
  identifier: string;
  action: GeofenceAction;
  location: Location;
  extras?: Record<string, unknown>;
}

/** Geofence set change event. */
export interface GeofencesChangeEvent {
  on: Geofence[];
  off: string[];
}

/** Heartbeat event (periodic check-in). */
export interface HeartbeatEvent {
  location: Location;
}

/** HTTP sync event. */
export interface HttpEvent {
  success: boolean;
  status: number;
  responseText: string;
}

/** Network connectivity change event. */
export interface ConnectivityChangeEvent {
  connected: boolean;
}

/** Authorization change event. */
export interface AuthorizationEvent {
  status: AuthorizationStatus;
  request: string;
}

/** Headless/background event. */
export interface HeadlessEvent {
  name: string;
  params: Record<string, unknown>;
}

/** Device sensor capabilities. */
export interface Sensors {
  accelerometer: boolean;
  gyroscope: boolean;
  magnetometer: boolean;
  motionHardware: boolean;
  significantMotion: boolean;
}

/** Device information. */
export interface DeviceInfo {
  model: string;
  manufacturer: string;
  version: string;
  platform: string;
  framework: string;
}

/** Budget adjustment event (BatteryBudgetEngine). */
export interface BudgetAdjustmentEvent {
  currentBatteryDrain: number;
  targetBudget: number;
  newDistanceFilter: number;
  newDesiredAccuracy: number;
  newPeriodicInterval?: number;
}
