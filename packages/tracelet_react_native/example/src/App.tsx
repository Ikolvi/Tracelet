import React, { useState, useCallback, useEffect } from 'react';
import {
  AppRegistry,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import {
  Tracelet,
  type Location,
  type State,
  type Subscription,
  DesiredAccuracy,
} from '@tracelet/react-native';

// Register headless task for background events (Android)
AppRegistry.registerHeadlessTask('TraceletHeadlessTask', () => async (event) => {
  console.log('[Tracelet Headless]', event?.name, event?.event);
});

export default function App() {
  const [state, setState] = useState<State | null>(null);
  const [location, setLocation] = useState<Location | null>(null);
  const [events, setEvents] = useState<string[]>([]);
  const [subscriptions, setSubscriptions] = useState<Subscription[]>([]);
  const [geofenceId, setGeofenceId] = useState('office');
  const [locationCount, setLocationCount] = useState(0);

  const log = useCallback((msg: string) => {
    setEvents((prev) => [`[${new Date().toLocaleTimeString()}] ${msg}`, ...prev].slice(0, 80));
  }, []);

  // Subscribe to all events after ready
  const subscribeAll = useCallback(() => {
    const subs: Subscription[] = [
      Tracelet.onLocation((loc) => {
        setLocation(loc);
        log(`location: ${loc.coords.latitude.toFixed(5)}, ${loc.coords.longitude.toFixed(5)}`);
      }),
      Tracelet.onMotionChange((e) =>
        log(`motionChange: isMoving=${e.isMoving}`)
      ),
      Tracelet.onActivityChange((e) =>
        log(`activity: ${e.activity} (${e.confidence})`)
      ),
      Tracelet.onGeofence((e) =>
        log(`geofence: ${e.identifier} ${e.action}`)
      ),
      Tracelet.onHeartbeat(() => log('heartbeat')),
      Tracelet.onHttp((e) =>
        log(`http: status=${e.status} success=${e.success}`)
      ),
      Tracelet.onProviderChange((e) =>
        log(`provider: enabled=${e.enabled} gps=${e.gps}`)
      ),
      Tracelet.onEnabledChange((enabled) =>
        log(`enabledChange: ${enabled}`)
      ),
      Tracelet.onConnectivityChange((e) =>
        log(`connectivity: connected=${e.connected}`)
      ),
    ];
    setSubscriptions(subs);
    return subs;
  }, [log]);

  const unsubscribeAll = useCallback(() => {
    subscriptions.forEach((s) => s.remove());
    setSubscriptions([]);
  }, [subscriptions]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      subscriptions.forEach((s) => s.remove());
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const onReady = useCallback(async () => {
    try {
      const s = await Tracelet.ready({
        geo: {
          desiredAccuracy: DesiredAccuracy.high,
          distanceFilter: 10,
        },
        app: {
          stopOnTerminate: false,
          startOnBoot: true,
          heartbeatInterval: 60,
        },
        logger: { level: 4 },
      });
      setState(s);
      subscribeAll();
      log('ready() OK');
    } catch (e) {
      log('ready() ERROR: ' + String(e));
    }
  }, [log, subscribeAll]);

  const onStart = useCallback(async () => {
    try {
      const s = await Tracelet.start();
      setState(s);
      log('start() → tracking');
    } catch (e) {
      log('start() ERROR: ' + String(e));
    }
  }, [log]);

  const onStop = useCallback(async () => {
    try {
      const s = await Tracelet.stop();
      setState(s);
      unsubscribeAll();
      log('stop() → idle');
    } catch (e) {
      log('stop() ERROR: ' + String(e));
    }
  }, [log, unsubscribeAll]);

  const onStartPeriodic = useCallback(async () => {
    try {
      const s = await Tracelet.startPeriodic();
      setState(s);
      log('startPeriodic() → periodic');
    } catch (e) {
      log('startPeriodic() ERROR: ' + String(e));
    }
  }, [log]);

  const onGetCurrentPosition = useCallback(async () => {
    try {
      const loc = await Tracelet.getCurrentPosition({
        desiredAccuracy: DesiredAccuracy.high,
        timeout: 30,
        maximumAge: 5000,
      });
      setLocation(loc);
      log(`gps: ${loc.coords.latitude.toFixed(5)}, ${loc.coords.longitude.toFixed(5)}`);
    } catch (e) {
      log('getCurrentPosition ERROR: ' + String(e));
    }
  }, [log]);

  const onAddGeofence = useCallback(async () => {
    if (!location) {
      log('Get a location first to use as geofence center');
      return;
    }
    try {
      await Tracelet.addGeofence({
        identifier: geofenceId,
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
        radius: 200,
        notifyOnEntry: true,
        notifyOnExit: true,
        notifyOnDwell: true,
        loiteringDelay: 30000,
      });
      log(`addGeofence("${geofenceId}") OK`);
    } catch (e) {
      log('addGeofence ERROR: ' + String(e));
    }
  }, [geofenceId, location, log]);

  const onRemoveGeofences = useCallback(async () => {
    try {
      await Tracelet.removeGeofences();
      log('removeGeofences() OK');
    } catch (e) {
      log('removeGeofences ERROR: ' + String(e));
    }
  }, [log]);

  const onSync = useCallback(async () => {
    try {
      const synced = await Tracelet.sync();
      log(`sync() → ${synced.length} locations synced`);
    } catch (e) {
      log('sync() ERROR: ' + String(e));
    }
  }, [log]);

  const onGetCount = useCallback(async () => {
    try {
      const count = await Tracelet.getCount();
      setLocationCount(count);
      log(`getCount() → ${count}`);
    } catch (e) {
      log('getCount() ERROR: ' + String(e));
    }
  }, [log]);

  const onRequestPermission = useCallback(async () => {
    try {
      const status = await Tracelet.requestPermission();
      log(`requestPermission() → status=${status}`);
    } catch (e) {
      log('requestPermission ERROR: ' + String(e));
    }
  }, [log]);

  return (
    <SafeAreaView style={styles.container}>
      <Text style={styles.title}>Tracelet RN Example</Text>

      {/* Status */}
      <View style={styles.statusRow}>
        <Text style={styles.statusLabel}>Enabled:</Text>
        <Text style={styles.statusValue}>{state?.enabled ? 'YES' : 'NO'}</Text>
        <Text style={styles.statusLabel}>  Moving:</Text>
        <Text style={styles.statusValue}>{state?.isMoving ? 'YES' : 'NO'}</Text>
        <Text style={styles.statusLabel}>  DB:</Text>
        <Text style={styles.statusValue}>{locationCount}</Text>
      </View>

      {/* Location */}
      {location && (
        <View style={styles.locationCard}>
          <Text style={styles.locationText}>
            {location.coords.latitude.toFixed(6)}, {location.coords.longitude.toFixed(6)}
          </Text>
          <Text style={styles.locationMeta}>
            accuracy: {location.coords.accuracy?.toFixed(1)}m  speed: {location.coords.speed?.toFixed(1)} m/s
          </Text>
        </View>
      )}

      {/* Core Buttons */}
      <View style={styles.buttonRow}>
        <TouchableOpacity style={styles.button} onPress={onReady}>
          <Text style={styles.buttonText}>Ready</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[styles.button, styles.greenButton]} onPress={onStart}>
          <Text style={styles.buttonText}>Start</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[styles.button, styles.redButton]} onPress={onStop}>
          <Text style={styles.buttonText}>Stop</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.button} onPress={onGetCurrentPosition}>
          <Text style={styles.buttonText}>GPS</Text>
        </TouchableOpacity>
      </View>

      {/* Extended Buttons */}
      <View style={styles.buttonRow}>
        <TouchableOpacity style={[styles.button, styles.purpleButton]} onPress={onStartPeriodic}>
          <Text style={styles.buttonText}>Periodic</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.button} onPress={onSync}>
          <Text style={styles.buttonText}>Sync</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.button} onPress={onGetCount}>
          <Text style={styles.buttonText}>Count</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.button} onPress={onRequestPermission}>
          <Text style={styles.buttonText}>Perms</Text>
        </TouchableOpacity>
      </View>

      {/* Geofence Row */}
      <View style={styles.geofenceRow}>
        <TextInput
          style={styles.geofenceInput}
          value={geofenceId}
          onChangeText={setGeofenceId}
          placeholder="Geofence ID"
        />
        <TouchableOpacity style={[styles.smallButton, styles.greenButton]} onPress={onAddGeofence}>
          <Text style={styles.buttonText}>+ Fence</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[styles.smallButton, styles.redButton]} onPress={onRemoveGeofences}>
          <Text style={styles.buttonText}>Clear</Text>
        </TouchableOpacity>
      </View>

      {/* Event Log */}
      <ScrollView style={styles.eventLog}>
        {events.map((evt, i) => (
          <Text key={i} style={styles.eventText}>{evt}</Text>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f5f5f5', padding: 16 },
  title: { fontSize: 22, fontWeight: '700', textAlign: 'center', marginBottom: 12 },
  statusRow: { flexDirection: 'row', justifyContent: 'center', marginBottom: 8 },
  statusLabel: { fontSize: 14, color: '#666' },
  statusValue: { fontSize: 14, fontWeight: '600', marginRight: 8 },
  locationCard: {
    backgroundColor: '#fff', borderRadius: 8, padding: 12, marginBottom: 12,
    shadowColor: '#000', shadowOpacity: 0.1, shadowRadius: 4, elevation: 2,
  },
  locationText: { fontSize: 18, fontWeight: '600', textAlign: 'center' },
  locationMeta: { fontSize: 12, color: '#888', textAlign: 'center', marginTop: 4 },
  buttonRow: { flexDirection: 'row', justifyContent: 'space-around', marginBottom: 8 },
  button: {
    backgroundColor: '#4a90d9', borderRadius: 8, paddingVertical: 10, paddingHorizontal: 18,
  },
  smallButton: {
    backgroundColor: '#4a90d9', borderRadius: 8, paddingVertical: 8, paddingHorizontal: 12,
  },
  greenButton: { backgroundColor: '#4caf50' },
  redButton: { backgroundColor: '#f44336' },
  purpleButton: { backgroundColor: '#9c27b0' },
  buttonText: { color: '#fff', fontWeight: '600', fontSize: 13 },
  geofenceRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    marginBottom: 8, gap: 8,
  },
  geofenceInput: {
    flex: 1, backgroundColor: '#fff', borderRadius: 8, paddingHorizontal: 12,
    paddingVertical: 8, fontSize: 14, borderWidth: 1, borderColor: '#ddd',
  },
  eventLog: { flex: 1, backgroundColor: '#1e1e1e', borderRadius: 8, padding: 8 },
  eventText: { color: '#00e676', fontSize: 11, fontFamily: 'Courier', marginBottom: 2 },
});
