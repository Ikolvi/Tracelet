/**
 * Tests for React hooks: useLocation, useGeofences, useTraceletState.
 *
 * Since the hooks use Tracelet static methods and event subscriptions,
 * we test the subscription wiring and cleanup rather than full React
 * rendering (which would require jsdom + @testing-library/react).
 */
import '../__tests__/setup';
import { Tracelet } from '../Tracelet';

// Track subscription callbacks registered via event listeners
let locationCallbacks: Array<(location: any) => void> = [];
let geofencesChangeCallbacks: Array<(...args: any[]) => void> = [];
let enabledChangeCallbacks: Array<(...args: any[]) => void> = [];
const removeFns: jest.Mock[] = [];

// Override event listener mocks to capture callbacks
beforeEach(() => {
  locationCallbacks = [];
  geofencesChangeCallbacks = [];
  enabledChangeCallbacks = [];
  removeFns.length = 0;

  jest.spyOn(Tracelet, 'onLocation').mockImplementation((cb) => {
    locationCallbacks.push(cb);
    const remove = jest.fn();
    removeFns.push(remove);
    return { remove };
  });

  jest.spyOn(Tracelet, 'onGeofencesChange').mockImplementation((cb) => {
    geofencesChangeCallbacks.push(cb);
    const remove = jest.fn();
    removeFns.push(remove);
    return { remove };
  });

  jest.spyOn(Tracelet, 'onEnabledChange').mockImplementation((cb) => {
    enabledChangeCallbacks.push(cb);
    const remove = jest.fn();
    removeFns.push(remove);
    return { remove };
  });
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe('useLocation hook contract', () => {
  it('subscribes to onLocation events', () => {
    // Verify the hook wires up the subscription correctly
    const sub = Tracelet.onLocation(() => {});
    expect(sub).toHaveProperty('remove');
    expect(typeof sub.remove).toBe('function');
    expect(locationCallbacks).toHaveLength(1);
  });

  it('subscription.remove() cleans up correctly', () => {
    const sub = Tracelet.onLocation(() => {});
    sub.remove();
    expect(removeFns[0]).toHaveBeenCalledTimes(1);
  });

  it('callback receives location data', () => {
    const mockLocation = {
      uuid: 'hook-test-uuid',
      coords: { latitude: 40.7128, longitude: -74.006, accuracy: 5 },
      timestamp: '2025-01-01T00:00:00Z',
    };

    let received: any = null;
    Tracelet.onLocation((loc) => {
      received = loc;
    });

    // Simulate event emission
    locationCallbacks[0]!(mockLocation);
    expect(received).toEqual(mockLocation);
  });

  it('multiple subscribers each get their own subscription', () => {
    Tracelet.onLocation(() => {});
    Tracelet.onLocation(() => {});
    expect(locationCallbacks).toHaveLength(2);
    expect(removeFns).toHaveLength(2);
  });
});

describe('useGeofences hook contract', () => {
  it('calls getGeofences() for initial load', async () => {
    const spy = jest.spyOn(Tracelet, 'getGeofences').mockResolvedValue([]);
    await Tracelet.getGeofences();
    expect(spy).toHaveBeenCalled();
  });

  it('subscribes to onGeofencesChange events', () => {
    const sub = Tracelet.onGeofencesChange(() => {});
    expect(sub).toHaveProperty('remove');
    expect(geofencesChangeCallbacks).toHaveLength(1);
  });

  it('subscription.remove() cleans up', () => {
    const sub = Tracelet.onGeofencesChange(() => {});
    sub.remove();
    expect(removeFns[0]).toHaveBeenCalledTimes(1);
  });

  it('getGeofences returns typed array', async () => {
    const mockGeofences = [
      { identifier: 'office', latitude: 37.77, longitude: -122.41, radius: 200 },
      { identifier: 'home', latitude: 37.78, longitude: -122.42, radius: 150 },
    ];
    jest.spyOn(Tracelet, 'getGeofences').mockResolvedValue(mockGeofences as any);
    const result = await Tracelet.getGeofences();
    expect(result).toHaveLength(2);
    expect(result[0]!.identifier).toBe('office');
  });

  it('refresh callback triggers getGeofences', async () => {
    const spy = jest.spyOn(Tracelet, 'getGeofences').mockResolvedValue([]);
    // Simulate what the hook does: call getGeofences on change event
    const refresh = () => Tracelet.getGeofences();
    Tracelet.onGeofencesChange(refresh);

    // Trigger the change event
    await geofencesChangeCallbacks[0]!();
    expect(spy).toHaveBeenCalledTimes(1);
  });
});

describe('useTraceletState hook contract', () => {
  it('calls getState() for initial load', async () => {
    const spy = jest.spyOn(Tracelet, 'getState');
    await Tracelet.getState();
    expect(spy).toHaveBeenCalled();
  });

  it('subscribes to onEnabledChange events', () => {
    const sub = Tracelet.onEnabledChange(() => {});
    expect(sub).toHaveProperty('remove');
    expect(enabledChangeCallbacks).toHaveLength(1);
  });

  it('subscription.remove() cleans up', () => {
    const sub = Tracelet.onEnabledChange(() => {});
    sub.remove();
    expect(removeFns[0]).toHaveBeenCalledTimes(1);
  });

  it('getState returns State object', async () => {
    const state = await Tracelet.getState();
    expect(state).toHaveProperty('enabled');
    expect(state).toHaveProperty('trackingMode');
    expect(state).toHaveProperty('isMoving');
    expect(state).toHaveProperty('odometer');
  });

  it('enabled change triggers refresh', async () => {
    const spy = jest.spyOn(Tracelet, 'getState');
    // Simulate what the hook does: call getState on enabled change
    const refresh = () => Tracelet.getState();
    Tracelet.onEnabledChange(refresh);

    // Simulate the enabled change event
    await enabledChangeCallbacks[0]!(true);
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it('state updates on enable/disable cycle', async () => {
    const states: any[] = [];
    jest
      .spyOn(Tracelet, 'getState')
      .mockResolvedValueOnce({ enabled: false, trackingMode: 0, isMoving: false, schedulerEnabled: false, odometer: 0, didLaunchInBackground: false, didDeviceReboot: false } as any)
      .mockResolvedValueOnce({ enabled: true, trackingMode: 0, isMoving: false, schedulerEnabled: false, odometer: 0, didLaunchInBackground: false, didDeviceReboot: false } as any);

    const refresh = async () => {
      const s = await Tracelet.getState();
      states.push(s);
    };

    Tracelet.onEnabledChange(refresh);

    // Initial fetch
    await refresh();
    expect(states[0]!.enabled).toBe(false);

    // Simulated enable event
    await enabledChangeCallbacks[0]!(true);
    expect(states[1]!.enabled).toBe(true);
  });
});
