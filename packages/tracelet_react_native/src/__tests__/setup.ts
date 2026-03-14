/**
 * Jest mock for NativeModules.TraceletReactNative.
 *
 * All methods return resolved promises with sensible defaults.
 */

const mockState = {
  enabled: false,
  trackingMode: 0,
  isMoving: false,
  schedulerEnabled: false,
  odometer: 0,
  didLaunchInBackground: false,
  didDeviceReboot: false,
  config: {},
};

const mockLocation = {
  uuid: 'test-uuid-1234',
  timestamp: '2024-01-01T00:00:00.000Z',
  isMoving: false,
  event: 'motionchange',
  coords: {
    latitude: 37.7749,
    longitude: -122.4194,
    accuracy: 10,
    speed: 0,
    heading: 0,
    altitude: 0,
    altitudeAccuracy: 5,
    speedAccuracy: 1,
    headingAccuracy: 5,
  },
  activity: { type: 'still', confidence: 100 },
  battery: { level: 0.85, isCharging: false },
  odometer: 0,
  mock: false,
};

const TraceletReactNative = {
  ready: jest.fn().mockResolvedValue({ ...mockState, enabled: false }),
  start: jest.fn().mockResolvedValue({ ...mockState, enabled: true }),
  stop: jest.fn().mockResolvedValue({ ...mockState, enabled: false }),
  startGeofences: jest.fn().mockResolvedValue({ ...mockState, enabled: true, trackingMode: 1 }),
  startPeriodic: jest.fn().mockResolvedValue({ ...mockState, enabled: true, trackingMode: 2 }),
  getState: jest.fn().mockResolvedValue(mockState),
  setConfig: jest.fn().mockResolvedValue(mockState),
  reset: jest.fn().mockResolvedValue(mockState),

  getCurrentPosition: jest.fn().mockResolvedValue(mockLocation),
  getLastKnownLocation: jest.fn().mockResolvedValue(mockLocation),
  watchPosition: jest.fn().mockResolvedValue(1),
  stopWatchPosition: jest.fn().mockResolvedValue(true),
  changePace: jest.fn().mockResolvedValue(true),
  getOdometer: jest.fn().mockResolvedValue(0),
  setOdometer: jest.fn().mockResolvedValue(mockLocation),

  addGeofence: jest.fn().mockResolvedValue(true),
  addGeofences: jest.fn().mockResolvedValue(true),
  removeGeofence: jest.fn().mockResolvedValue(true),
  removeGeofences: jest.fn().mockResolvedValue(true),
  getGeofences: jest.fn().mockResolvedValue([]),
  getGeofence: jest.fn().mockResolvedValue(null),
  geofenceExists: jest.fn().mockResolvedValue(false),

  getLocations: jest.fn().mockResolvedValue([]),
  getCount: jest.fn().mockResolvedValue(0),
  destroyLocations: jest.fn().mockResolvedValue(true),
  destroyLocation: jest.fn().mockResolvedValue(true),
  insertLocation: jest.fn().mockResolvedValue('new-uuid'),

  sync: jest.fn().mockResolvedValue([]),

  requestPermission: jest.fn().mockResolvedValue(3),
  getPermissionStatus: jest.fn().mockResolvedValue(3),
  requestNotificationPermission: jest.fn().mockResolvedValue(3),
  getNotificationPermissionStatus: jest.fn().mockResolvedValue(3),
  requestMotionPermission: jest.fn().mockResolvedValue(3),
  getMotionPermissionStatus: jest.fn().mockResolvedValue(3),
  requestTemporaryFullAccuracy: jest.fn().mockResolvedValue(0),
  canScheduleExactAlarms: jest.fn().mockResolvedValue(true),

  isPowerSaveMode: jest.fn().mockResolvedValue(false),
  getProviderState: jest.fn().mockResolvedValue({}),
  getSensors: jest.fn().mockResolvedValue({}),
  getDeviceInfo: jest.fn().mockResolvedValue({
    manufacturer: 'Apple',
    model: 'iPhone',
    version: '17.0',
    platform: 'ios',
    framework: 'react-native',
  }),

  addListener: jest.fn(),
  removeListeners: jest.fn(),
};

jest.mock('react-native', () => ({
  NativeModules: {
    TraceletReactNative,
  },
  NativeEventEmitter: jest.fn().mockImplementation(() => ({
    addListener: jest.fn().mockReturnValue({ remove: jest.fn() }),
    removeAllListeners: jest.fn(),
  })),
  TurboModuleRegistry: {
    getEnforcing: jest.fn().mockReturnValue(TraceletReactNative),
  },
}));

export { TraceletReactNative, mockState, mockLocation };
