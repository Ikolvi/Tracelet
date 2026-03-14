import type {
  DesiredAccuracy,
  LocationActivityType,
  LocationAuthorizationRequest,
  LocationFilterPolicy,
  MockDetectionLevel,
  HttpMethod,
  LogLevel,
  PersistMode,
  NotificationPriority,
  HashAlgorithm,
  LocationOrder,
  ActivityType,
} from './Enums';

/** Location filter / denoising settings. */
export interface LocationFilter {
  maxImpliedSpeed?: number;
  maxAccuracy?: number;
  minSpeed?: number;
  enableKalmanFilter?: boolean;
  kalmanProcessNoise?: number;
  enableMockDetection?: boolean;
  mockDetectionLevel?: MockDetectionLevel;
  locationFilterPolicy?: LocationFilterPolicy;
}

/** Location accuracy and sampling settings. */
export interface GeoConfig {
  desiredAccuracy?: DesiredAccuracy;
  distanceFilter?: number;
  locationUpdateInterval?: number;
  fastestLocationUpdateInterval?: number;
  stationaryRadius?: number;
  locationTimeout?: number;
  activityType?: LocationActivityType;
  disableElasticity?: boolean;
  elasticityMultiplier?: number;
  stopAfterElapsedMinutes?: number;
  deferTime?: number;
  allowIdenticalLocations?: boolean;
  geofenceModeHighAccuracy?: boolean;
  maxMonitoredGeofences?: number;
  useSignificantChangesOnly?: boolean;
  showsBackgroundLocationIndicator?: boolean;
  pausesLocationUpdatesAutomatically?: boolean;
  locationAuthorizationRequest?: LocationAuthorizationRequest;
  disableLocationAuthorizationAlert?: boolean;
  enableTimestampMeta?: boolean;
  enableAdaptiveMode?: boolean;
  periodicLocationInterval?: number;
  periodicDesiredAccuracy?: DesiredAccuracy;
  periodicUseForegroundService?: boolean;
  periodicUseExactAlarms?: boolean;
  enableSparseUpdates?: boolean;
  sparseDistanceThreshold?: number;
  sparseMaxIdleSeconds?: number;
  enableDeadReckoning?: boolean;
  deadReckoningActivationDelay?: number;
  deadReckoningMaxDuration?: number;
  batteryBudgetPerHour?: number;
  filter?: LocationFilter;
}

/** Application lifecycle and scheduling settings. */
export interface AppConfig {
  stopOnTerminate?: boolean;
  startOnBoot?: boolean;
  heartbeatInterval?: number;
  schedule?: string[];
  stopTimeout?: number;
  disableMotionActivityUpdates?: boolean;
  disableStopDetection?: boolean;
  preventSuspend?: boolean;
  foregroundService?: ForegroundServiceConfig;
}

/** Android foreground service notification configuration. */
export interface ForegroundServiceConfig {
  enabled?: boolean;
  title?: string;
  text?: string;
  channelName?: string;
  channelId?: string;
  color?: string;
  smallIconName?: string;
  largeIconName?: string;
  priority?: NotificationPriority;
  actions?: string[];
}

/** HTTP sync settings. */
export interface HttpConfig {
  url?: string;
  method?: HttpMethod;
  headers?: Record<string, string>;
  autoSync?: boolean;
  autoSyncThreshold?: number;
  batchSync?: boolean;
  maxBatchSize?: number;
  maxDaysToPersist?: number;
  maxRecordsToPersist?: number;
  locationsOrderDirection?: LocationOrder;
  extras?: Record<string, unknown>;
  enableDeltaCompression?: boolean;
  deltaCoordinatePrecision?: number;
  disableAutoSyncOnCellular?: boolean;
}

/** Logger settings. */
export interface LoggerConfig {
  level?: LogLevel;
  maxEntries?: number;
}

/** Motion detection settings. */
export interface MotionConfig {
  stopTimeout?: number;
  triggerActivities?: ActivityType[];
  disableMotionActivityUpdates?: boolean;
  disableStopDetection?: boolean;
  accelerometerSampleRate?: number;
}

/** Geofencing settings. */
export interface GeofenceConfig {
  geofenceProximityRadius?: number;
  geofenceInitialTriggerEntry?: boolean;
}

/** Data persistence and database settings. */
export interface PersistenceConfig {
  persistMode?: PersistMode;
  maxDaysToPersist?: number;
  maxRecordsToPersist?: number;
  autoSync?: boolean;
  autoSyncThreshold?: number;
  locationsOrderDirection?: LocationOrder;
  extras?: Record<string, unknown>;
  locationTemplate?: string;
  geofenceTemplate?: string;
}

/** Audit trail configuration (Enterprise). */
export interface AuditConfig {
  enabled?: boolean;
  hashAlgorithm?: HashAlgorithm;
}

/** Privacy zone configuration (Enterprise). */
export interface PrivacyZoneConfig {
  enabled?: boolean;
}

/** Permission rationale dialog (Android). */
export interface PermissionRationale {
  title?: string;
  message?: string;
  positiveAction?: string;
  negativeAction?: string;
}

/** Top-level compound configuration for Tracelet. */
export interface Config {
  geo?: GeoConfig;
  app?: AppConfig;
  http?: HttpConfig;
  logger?: LoggerConfig;
  motion?: MotionConfig;
  geofence?: GeofenceConfig;
  persistence?: PersistenceConfig;
  audit?: AuditConfig;
  privacyZone?: PrivacyZoneConfig;
}
