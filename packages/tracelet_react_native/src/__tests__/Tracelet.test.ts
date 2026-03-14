import './setup';
import { Tracelet } from '../Tracelet';
import { TraceletReactNative, mockState, mockLocation } from './setup';
import { DesiredAccuracy, TrackingMode, AuthorizationStatus } from '../types/Enums';

describe('Tracelet', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // ── Lifecycle ──────────────────────────────────────────────────

  describe('Lifecycle', () => {
    it('ready() calls native with config and returns state', async () => {
      const config = { geo: { desiredAccuracy: DesiredAccuracy.high } };
      const state = await Tracelet.ready(config);
      expect(TraceletReactNative.ready).toHaveBeenCalledWith(config);
      expect(state).toHaveProperty('enabled');
    });

    it('ready() passes full nested config correctly', async () => {
      const config = {
        geo: { desiredAccuracy: DesiredAccuracy.high, distanceFilter: 25 },
        app: { stopOnTerminate: false, startOnBoot: true },
        http: { url: 'https://example.com/locations', autoSync: true },
        logger: { level: 4 },
      };
      await Tracelet.ready(config);
      expect(TraceletReactNative.ready).toHaveBeenCalledWith(config);
    });

    it('start() returns state with enabled=true', async () => {
      const state = await Tracelet.start();
      expect(TraceletReactNative.start).toHaveBeenCalled();
      expect(state.enabled).toBe(true);
    });

    it('stop() returns state with enabled=false', async () => {
      const state = await Tracelet.stop();
      expect(TraceletReactNative.stop).toHaveBeenCalled();
      expect(state.enabled).toBe(false);
    });

    it('startGeofences() returns state with trackingMode=1', async () => {
      const state = await Tracelet.startGeofences();
      expect(TraceletReactNative.startGeofences).toHaveBeenCalled();
      expect(state.trackingMode).toBe(TrackingMode.geofences);
    });

    it('startPeriodic() returns state with trackingMode=2', async () => {
      const state = await Tracelet.startPeriodic();
      expect(TraceletReactNative.startPeriodic).toHaveBeenCalled();
      expect(state.trackingMode).toBe(TrackingMode.periodic);
    });

    it('getState() returns current state', async () => {
      const state = await Tracelet.getState();
      expect(TraceletReactNative.getState).toHaveBeenCalled();
      expect(state).toEqual(mockState);
    });

    it('setConfig() merges config and returns state', async () => {
      const config = { geo: { distanceFilter: 50 } };
      await Tracelet.setConfig(config);
      expect(TraceletReactNative.setConfig).toHaveBeenCalledWith(config);
    });

    it('reset() resets plugin and returns state', async () => {
      await Tracelet.reset();
      expect(TraceletReactNative.reset).toHaveBeenCalled();
    });

    it('reset() accepts an optional config', async () => {
      const config = { geo: { distanceFilter: 10 } };
      await Tracelet.reset(config);
      expect(TraceletReactNative.reset).toHaveBeenCalledWith(config);
    });
  });

  // ── Lifecycle Error Handling ───────────────────────────────────

  describe('Lifecycle Error Handling', () => {
    it('start() rejects if not ready', async () => {
      TraceletReactNative.start.mockRejectedValueOnce(
        new Error('ERR_NOT_READY: Call ready() before start()')
      );
      await expect(Tracelet.start()).rejects.toThrow('ERR_NOT_READY');
    });

    it('startGeofences() rejects if not ready', async () => {
      TraceletReactNative.startGeofences.mockRejectedValueOnce(
        new Error('ERR_NOT_READY')
      );
      await expect(Tracelet.startGeofences()).rejects.toThrow();
    });

    it('startPeriodic() rejects if permission denied', async () => {
      TraceletReactNative.startPeriodic.mockRejectedValueOnce(
        new Error('ERR_PERMISSION_DENIED')
      );
      await expect(Tracelet.startPeriodic()).rejects.toThrow('ERR_PERMISSION_DENIED');
    });
  });

  // ── Location ───────────────────────────────────────────────────

  describe('Location', () => {
    it('getCurrentPosition() returns location', async () => {
      const loc = await Tracelet.getCurrentPosition();
      expect(TraceletReactNative.getCurrentPosition).toHaveBeenCalled();
      expect(loc.coords.latitude).toBe(37.7749);
    });

    it('getCurrentPosition() passes options correctly', async () => {
      await Tracelet.getCurrentPosition({
        timeout: 30,
        maximumAge: 5000,
        desiredAccuracy: DesiredAccuracy.high,
        persist: true,
      });
      expect(TraceletReactNative.getCurrentPosition).toHaveBeenCalledWith({
        timeout: 30,
        maximumAge: 5000,
        desiredAccuracy: DesiredAccuracy.high,
        persist: true,
      });
    });

    it('getCurrentPosition() uses empty options when none provided', async () => {
      await Tracelet.getCurrentPosition();
      expect(TraceletReactNative.getCurrentPosition).toHaveBeenCalledWith({});
    });

    it('getCurrentPosition() rejects on timeout', async () => {
      TraceletReactNative.getCurrentPosition.mockRejectedValueOnce(
        new Error('ERR_LOCATION: Timed out')
      );
      await expect(Tracelet.getCurrentPosition()).rejects.toThrow('ERR_LOCATION');
    });

    it('getLastKnownLocation() returns location or null', async () => {
      const loc = await Tracelet.getLastKnownLocation();
      expect(TraceletReactNative.getLastKnownLocation).toHaveBeenCalled();
      expect(loc).not.toBeNull();
    });

    it('getLastKnownLocation() can return null', async () => {
      TraceletReactNative.getLastKnownLocation.mockResolvedValueOnce(null);
      const loc = await Tracelet.getLastKnownLocation();
      expect(loc).toBeNull();
    });

    it('watchPosition() returns a watchId', async () => {
      const watchId = await Tracelet.watchPosition({});
      expect(TraceletReactNative.watchPosition).toHaveBeenCalled();
      expect(typeof watchId).toBe('number');
    });

    it('stopWatchPosition() returns true', async () => {
      const result = await Tracelet.stopWatchPosition(1);
      expect(TraceletReactNative.stopWatchPosition).toHaveBeenCalledWith(1);
      expect(result).toBe(true);
    });

    it('changePace() changes pace', async () => {
      const result = await Tracelet.changePace(true);
      expect(TraceletReactNative.changePace).toHaveBeenCalledWith(true);
      expect(result).toBe(true);
    });

    it('getOdometer() returns number', async () => {
      const odometer = await Tracelet.getOdometer();
      expect(typeof odometer).toBe('number');
    });

    it('setOdometer() sets value', async () => {
      await Tracelet.setOdometer(1000);
      expect(TraceletReactNative.setOdometer).toHaveBeenCalledWith(1000);
    });

    it('location has complete structure', async () => {
      const loc = await Tracelet.getCurrentPosition();
      expect(loc.coords).toBeDefined();
      expect(loc.coords.latitude).toBeDefined();
      expect(loc.coords.longitude).toBeDefined();
      expect(loc.coords.accuracy).toBeDefined();
      expect(loc.timestamp).toBeDefined();
      expect(loc.uuid).toBeDefined();
      expect(loc.activity).toBeDefined();
      expect(loc.battery).toBeDefined();
    });
  });

  // ── Geofencing ─────────────────────────────────────────────────

  describe('Geofencing', () => {
    const geofence = {
      identifier: 'home',
      latitude: 37.7749,
      longitude: -122.4194,
      radius: 200,
      notifyOnEntry: true,
      notifyOnExit: true,
      notifyOnDwell: false,
    };

    it('addGeofence() adds a geofence', async () => {
      const result = await Tracelet.addGeofence(geofence);
      expect(TraceletReactNative.addGeofence).toHaveBeenCalledWith(geofence);
      expect(result).toBe(true);
    });

    it('addGeofences() adds multiple geofences', async () => {
      const second = { ...geofence, identifier: 'work', latitude: 37.78 };
      const result = await Tracelet.addGeofences([geofence, second]);
      expect(TraceletReactNative.addGeofences).toHaveBeenCalledWith([geofence, second]);
      expect(result).toBe(true);
    });

    it('removeGeofence() removes by identifier', async () => {
      const result = await Tracelet.removeGeofence('home');
      expect(TraceletReactNative.removeGeofence).toHaveBeenCalledWith('home');
      expect(result).toBe(true);
    });

    it('removeGeofences() removes all', async () => {
      const result = await Tracelet.removeGeofences();
      expect(result).toBe(true);
    });

    it('getGeofences() returns array', async () => {
      const geofences = await Tracelet.getGeofences();
      expect(Array.isArray(geofences)).toBe(true);
    });

    it('getGeofence() returns single geofence', async () => {
      TraceletReactNative.getGeofence.mockResolvedValueOnce(geofence);
      const result = await Tracelet.getGeofence('home');
      expect(TraceletReactNative.getGeofence).toHaveBeenCalledWith('home');
      expect(result).toEqual(geofence);
    });

    it('getGeofence() returns null for non-existent', async () => {
      const result = await Tracelet.getGeofence('nonexistent');
      expect(result).toBeNull();
    });

    it('geofenceExists() returns boolean', async () => {
      const exists = await Tracelet.geofenceExists('home');
      expect(typeof exists).toBe('boolean');
    });

    it('geofenceExists() returns true when exists', async () => {
      TraceletReactNative.geofenceExists.mockResolvedValueOnce(true);
      const exists = await Tracelet.geofenceExists('home');
      expect(exists).toBe(true);
    });
  });

  // ── Persistence ────────────────────────────────────────────────

  describe('Persistence', () => {
    it('getLocations() returns array', async () => {
      const locs = await Tracelet.getLocations();
      expect(Array.isArray(locs)).toBe(true);
    });

    it('getLocations() passes query options', async () => {
      await Tracelet.getLocations({ limit: 10, order: 'DESC' });
      expect(TraceletReactNative.getLocations).toHaveBeenCalledWith({ limit: 10, order: 'DESC' });
    });

    it('getLocations() returns populated list', async () => {
      TraceletReactNative.getLocations.mockResolvedValueOnce([mockLocation, mockLocation]);
      const locs = await Tracelet.getLocations();
      expect(locs).toHaveLength(2);
    });

    it('getCount() returns number', async () => {
      const count = await Tracelet.getCount();
      expect(typeof count).toBe('number');
    });

    it('getCount() returns positive count', async () => {
      TraceletReactNative.getCount.mockResolvedValueOnce(42);
      const count = await Tracelet.getCount();
      expect(count).toBe(42);
    });

    it('destroyLocations() returns boolean', async () => {
      const result = await Tracelet.destroyLocations();
      expect(result).toBe(true);
    });

    it('destroyLocation() deletes by uuid', async () => {
      const result = await Tracelet.destroyLocation('uuid-123');
      expect(TraceletReactNative.destroyLocation).toHaveBeenCalledWith('uuid-123');
      expect(result).toBe(true);
    });

    it('insertLocation() returns uuid', async () => {
      const uuid = await Tracelet.insertLocation({});
      expect(typeof uuid).toBe('string');
    });

    it('insertLocation() returns correct uuid', async () => {
      TraceletReactNative.insertLocation.mockResolvedValueOnce('custom-uuid-456');
      const uuid = await Tracelet.insertLocation({
        coords: { latitude: 37.77, longitude: -122.41 },
      } as any);
      expect(uuid).toBe('custom-uuid-456');
    });
  });

  // ── HTTP Sync ──────────────────────────────────────────────────

  describe('HTTP Sync', () => {
    it('sync() returns array', async () => {
      const result = await Tracelet.sync();
      expect(Array.isArray(result)).toBe(true);
    });

    it('sync() returns synced locations', async () => {
      TraceletReactNative.sync.mockResolvedValueOnce([mockLocation]);
      const result = await Tracelet.sync();
      expect(result).toHaveLength(1);
      expect(result[0]).toEqual(mockLocation);
    });
  });

  // ── Permissions ────────────────────────────────────────────────

  describe('Permissions', () => {
    it('requestPermission() returns status number', async () => {
      const status = await Tracelet.requestPermission();
      expect(typeof status).toBe('number');
    });

    it('getPermissionStatus() returns status number', async () => {
      const status = await Tracelet.getPermissionStatus();
      expect(typeof status).toBe('number');
    });

    it('getPermissionStatus() returns AuthorizationStatus values', async () => {
      TraceletReactNative.getPermissionStatus.mockResolvedValueOnce(AuthorizationStatus.always);
      const status = await Tracelet.getPermissionStatus();
      expect(status).toBe(AuthorizationStatus.always);
    });

    it('requestMotionPermission() returns status', async () => {
      const status = await Tracelet.requestMotionPermission();
      expect(typeof status).toBe('number');
    });

    it('requestNotificationPermission() returns status', async () => {
      const status = await Tracelet.requestNotificationPermission();
      expect(typeof status).toBe('number');
    });

    it('getNotificationPermissionStatus() returns status', async () => {
      const status = await Tracelet.getNotificationPermissionStatus();
      expect(typeof status).toBe('number');
    });

    it('getMotionPermissionStatus() returns status', async () => {
      const status = await Tracelet.getMotionPermissionStatus();
      expect(typeof status).toBe('number');
    });

    it('requestTemporaryFullAccuracy() takes purposeKey', async () => {
      const result = await Tracelet.requestTemporaryFullAccuracy('navigation');
      expect(TraceletReactNative.requestTemporaryFullAccuracy).toHaveBeenCalledWith('navigation');
      expect(typeof result).toBe('number');
    });

    it('canScheduleExactAlarms() returns boolean', async () => {
      const can = await Tracelet.canScheduleExactAlarms();
      expect(typeof can).toBe('boolean');
    });
  });

  // ── Utilities ──────────────────────────────────────────────────

  describe('Utilities', () => {
    it('isPowerSaveMode() returns boolean', async () => {
      const result = await Tracelet.isPowerSaveMode();
      expect(typeof result).toBe('boolean');
    });

    it('getProviderState() returns object', async () => {
      const state = await Tracelet.getProviderState();
      expect(typeof state).toBe('object');
    });

    it('getSensors() returns object', async () => {
      const sensors = await Tracelet.getSensors();
      expect(typeof sensors).toBe('object');
    });

    it('getDeviceInfo() returns device info', async () => {
      const info = await Tracelet.getDeviceInfo();
      expect(info).toHaveProperty('platform');
      expect(info).toHaveProperty('manufacturer');
      expect(info).toHaveProperty('model');
      expect(info).toHaveProperty('version');
      expect(info).toHaveProperty('framework');
      expect(info.framework).toBe('react-native');
    });
  });

  // ── Events ─────────────────────────────────────────────────────

  describe('Events', () => {
    it('onLocation() returns subscription with remove()', () => {
      const sub = Tracelet.onLocation(() => {});
      expect(sub).toHaveProperty('remove');
      expect(typeof sub.remove).toBe('function');
    });

    it('onLocation() subscription.remove() is callable', () => {
      const sub = Tracelet.onLocation(() => {});
      expect(() => sub.remove()).not.toThrow();
    });

    it('onMotionChange() returns subscription', () => {
      const sub = Tracelet.onMotionChange(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onActivityChange() returns subscription', () => {
      const sub = Tracelet.onActivityChange(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onGeofence() returns subscription', () => {
      const sub = Tracelet.onGeofence(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onGeofencesChange() returns subscription', () => {
      const sub = Tracelet.onGeofencesChange(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onHeartbeat() returns subscription', () => {
      const sub = Tracelet.onHeartbeat(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onHttp() returns subscription', () => {
      const sub = Tracelet.onHttp(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onSchedule() returns subscription', () => {
      const sub = Tracelet.onSchedule(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onEnabledChange() returns subscription', () => {
      const sub = Tracelet.onEnabledChange(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onProviderChange() returns subscription', () => {
      const sub = Tracelet.onProviderChange(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onPowerSaveChange() returns subscription', () => {
      const sub = Tracelet.onPowerSaveChange(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onConnectivityChange() returns subscription', () => {
      const sub = Tracelet.onConnectivityChange(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onAuthorization() returns subscription', () => {
      const sub = Tracelet.onAuthorization(() => {});
      expect(sub).toHaveProperty('remove');
    });

    it('onNotificationAction() returns subscription', () => {
      const sub = Tracelet.onNotificationAction(() => {});
      expect(sub).toHaveProperty('remove');
    });
  });
});
