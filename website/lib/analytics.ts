// Fans a custom analytics event out to every analytics tool wired into the
// site, so a single call lands the event wherever it can be reported:
//
//   - Cloudflare Zaraz  → window.zaraz.track(name, params)   (only if Zaraz is
//     enabled on the Cloudflare zone; plain Cloudflare Web Analytics is
//     pageview-only and cannot receive custom events)
//   - GA4 / Firebase    → window.gtag('event', name, params) (loaded via
//     <GoogleAnalytics> in app/layout.tsx; if the GA4 property is linked to a
//     Firebase project the event also appears in the Firebase console)
//
// Every call is guarded and wrapped in try/catch so a missing or misbehaving
// tool never throws into the UI.

type EventParams = Record<string, string | number | boolean>;

export function trackEvent(name: string, params: EventParams = {}): void {
  if (typeof window === "undefined") return;
  const w = window as any;

  // Cloudflare Zaraz (custom events)
  try {
    if (w.zaraz && typeof w.zaraz.track === "function") {
      w.zaraz.track(name, params);
    }
  } catch {
    /* no-op */
  }

  // Google Analytics 4 / Firebase Analytics
  try {
    if (typeof w.gtag === "function") {
      w.gtag("event", name, params);
    }
  } catch {
    /* no-op */
  }
}
