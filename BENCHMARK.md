# Tracelet Performance Benchmarks

Automated performance tracking for Tracelet's core Dart algorithms.
Benchmarks run on every commit via CI and results are appended below.

## How to Run Locally

```bash
cd benchmark && flutter pub get && flutter test test/tracelet_benchmark_test.dart --reporter expanded
```

## Benchmark Descriptions

| Benchmark | Description | Hot Path |
|---|---|---|
| `kalman_process_single` | Single Kalman filter predict+update cycle | Every GPS fix |
| `kalman_process_100_fixes` | 100 sequential GPS fixes through Kalman filter | Sustained tracking |
| `kalman_process_1k_fixes` | 1000 sequential GPS fixes through Kalman filter | Long session |
| `kalman_reset` | Reset filter state (Float64List fillRange) | Mode change |
| `haversine_single` | Single haversine distance calculation | Every GPS fix (3+ calls) |
| `haversine_1k_pairs` | 1000 sequential haversine calculations | Batch processing |
| `pip_4v` | Point-in-polygon, 4-vertex polygon | Simple geofence |
| `pip_10v` | Point-in-polygon, 10-vertex polygon | Medium polygon |
| `pip_50v` | Point-in-polygon, 50-vertex polygon | Complex polygon |
| `pip_100v` | Point-in-polygon, 100-vertex polygon | Detailed boundary |
| `pip_500v` | Point-in-polygon, 500-vertex polygon | High-detail polygon |
| `geofence_eval_10_circular` | Evaluate 10 circular geofences | Small deployment |
| `geofence_eval_100_circular` | Evaluate 100 circular geofences | Medium deployment |
| `geofence_eval_500_circular` | Evaluate 500 circular geofences | Large deployment |
| `geofence_eval_10_polygon_6v` | Evaluate 10 polygon geofences (6 vertices each) | Polygon zones |
| `geofence_eval_50_polygon_6v` | Evaluate 50 polygon geofences (6 vertices each) | Many polygon zones |
| `processor_1k_fixes` | Full LocationProcessor pipeline, 1000 fixes | Core tracking loop |
| `processor_1k_adaptive` | LocationProcessor with adaptive mode, 1000 fixes | Battery-aware tracking |
| `trip_manager_5k_waypoints` | TripManager accumulating 5000 waypoints | Long trip |
| `schedule_parse` | Parse a schedule string | Schedule evaluation |
| `schedule_matches` | Check if time matches a schedule | Schedule evaluation |
| `schedule_isWithin_5_entries` | Check 5 schedule entries | Multi-schedule |
| `adaptive_compute` | AdaptiveSamplingEngine single computation | Every GPS fix (adaptive) |
| `location_fromMap` | Deserialize Location from platform map | Every GPS fix |
| `location_toMap` | Serialize Location to map | Persistence/HTTP |
| `location_fromMap_toMap_roundtrip` | Full serialization round-trip | Legacy path |
| `location_copyWithCoords` | Copy Location with new coords (optimized) | Kalman output |
| `geofence_fromMap_circular` | Deserialize circular geofence | Geofence loading |
| `geofence_fromMap_polygon` | Deserialize polygon geofence with vertices | Polygon loading |
| `delta_encode_10` | Delta-encode batch of 10 locations | HTTP sync |
| `delta_encode_100` | Delta-encode batch of 100 locations | HTTP sync |
| `delta_encode_500` | Delta-encode batch of 500 locations | Bulk sync |
| `delta_decode_10` | Delta-decode batch of 10 locations | Server restore |
| `delta_decode_100` | Delta-decode batch of 100 locations | Server restore |
| `delta_decode_500` | Delta-decode batch of 500 locations | Bulk restore |
| `delta_roundtrip_100` | Full encode→decode round-trip, 100 locations | Correctness path |
| `battery_budget_single_sample` | Single battery sample processing | Every battery read |
| `battery_budget_60_samples` | 60 samples (1-hour simulation) | Sustained tracking |
| `battery_budget_heavy_drain` | 120 samples with aggressive drain | Worst-case budget |
| `carbon_trip_100_locations` | Full trip with 100 GPS fixes | Trip completion |
| `carbon_onLocation` | Per-location carbon accounting | Every GPS fix |
| `carbon_setActivity` | Activity type switching | Activity change |
| `carbon_cumulative_report` | Generate cumulative report (10 trips) | Report request |
| `persist_decider_location` | Location persist decision (all modes) | Every GPS fix |
| `persist_decider_geofence` | Geofence persist decision (all modes) | Geofence event |
| `config_fromMap` | Deserialize full Config from map | Config restore |
| `config_toMap` | Serialize full Config to map | Config persist |
| `config_roundtrip` | Full Config serialization round-trip | Config update |
| `state_fromMap` | Deserialize State from map | State restore |
| `state_toMap` | Serialize State to map | State persist |
| `route_context_toMap` | Serialize RouteContext to map | Route context attach |
| `route_context_fromMap` | Deserialize RouteContext from map | Route context restore |
| `route_context_roundtrip` | Full RouteContext serialization round-trip | Route context update |
| `sync_body_context_toMap_50` | Serialize SyncBodyContext with 50 locations | Sync body build |
| `sync_body_context_fromMap_50` | Deserialize SyncBodyContext with 50 locations | Sync body restore |
| `http_config_ssl_toMap` | Serialize HttpConfig with SSL pinning fields | Config persist |
| `http_config_ssl_fromMap` | Deserialize HttpConfig with SSL pinning fields | Config restore |
| `http_config_ssl_roundtrip` | Full HttpConfig+SSL serialization round-trip | Config update |

