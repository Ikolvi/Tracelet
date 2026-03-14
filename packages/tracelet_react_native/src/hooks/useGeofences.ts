import { useState, useEffect, useCallback } from 'react';
import { Tracelet } from '../Tracelet';
import type { Geofence } from '../types/Geofence';

/**
 * React hook that provides the current list of registered geofences.
 * Automatically refreshes when the geofence set changes.
 */
export function useGeofences(): Geofence[] {
  const [geofences, setGeofences] = useState<Geofence[]>([]);

  const refresh = useCallback(() => {
    Tracelet.getGeofences().then(setGeofences).catch(() => {});
  }, []);

  useEffect(() => {
    refresh();
    const sub = Tracelet.onGeofencesChange(refresh);
    return () => sub.remove();
  }, [refresh]);

  return geofences;
}
