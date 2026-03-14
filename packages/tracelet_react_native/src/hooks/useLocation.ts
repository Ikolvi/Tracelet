import { useState, useEffect } from 'react';
import { Tracelet } from '../Tracelet';
import type { Location } from '../types/Location';

/**
 * React hook that provides the latest location from Tracelet.
 * Returns `null` until the first location event arrives.
 */
export function useLocation(): Location | null {
  const [location, setLocation] = useState<Location | null>(null);

  useEffect(() => {
    const sub = Tracelet.onLocation(setLocation);
    return () => sub.remove();
  }, []);

  return location;
}
