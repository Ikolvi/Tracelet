import type { ActivityType, ActivityConfidence } from './Enums';

/** GPS coordinates. */
export interface Coords {
  latitude: number;
  longitude: number;
  altitude: number;
  speed: number;
  heading: number;
  accuracy: number;
  speedAccuracy: number;
  headingAccuracy: number;
  altitudeAccuracy: number;
  floor?: number;
}

/** Activity classification from motion detection. */
export interface LocationActivity {
  type: ActivityType;
  confidence: ActivityConfidence;
}

/** Battery state at the time of location capture. */
export interface LocationBattery {
  level: number;
  isCharging: boolean;
}

/** Mock location heuristics (when mock detection is enabled). */
export interface MockHeuristics {
  satellites?: number;
  elapsedRealtimeDriftMs?: number;
  timestampDriftMs?: number;
  platformFlagMock?: boolean;
}

/** A location record. */
export interface Location {
  coords: Coords;
  timestamp: string;
  isMoving: boolean;
  uuid: string;
  odometer: number;
  isMock: boolean;
  mockHeuristics?: MockHeuristics;
  activity: LocationActivity;
  battery: LocationBattery;
  extras: Record<string, unknown>;
  event?: string;
  auditHash?: string;
  auditPreviousHash?: string;
  auditChainIndex?: number;
}

/** Options for getCurrentPosition(). */
export interface CurrentPositionOptions {
  timeout?: number;
  maximumAge?: number;
  desiredAccuracy?: number;
  persist?: boolean;
  extras?: Record<string, unknown>;
}

/** Options for getLastKnownLocation(). */
export interface LastKnownLocationOptions {
  maximumAge?: number;
}

/** Options for watchPosition(). */
export interface WatchPositionOptions {
  interval?: number;
  desiredAccuracy?: number;
  persist?: boolean;
  extras?: Record<string, unknown>;
}

/** SQL query for getLocations(). */
export interface SQLQuery {
  limit?: number;
  offset?: number;
  order?: string;
}
