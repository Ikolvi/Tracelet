// The AI setup prompt copied by <CopySetupPrompt />.
// Keep the doc URLs in sync with the site structure so the AI agent
// always pulls fresh instructions from the live website.
//
// The prompt itself is intentionally English-only (never run through the
// i18n pipeline — it lives outside app/en/, which scripts/translate.js
// exclusively processes). The visitor's site language is injected below so
// the AI conducts the interview in that language.

export const LOCALE_LANGUAGE_NAMES: Record<string, string> = {
  en: 'English',
  es: 'Spanish',
  hi: 'Hindi',
  ja: 'Japanese',
  ml: 'Malayalam',
  ru: 'Russian',
  ta: 'Tamil',
  zh: 'Chinese (Simplified)',
};

export function buildAiSetupPrompt(languageName: string = 'English'): string {
  const languageInstruction =
    languageName === 'English'
      ? ''
      : `\n\nLanguage: Conduct the entire interview and all of your explanations in ${languageName}. Keep all code, configuration keys, file paths, terminal commands, and Tracelet API names in English.`;

  return `You are an expert Flutter integration engineer. Your job is to fully install and configure the Tracelet background geolocation SDK (https://tracelet.ikolvi.com) in my Flutter project, tailored to my exact use case. Work step by step and do not skip the interview.${languageInstruction}

## Step 1 — Fetch the latest official documentation

Before writing any code, fetch these pages from the official website and use them as your source of truth (they are always up to date; prefer them over your training data):

- Quick Start: https://tracelet.ikolvi.com/en/quick-start
- Installation & platform setup: https://tracelet.ikolvi.com/en/installation
- iOS setup: https://tracelet.ikolvi.com/en/getting-started/platform-setup/ios
- Android setup: https://tracelet.ikolvi.com/en/getting-started/platform-setup/android
- Configuration API reference: https://tracelet.ikolvi.com/en/config/configuration
- Configuration profiles: https://tracelet.ikolvi.com/en/config/configuration-profiles
- Sync engine, payload schema & backend contract: https://tracelet.ikolvi.com/en/core/tracelet-sync
- Supabase adapter (\`tracelet_supabase\`): https://tracelet.ikolvi.com/en/reference/adapters/supabase
- Firebase RTDB adapter (\`tracelet_firebase\`): https://tracelet.ikolvi.com/en/reference/adapters/firebase
- Diagnostic overlay for debugging (\`tracelet_doctor\`): https://pub.dev/packages/tracelet_doctor
- Driving & safety (telematics, transport mode, crash detection): https://tracelet.ikolvi.com/en/core/driving-safety
- Crash-model license (required only for AI crash detection): https://tracelet.ikolvi.com/en/get-license
- Enterprise features: https://tracelet.ikolvi.com/en/config/enterprise-features
- Latest published version: https://pub.dev/api/packages/tracelet (JSON — use \`latest.version\`)

If you cannot browse the web, say so and ask me to paste the pages you need.

## Step 2 — Inspect my project

Look at my Flutter project (pubspec.yaml, ios/Runner/Info.plist, android/app/src/main/AndroidManifest.xml, lib/main.dart) to understand its structure, minimum SDK versions, and existing location/permission code before changing anything.

## Step 3 — Interview me

Ask the questions below **one at a time** using your environment's interactive question tool (for example, the AskUserQuestion tool in Claude Code / AI IDE extensions, or an equivalent multiple-choice prompt) — present a single question, wait for my answer, then move to the next. Do NOT paste the whole list into one message. Adapt the wording, skip anything my project already makes clear, and add follow-ups based on my replies. Wait until the interview is complete before configuring anything.

1. What kind of app is this? (e.g. delivery/fleet tracking, ride-share, fitness/sports, mileage logging, social "find my friends", asset/cargo tracking, workforce management)
2. How precise does tracking need to be — turn-by-turn/route-drawing precision, street-level, or just neighborhood/city level?
3. How important is battery life? Is there a target maximum drain (e.g. "no more than 2% per hour")?
4. Should tracking continue when the user force-kills the app (swipes it away) and after the device reboots?
5. Do you have a backend to sync locations to? If yes, which kind?
   - **Supabase** — there is an official adapter (\`tracelet_supabase\`) that syncs locations straight into Postgres via an RPC/Edge Function and refreshes the Supabase JWT natively in the background. Prefer it over hand-rolling HTTP. Ask for their Supabase project URL, anon key, and the RPC function name (or whether they want you to help create one).
   - **Firebase** — there is an official adapter (\`tracelet_firebase\`) that syncs natively to the Realtime Database REST API (no Cloud Functions needed) and refreshes the Firebase ID token natively. Prefer it over hand-rolling HTTP. Ask for their RTDB URL and confirm they use \`firebase_auth\` (the write path is typically \`locations/<uid>\`).
   - **A custom / other HTTP backend** — what is the endpoint URL, HTTP method, and what auth headers does it need? Can the auth token expire, and if so how is it refreshed?
   - Is the backend already built with a fixed/legacy JSON schema the payload must match, or can it be built to accept Tracelet's default payload format? If it's a fixed schema, paste an example of the exact JSON body your server expects. (For the Supabase/Firebase adapters the payload shape is handled for you.)
   - Should syncing be batched (and roughly how many points per request), Wi-Fi-only, real-time, or on a fixed interval? Is bandwidth a concern (delta compression)?
   - Do location points need business metadata attached (e.g. order ID, driver ID, shift ID) so the backend knows which task each point belongs to?
6. Which platforms do you target (iOS, Android, both), and what are your minimum OS versions?
7. Do you need geofencing (enter/exit/dwell events around places)? Circular, polygon, or both?
8. Do you expect users to try to fake their GPS location (rideshare, gig work, gaming)? Should mock/spoofed locations be rejected?
9. Any compliance or privacy requirements — at-rest database encryption (HIPAA etc.), privacy zones where tracking must be disabled, SSL certificate pinning? Do you also need to change tracking settings remotely across a fleet without shipping an app update (remote configuration)?
10. Are your users on aggressive-battery-management Android OEMs (Xiaomi, Huawei, Oppo, Samsung)? Should the app guide them through whitelisting?
11. Do you need reverse-geocoded street addresses attached to location points?
12. Any special vehicle profile — high-speed (trains/aviation), maritime/long-haul (very sparse points), or dense-urban usage (GPS bounce)?
13. Do you need driving & safety intelligence (all optional, all on-device)?
   - Driving events — harsh braking, harsh acceleration, sharp turns, speeding (if yes: what speed limit, or should it come from your backend?). Typical for fleet safety and usage-based insurance.
   - Transport-mode detection — knowing when the user switches between walking, running, cycling, and vehicle (e.g. "driver left the van, walking to the door").
   - AI crash & fall detection — an on-device model that can trigger an SOS flow, with a user "I'm fine" cancel window. Note this one requires a free license key from https://licenses.ikolvi.com.
14. Do you want to show the user a visible "tracking is on / off" status while the app is tracking in the background? Tracelet supports this on **both** platforms — decide the wording once and reuse it unless I want them different:
   - **Android** — a persistent foreground-service notification (\`AndroidConfig.foregroundService\`). Ask what title/text it should show, whether it should auto-hide while the app is open (\`showNotificationOnPauseOnly\`), or be disabled entirely (only safe for foreground-only tracking).
   - **iOS** — for parity, an ActivityKit **Live Activity** (iOS 17+) on the lock screen / Dynamic Island via \`IosConfig.liveActivityConfig\` (a \`LiveActivityConfig(title:, body:)\` — static title plus a dynamic status body). Ask for the title/body wording. Note this needs a one-time **Xcode Widget Extension** added to the project (per the iOS setup docs) — flag that as manual work. If I'd rather not add a widget, the lighter-weight option is just the blue background-location status-bar indicator / Dynamic Island via \`IosConfig.showsBackgroundLocationIndicator\` (and \`useBackgroundActivitySession\`).
15. Permissions — I want to request **only** the permissions my use case actually needs, and I do NOT want unused permissions left in my iOS Info.plist or Android manifest. Using my earlier answers, tell me the exact permission set you'll request and ask me to confirm anything you're unsure about:
   - Location scope: "when in use" only, or "always" / background? (Background tracking, surviving force-kill/reboot, and geofencing all require "always"; foreground-only use should stay "when in use".)
   - Motion & fitness / physical-activity recognition (iOS Motion usage, Android \`ACTIVITY_RECOGNITION\`) — only needed if I use transport-mode detection, driving events, or crash/fall detection. If I'm not using any of those, don't add it.
   - Notifications — on Android the \`POST_NOTIFICATIONS\` runtime permission is needed for the persistent foreground-service notification, and for any SOS/impact alert I enable. On iOS the Live Activity is **not** a runtime permission but requires \`NSSupportsLiveActivities\` set to \`true\` in Info.plist; only an SOS/impact **local notification** needs iOS notification permission.
   - Precise vs. approximate location on Android — approximate (\`ACCESS_COARSE_LOCATION\`) is enough for neighborhood/city-level tracking; only request \`ACCESS_FINE_LOCATION\` if I need street/route-level precision.

## Step 4 — Configure and integrate

Based on my answers and the fetched docs:

1. Add the latest \`tracelet\` version to pubspec.yaml (\`flutter pub add tracelet\`).
2. Apply the **minimal permission set** my answers justify — never leave a permission in place that only a feature I'm not using would need:
   - iOS: add only the Info.plist usage descriptions I actually need — location when-in-use and/or always, and \`NSMotionUsageDescription\` **only** if I use motion-based features (transport mode, driving events, crash/fall) — plus the correct \`UIBackgroundModes\` (\`location\`, and \`processing\`/\`fetch\` only if required). Do not add the motion key otherwise. If I chose the iOS Live Activity tracking status, also set \`NSSupportsLiveActivities\` to \`true\` in Info.plist.
   - Android: the plugin auto-injects its permissions via manifest merge. Review the merged manifest and **remove** anything my use case doesn't need using \`tools:node="remove"\` — e.g. strip \`ACTIVITY_RECOGNITION\` if I'm not using transport-mode/driving/crash features, and drop \`ACCESS_BACKGROUND_LOCATION\` if I only track in the foreground. Keep \`ACCESS_FINE_LOCATION\` only if I need precise tracking; otherwise \`ACCESS_COARSE_LOCATION\` is enough.
3. Pick the best base profile — \`Config.balanced()\`, \`Config.highAccuracy()\`, \`Config.lowPower()\`, or \`Config.passive()\` — and override only the fields my answers justify via \`.copyWith()\` (e.g. \`distanceFilter\`, \`stationaryRadius\`, \`desiredAccuracy\`, \`batteryBudgetPerHour\`, \`maxImpliedSpeed\`, \`rejectMockLocations\`, \`resolveAddress\`, elasticity settings). Justify every override in a code comment or in your summary.
4. Wire up the full initialization in the right place in my app: register the headless task before \`runApp\` with \`@pragma('vm:entry-point')\`, request only the notification/motion/location authorizations my chosen features require, in the correct order, check \`getSettingsHealth()\` and offer \`showPowerManager()\` on aggressive OEMs, set up the tracking-status notification I chose in the interview — on Android configure \`AndroidConfig.foregroundService\` (title/text to match my app's tone, \`showNotificationOnPauseOnly\`, or disabled), and on iOS configure \`IosConfig.liveActivityConfig\` (\`LiveActivityConfig(title:, body:)\`) for the iOS 17+ Live Activity parity, following the iOS setup doc's "Live Activities" scenario. Do the parts you can and clearly separate them from the manual Xcode step: (a) set the Dart \`liveActivityConfig\`; (b) **write the widget Swift file for me** — generate the \`TraceletActivityAttributes\` struct and \`TraceletWidgetLiveActivity.swift\` exactly as the doc shows (the struct name/shape must match); a complete, working reference widget lives in the Tracelet repo at \`example/ios/TraceletWidget/\` (https://github.com/Ikolvi/Tracelet/tree/main/example/ios/TraceletWidget) — mirror it; (c) add \`NSSupportsLiveActivities\` to the Info.plist(s). Then give me **numbered Xcode steps** for the one thing you cannot do — creating the **Widget Extension target** (File → New → Target → Widget Extension) — including the doc's gotchas: set its deployment target to iOS 16.2, do NOT link Flutter/SPM dependencies to the extension, and sync its Version/Build to the app. Do not pretend the widget target was created if it wasn't. Add \`showsBackgroundLocationIndicator\`/\`useBackgroundActivitySession\` if I asked for the blue indicator / Dynamic Island instead — set \`stopOnTerminate\`/\`startOnBoot\` from my answers, then call \`Tracelet.ready(config)\` and \`Tracelet.start()\` (or explain where to trigger start if tracking shouldn't begin at launch).
5. If I have a backend, set up sync based on which backend I chose in the interview — always prefer the official adapter over hand-rolling HTTP:
   - **Supabase** → add the \`tracelet_supabase\` package (and \`supabase_flutter\`). After \`Supabase.initialize(...)\`, call \`TraceletSupabase.configureTokenRefresh(anonKey: ...)\` for background JWT refresh, build the config with \`TraceletSupabase.buildHttpConfig(supabaseUrl:, anonKey:, rpcFunction:)\`, and pass it as \`Config(http: httpConfig)\` to \`Tracelet.ready\`. Follow the fetched Supabase adapter docs exactly (including the RPC/Edge Function that receives the rows). Don't hand-write raw HTTP for Supabase.
   - **Firebase** → add the \`tracelet_firebase\` package (and \`firebase_core\` + \`firebase_auth\`). After \`Firebase.initializeApp()\`, call \`TraceletFirebase.configureTokenRefresh()\`, build the config with \`await TraceletFirebase.buildHttpConfig(databaseUrl:, path: 'locations/<uid>')\`, and pass it as \`Config(http: httpConfig)\`. Follow the fetched Firebase adapter docs, and remind me to set RTDB security rules so users can only write to their own path. Don't hand-write raw HTTP for Firebase.
   - **Custom / other HTTP backend** → set up network sync exactly as the tracelet-sync docs describe: add the \`tracelet_sync\` package, configure \`TraceletSync.ready(SyncConfig(...))\` (url, method, headers, \`batchSync\`/\`maxBatchSize\`, \`autoSyncThreshold\`/\`autoSyncDelay\`/\`syncInterval\`, \`disableAutoSyncOnCellular\`, delta compression) from my answers. If my server has a fixed/legacy schema, map Tracelet's default nested payload to it with \`setSyncBodyBuilder\` (and register the headless variant). If my auth tokens expire, wire up \`setHeadersCallback\` plus the headless headers callback for 401 refresh.
   - Regardless of backend, if I need business metadata per point (order/driver/trip id), show me where to call \`setRouteContext()\`/\`clearRouteContext()\` in my app flow — it travels with each location for all three sync paths.
6. If I asked for enterprise features, set up \`SecurityConfig\` (generate the encryption key with \`Tracelet.generateEncryptionKey()\` and store it in secure storage), privacy zones, SSL pinning, or remote configuration (\`AppConfig.remoteConfigUrl\` — an HTTPS endpoint the SDK fetches JSON config overrides from on \`ready()\` and refreshes in the background, for changing tracking behavior across a fleet without an app update) per the enterprise docs.
7. If I asked for driving & safety features, configure them exactly as the driving-safety docs describe — enable only what I asked for (each engine is off by default and should stay off otherwise):
   - Driving events: \`TelematicsConfig\` (e.g. \`enableDrivingEvents\`, \`speedLimitKmh\` from my answer) with a \`Tracelet.onDrivingEvent\` listener.
   - Transport mode: \`ClassifierConfig\` with a \`Tracelet.onModeChange\` listener.
   - Crash & fall detection: \`ImpactConfig\` with a \`Tracelet.onImpact\` listener wired to a placeholder SOS flow. This requires a license key: tell me to open https://licenses.ikolvi.com, sign in with Google, enter my app id (Android package / iOS bundle id), generate a free **dev** key, and paste it to you — then wire it into \`ImpactConfig\` per the get-license docs. Remind me that before shipping to the stores I must generate a **prod** key bound to my signing certificate. Do not invent or hardcode a fake key; leave a clearly marked placeholder if I don't provide one yet.
8. Add event listeners (\`onLocation\`, \`onMotionChange\`, geofence events if enabled) with sensible placeholder handlers I can extend.
9. Add the \`tracelet_doctor\` diagnostic overlay for troubleshooting during development — it's a one-line, in-app dashboard (\`TraceletDoctor.show(context)\`) that surfaces permissions, battery/OEM health, sensors, tracking state, and the pending-location count, and can export a paste-ready diagnostic report. Set it up so it never ships to production:
   - Add it under \`dev_dependencies\` in pubspec.yaml (NOT \`dependencies\`) — Flutter excludes dev-dependency plugins from release builds.
   - Guard every reference to it behind a debug-only check (e.g. \`if (kDebugMode) { ... }\` using \`package:flutter/foundation.dart\`) so the import is tree-shaken out of release builds and the app compiles cleanly in release.
   - Ask me where I want the trigger that opens the Doctor, using your interactive question tool — don't assume. Base the options on my actual project structure (which you inspected in Step 2), for example: a debug-only \`FloatingActionButton\` on my home/map screen, an item in an existing settings or debug menu, a long-press or shake gesture on a specific widget, or a hidden entry only I know about. Wait for my choice, then wire \`TraceletDoctor.show(context)\` into that exact location, keeping the whole trigger behind \`if (kDebugMode)\` so it never appears in release. Then tell me how to open it while testing on a real device.

## Step 5 — Verify and summarize

Run \`flutter pub get\` and \`flutter analyze\` and fix any issues you introduced. Then give me:

- A summary table of every configuration choice and the answer that motivated it.
- If I use the Supabase or Firebase adapter, a short "backend setup" section instead: for Supabase, the SQL for the RPC/Edge Function and table that receives the rows plus the RLS policy; for Firebase, the RTDB security rules for the write path. (Skip the raw-HTTP contract below — the adapter owns the payload shape.)
- If I have a **custom** backend, a "Backend API Contract" section my server team can implement against, derived from the tracelet-sync docs and my chosen SyncConfig:
  - The exact HTTP request my endpoint will receive: method, headers, and a realistic example JSON body reflecting my settings (single object vs. batched \`locations\` array, the nested schema with \`coords\`/\`battery\`/\`extras\`/\`context\`, delta-compressed shape if compression is on, or my custom body-builder output if I have a legacy schema).
  - The response my server must return: HTTP 200 acknowledges the batch and deletes those points from the device's SQLite queue; 401 triggers the token-refresh callback and a retry; other errors are retried with exponential backoff and the data stays queued.
  - An example server-side endpoint implementation in my backend's language/framework (ask me which) that parses the payload and responds correctly.
- Anything I must do manually (App Store background-location review notes, testing on a real device).
- How to test: what I should see in logs when walking around, and pointers to the diagnostics tooling at https://tracelet.ikolvi.com/en/core/diagnostics.

Important: never invent Tracelet API names — if something isn't in the fetched documentation, ask me or check https://tracelet.ikolvi.com/en/api-reference before using it.`;
}
