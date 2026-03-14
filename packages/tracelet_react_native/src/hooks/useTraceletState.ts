import { useState, useEffect, useCallback } from 'react';
import { Tracelet } from '../Tracelet';
import type { State } from '../types/State';

/**
 * React hook that provides the current Tracelet state.
 * Returns `null` until state is fetched. Automatically updates
 * when enabled/disabled state changes.
 */
export function useTraceletState(): State | null {
  const [state, setState] = useState<State | null>(null);

  const refresh = useCallback(() => {
    Tracelet.getState().then(setState).catch(() => {});
  }, []);

  useEffect(() => {
    refresh();
    const sub = Tracelet.onEnabledChange(refresh);
    return () => sub.remove();
  }, [refresh]);

  return state;
}
