import type { TrackingMode } from './Enums';
import type { Config } from './Config';

/** Plugin state returned by ready(), start(), stop(), getState(). */
export interface State {
  enabled: boolean;
  trackingMode: TrackingMode;
  isMoving: boolean;
  schedulerEnabled: boolean;
  odometer: number;
  didLaunchInBackground: boolean;
  didDeviceReboot: boolean;
  config?: Config;
}
