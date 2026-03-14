// @tracelet/react-native — Production-grade background geolocation.

export { Tracelet } from './Tracelet';
export type { Subscription } from './Tracelet';

// Types
export type { Config, GeoConfig, AppConfig, HttpConfig, LoggerConfig, MotionConfig, GeofenceConfig, PersistenceConfig, AuditConfig, PrivacyZoneConfig, ForegroundServiceConfig, LocationFilter, PermissionRationale } from './types/Config';
export type { Location, Coords, LocationActivity, LocationBattery, MockHeuristics, CurrentPositionOptions, LastKnownLocationOptions, WatchPositionOptions, SQLQuery } from './types/Location';
export type { Geofence } from './types/Geofence';
export type { State } from './types/State';
export type { MotionChangeEvent, ActivityChangeEvent, ProviderChangeEvent, GeofenceEvent, GeofencesChangeEvent, HeartbeatEvent, HttpEvent, ConnectivityChangeEvent, AuthorizationEvent, HeadlessEvent, Sensors, DeviceInfo, BudgetAdjustmentEvent } from './types/Events';

// Enums
export { DesiredAccuracy, LogLevel, ActivityType, ActivityConfidence, TrackingMode, GeofenceAction, AuthorizationStatus, AccuracyAuthorization, HttpMethod, LocationOrder, LocationActivityType, PersistMode, LocationFilterPolicy, MockDetectionLevel, LocationAuthorizationRequest, NotificationPriority, HashAlgorithm } from './types/Enums';

// Errors
export { TraceletError } from './types/Errors';

// Hooks
export { useLocation } from './hooks/useLocation';
export { useTraceletState } from './hooks/useTraceletState';
export { useGeofences } from './hooks/useGeofences';