## Performance Thresholds

Critical operations that run on **every GPS fix** (1 Hz) must complete in < 1ms total:

| Operation | Budget | Typical |
|---|---|---|
| Kalman filter process | < 1 µs | ~0.1 µs |
| Haversine distance | < 1 µs | ~0.09 µs |
| Point-in-polygon (4v) | < 1 µs | ~0.06 µs |
| Location.fromMap() | < 5 µs | ~0.5 µs |
| Location.copyWithCoords() | < 1 µs | ~0.06 µs |
| Full processor pipeline (per fix) | < 100 µs | ~83 µs/1k ≈ 0.08 µs/fix |

---

## Results History

### 2026-05-05 — Commit 3350cae

**Environment:** Dart 3.11.5, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7192348 | 0.14 |
| kalman_process_100_fixes | 91068 | 10.98 |
| kalman_process_1k_fixes | 9410 | 106.27 |
| kalman_reset | 6836868 | 0.15 |
| haversine_single | 9388487 | 0.11 |
| haversine_1k_pairs | 18449 | 54.20 |
| pip_4v | 13411946 | 0.07 |
| pip_10v | 10384029 | 0.10 |
| pip_50v | 3986515 | 0.25 |
| pip_100v | 2168520 | 0.46 |
| pip_500v | 443683 | 2.25 |
| geofence_eval_10_circular | 663623 | 1.51 |
| geofence_eval_100_circular | 74117 | 13.49 |
| geofence_eval_500_circular | 14157 | 70.64 |
| geofence_eval_10_polygon_6v | 434670 | 2.30 |
| geofence_eval_50_polygon_6v | 86074 | 11.62 |
| processor_1k_fixes | 10728 | 93.21 |
| processor_1k_adaptive | 10210 | 97.95 |
| trip_manager_5k_waypoints | 140 | 7146.78 |
| schedule_parse | 2978501 | 0.34 |
| schedule_matches | 259495 | 3.85 |
| schedule_isWithin_5_entries | 231959 | 4.31 |
| adaptive_compute | 13871774 | 0.07 |
| location_fromMap | 1597929 | 0.63 |
| location_toMap | 580319 | 1.72 |
| location_fromMap_toMap_roundtrip | 433403 | 2.31 |
| location_copyWithCoords | 11081955 | 0.09 |
| geofence_fromMap_circular | 4145133 | 0.24 |
| geofence_fromMap_polygon | 1482531 | 0.67 |
| delta_encode_10 | 32247 | 31.01 |
| delta_decode_10 | 87593 | 11.42 |
| delta_encode_100 | 4266 | 234.42 |
| delta_decode_100 | 10478 | 95.44 |
| delta_encode_500 | 788 | 1269.22 |
| delta_decode_500 | 1982 | 504.64 |
| delta_roundtrip_100 | 3009 | 332.30 |
| battery_budget_single_sample | 8591243 | 0.12 |
| battery_budget_60_samples | 301482 | 3.32 |
| battery_budget_heavy_drain | 149757 | 6.68 |
| carbon_trip_100_locations | 105867 | 9.45 |
| carbon_onLocation | 4328706 | 0.23 |
| carbon_setActivity | 10476548 | 0.10 |
| carbon_cumulative_report | 2607940 | 0.38 |
| persist_decider_location | 21841381 | 0.05 |
| persist_decider_geofence | 21966867 | 0.05 |
| config_fromMap | 409551 | 2.44 |
| config_toMap | 154859 | 6.46 |
| config_roundtrip | 109697 | 9.12 |
| state_fromMap | 389361 | 2.57 |
| state_toMap | 144378 | 6.93 |
| route_context_toMap | 2855699 | 0.35 |
| route_context_fromMap | 2271131 | 0.44 |
| route_context_roundtrip | 1268490 | 0.79 |
| sync_body_context_toMap_50 | 8226140 | 0.12 |
| sync_body_context_fromMap_50 | 21330 | 46.88 |
| http_config_ssl_toMap | 715367 | 1.40 |
| http_config_ssl_fromMap | 1290981 | 0.77 |
| http_config_ssl_roundtrip | 444461 | 2.25 |


