/** A circular geofence. */
export interface Geofence {
  identifier: string;
  latitude: number;
  longitude: number;
  radius: number;
  notifyOnEntry?: boolean;
  notifyOnExit?: boolean;
  notifyOnDwell?: boolean;
  loiteringDelay?: number;
  extras?: Record<string, unknown>;
  vertices?: Array<[number, number]>;
}
