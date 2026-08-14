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

### 2026-08-14 — Commit 6283aa52

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81234 | 12.31 |
| schedule_isWithin_5_entries | 75585 | 13.23 |
| location_fromMap | 1449275 | 0.69 |
| location_toMap | 625000 | 1.60 |
| location_fromMap_toMap_roundtrip | 442477 | 2.26 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 3846153 | 0.26 |
| geofence_fromMap_polygon | 1315789 | 0.76 |
| carbon_trip_100_locations | 90909 | 11.00 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 552486 | 1.81 |
| config_toMap | 662251 | 1.51 |
| config_roundtrip | 287356 | 3.48 |
| state_fromMap | 515463 | 1.94 |
| state_toMap | 529100 | 1.89 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2040816 | 0.49 |
| route_context_roundtrip | 1282051 | 0.78 |
| sync_body_context_toMap_50 | 6250000 | 0.16 |
| sync_body_context_fromMap_50 | 21593 | 46.31 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_single_sample | 22021177 | 0.05 |
| smart_motion_accel_change | 22079055 | 0.05 |
| smart_motion_speed_change | 21680654 | 0.05 |
| battery_budget_60_samples | 1286776 | 0.78 |
| battery_budget_heavy_drain | 662359 | 1.51 |


### 2026-08-14 — Commit 08902707

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 90744 | 11.02 |
| schedule_isWithin_5_entries | 81967 | 12.20 |
| location_fromMap | 1492537 | 0.67 |
| location_toMap | 595238 | 1.68 |
| location_fromMap_toMap_roundtrip | 438596 | 2.28 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4166666 | 0.24 |
| geofence_fromMap_polygon | 1315789 | 0.76 |
| carbon_trip_100_locations | 93457 | 10.70 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 549450 | 1.82 |
| config_toMap | 645161 | 1.55 |
| config_roundtrip | 290697 | 3.44 |
| state_fromMap | 510204 | 1.96 |
| state_toMap | 518134 | 1.93 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2127659 | 0.47 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22040 | 45.37 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| smart_motion_speed_change | 23259579 | 0.04 |
| battery_budget_heavy_drain | 664841 | 1.50 |
| battery_budget_single_sample | 23752063 | 0.04 |
| battery_budget_60_samples | 1291062 | 0.77 |
| smart_motion_accel_change | 23526993 | 0.04 |


### 2026-08-14 — Commit adf591bc

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 82101 | 12.18 |
| schedule_isWithin_5_entries | 75075 | 13.32 |
| location_fromMap | 1449275 | 0.69 |
| location_toMap | 625000 | 1.60 |
| location_fromMap_toMap_roundtrip | 448430 | 2.23 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 3846153 | 0.26 |
| geofence_fromMap_polygon | 1298701 | 0.77 |
| carbon_trip_100_locations | 87260 | 11.46 |
| carbon_onLocation | 3846153 | 0.26 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 529100 | 1.89 |
| config_toMap | 657894 | 1.52 |
| config_roundtrip | 277008 | 3.61 |
| state_fromMap | 492610 | 2.03 |
| state_toMap | 526315 | 1.90 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2040816 | 0.49 |
| route_context_roundtrip | 1265822 | 0.79 |
| sync_body_context_toMap_50 | 6250000 | 0.16 |
| sync_body_context_fromMap_50 | 21777 | 45.92 |
| http_config_ssl_toMap | 5263157 | 0.19 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2000000 | 0.50 |
| smart_motion_speed_change | 21952922 | 0.05 |
| battery_budget_heavy_drain | 662060 | 1.51 |
| smart_motion_accel_change | 22163644 | 0.05 |
| battery_budget_60_samples | 1285754 | 0.78 |
| battery_budget_single_sample | 22034525 | 0.05 |


### 2026-08-13 — Commit e8de8407

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81037 | 12.34 |
| schedule_isWithin_5_entries | 72992 | 13.70 |
| location_fromMap | 1470588 | 0.68 |
| location_toMap | 625000 | 1.60 |
| location_fromMap_toMap_roundtrip | 444444 | 2.25 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 3846153 | 0.26 |
| geofence_fromMap_polygon | 1333333 | 0.75 |
| carbon_trip_100_locations | 90009 | 11.11 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 584795 | 1.71 |
| config_toMap | 649350 | 1.54 |
| config_roundtrip | 293255 | 3.41 |
| state_fromMap | 529100 | 1.89 |
| state_toMap | 526315 | 1.90 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2040816 | 0.49 |
| route_context_roundtrip | 1204819 | 0.83 |
| sync_body_context_toMap_50 | 6250000 | 0.16 |
| sync_body_context_fromMap_50 | 21468 | 46.58 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2702702 | 0.37 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_60_samples | 1289228 | 0.78 |
| smart_motion_accel_change | 22165890 | 0.05 |
| battery_budget_heavy_drain | 663737 | 1.51 |
| battery_budget_single_sample | 22038714 | 0.05 |
| smart_motion_speed_change | 22019518 | 0.05 |


### 2026-08-13 — Commit 781ff04b

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 82781 | 12.08 |
| schedule_isWithin_5_entries | 75700 | 13.21 |
| location_fromMap | 1428571 | 0.70 |
| location_toMap | 609756 | 1.64 |
| location_fromMap_toMap_roundtrip | 436681 | 2.29 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 3846153 | 0.26 |
| geofence_fromMap_polygon | 1298701 | 0.77 |
| carbon_trip_100_locations | 90826 | 11.01 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2272727 | 0.44 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 574712 | 1.74 |
| config_toMap | 645161 | 1.55 |
| config_roundtrip | 285714 | 3.50 |
| state_fromMap | 523560 | 1.91 |
| state_toMap | 518134 | 1.93 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2040816 | 0.49 |
| route_context_roundtrip | 1190476 | 0.84 |
| sync_body_context_toMap_50 | 5263157 | 0.19 |
| sync_body_context_fromMap_50 | 21635 | 46.22 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| smart_motion_accel_change | 22121396 | 0.05 |
| battery_budget_60_samples | 1287940 | 0.78 |
| battery_budget_single_sample | 22020359 | 0.05 |
| battery_budget_heavy_drain | 662783 | 1.51 |
| smart_motion_speed_change | 21915456 | 0.05 |


### 2026-08-13 — Commit 380491ab

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2857142 | 0.35 |
| schedule_matches | 140252 | 7.13 |
| schedule_isWithin_5_entries | 119617 | 8.36 |
| location_fromMap | 1470588 | 0.68 |
| location_toMap | 515463 | 1.94 |
| location_fromMap_toMap_roundtrip | 393700 | 2.54 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4000000 | 0.25 |
| geofence_fromMap_polygon | 1449275 | 0.69 |
| carbon_trip_100_locations | 98231 | 10.18 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 529100 | 1.89 |
| config_toMap | 649350 | 1.54 |
| config_roundtrip | 300300 | 3.33 |
| state_fromMap | 512820 | 1.95 |
| state_toMap | 523560 | 1.91 |
| route_context_toMap | 2631578 | 0.38 |
| route_context_fromMap | 1960784 | 0.51 |
| route_context_roundtrip | 1111111 | 0.90 |
| sync_body_context_toMap_50 | 6250000 | 0.16 |
| sync_body_context_fromMap_50 | 19282 | 51.86 |
| http_config_ssl_toMap | 5263157 | 0.19 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 1851851 | 0.54 |
| battery_budget_single_sample | 23934865 | 0.04 |
| smart_motion_accel_change | 17559014 | 0.06 |
| smart_motion_speed_change | 17551410 | 0.06 |
| battery_budget_heavy_drain | 425729 | 2.35 |
| battery_budget_60_samples | 841853 | 1.19 |


### 2026-08-13 — Commit c14ed21f

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 81632 | 12.25 |
| schedule_isWithin_5_entries | 75301 | 13.28 |
| location_fromMap | 1449275 | 0.69 |
| location_toMap | 613496 | 1.63 |
| location_fromMap_toMap_roundtrip | 436681 | 2.29 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 3846153 | 0.26 |
| geofence_fromMap_polygon | 1298701 | 0.77 |
| carbon_trip_100_locations | 89766 | 11.14 |
| carbon_onLocation | 3703703 | 0.27 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 546448 | 1.83 |
| config_toMap | 649350 | 1.54 |
| config_roundtrip | 276243 | 3.62 |
| state_fromMap | 497512 | 2.01 |
| state_toMap | 529100 | 1.89 |
| route_context_toMap | 2777777 | 0.36 |
| route_context_fromMap | 2000000 | 0.50 |
| route_context_roundtrip | 1250000 | 0.80 |
| sync_body_context_toMap_50 | 6250000 | 0.16 |
| sync_body_context_fromMap_50 | 21514 | 46.48 |
| http_config_ssl_toMap | 5263157 | 0.19 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_single_sample | 21885658 | 0.05 |
| battery_budget_heavy_drain | 661276 | 1.51 |
| smart_motion_accel_change | 22146788 | 0.05 |
| battery_budget_60_samples | 1273585 | 0.79 |
| smart_motion_speed_change | 21826080 | 0.05 |


### 2026-08-13 — Commit cc50e000

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2631578 | 0.38 |
| schedule_matches | 81300 | 12.30 |
| schedule_isWithin_5_entries | 75414 | 13.26 |
| location_fromMap | 1369863 | 0.73 |
| location_toMap | 617283 | 1.62 |
| location_fromMap_toMap_roundtrip | 432900 | 2.31 |
| location_copyWithCoords | 8333333 | 0.12 |
| geofence_fromMap_circular | 3846153 | 0.26 |
| geofence_fromMap_polygon | 1315789 | 0.76 |
| carbon_trip_100_locations | 88261 | 11.33 |
| carbon_onLocation | 3703703 | 0.27 |
| carbon_setActivity | 7142857 | 0.14 |
| carbon_cumulative_report | 2325581 | 0.43 |
| persist_decider_location | 14285714 | 0.07 |
| persist_decider_geofence | 14285714 | 0.07 |
| config_fromMap | 555555 | 1.80 |
| config_toMap | 657894 | 1.52 |
| config_roundtrip | 283286 | 3.53 |
| state_fromMap | 505050 | 1.98 |
| state_toMap | 529100 | 1.89 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2083333 | 0.48 |
| route_context_roundtrip | 1298701 | 0.77 |
| sync_body_context_toMap_50 | 5555555 | 0.18 |
| sync_body_context_fromMap_50 | 21944 | 45.57 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_60_samples | 1286387 | 0.78 |
| battery_budget_heavy_drain | 661632 | 1.51 |
| smart_motion_accel_change | 22112304 | 0.05 |
| battery_budget_single_sample | 22013404 | 0.05 |
| smart_motion_speed_change | 21943701 | 0.05 |


### 2026-08-13 — Commit be2693f4

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 87565 | 11.42 |
| schedule_isWithin_5_entries | 81234 | 12.31 |
| location_fromMap | 1492537 | 0.67 |
| location_toMap | 617283 | 1.62 |
| location_fromMap_toMap_roundtrip | 438596 | 2.28 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4166666 | 0.24 |
| geofence_fromMap_polygon | 1351351 | 0.74 |
| carbon_trip_100_locations | 92506 | 10.81 |
| carbon_onLocation | 3846153 | 0.26 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 531914 | 1.88 |
| config_toMap | 636942 | 1.57 |
| config_roundtrip | 272479 | 3.67 |
| state_fromMap | 478468 | 2.09 |
| state_toMap | 500000 | 2.00 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2083333 | 0.48 |
| route_context_roundtrip | 1298701 | 0.77 |
| sync_body_context_toMap_50 | 6250000 | 0.16 |
| sync_body_context_fromMap_50 | 22182 | 45.08 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 2000000 | 0.50 |
| battery_budget_single_sample | 23762043 | 0.04 |
| battery_budget_heavy_drain | 665886 | 1.50 |
| battery_budget_60_samples | 1290501 | 0.77 |
| smart_motion_accel_change | 23164074 | 0.04 |
| smart_motion_speed_change | 23265799 | 0.04 |


### 2026-08-13 — Commit e7d0f098

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 92421 | 10.82 |
| schedule_isWithin_5_entries | 83263 | 12.01 |
| location_fromMap | 1492537 | 0.67 |
| location_toMap | 609756 | 1.64 |
| location_fromMap_toMap_roundtrip | 446428 | 2.24 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4166666 | 0.24 |
| geofence_fromMap_polygon | 1333333 | 0.75 |
| carbon_trip_100_locations | 91324 | 10.95 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 574712 | 1.74 |
| config_toMap | 649350 | 1.54 |
| config_roundtrip | 291545 | 3.43 |
| state_fromMap | 529100 | 1.89 |
| state_toMap | 510204 | 1.96 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22016 | 45.42 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2083333 | 0.48 |
| smart_motion_accel_change | 23435604 | 0.04 |
| battery_budget_60_samples | 1292420 | 0.77 |
| battery_budget_single_sample | 23747054 | 0.04 |
| battery_budget_heavy_drain | 665518 | 1.50 |
| smart_motion_speed_change | 23464181 | 0.04 |


### 2026-08-13 — Commit 0cc2e35d

**Environment:** Dart 3.13.0, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3030303 | 0.33 |
| schedule_matches | 143061 | 6.99 |
| schedule_isWithin_5_entries | 121654 | 8.22 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 628930 | 1.59 |
| location_fromMap_toMap_roundtrip | 456621 | 2.19 |
| location_copyWithCoords | 12500000 | 0.08 |
| geofence_fromMap_circular | 4761904 | 0.21 |
| geofence_fromMap_polygon | 1470588 | 0.68 |
| carbon_trip_100_locations | 107066 | 9.34 |
| carbon_onLocation | 4347826 | 0.23 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 598802 | 1.67 |
| config_toMap | 714285 | 1.40 |
| config_roundtrip | 320512 | 3.12 |
| state_fromMap | 546448 | 1.83 |
| state_toMap | 574712 | 1.74 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2380952 | 0.42 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22021 | 45.41 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2941176 | 0.34 |
| http_config_ssl_roundtrip | 2083333 | 0.48 |
| battery_budget_single_sample | 24014153 | 0.04 |
| smart_motion_accel_change | 17538937 | 0.06 |
| battery_budget_60_samples | 840321 | 1.19 |
| battery_budget_heavy_drain | 425182 | 2.35 |
| smart_motion_speed_change | 17574689 | 0.06 |


### 2026-08-12 — Commit b544be23

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88495 | 11.30 |
| schedule_isWithin_5_entries | 80321 | 12.45 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 632911 | 1.58 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 93457 | 10.70 |
| carbon_onLocation | 3846153 | 0.26 |
| carbon_setActivity | 8333333 | 0.12 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 552486 | 1.81 |
| config_toMap | 675675 | 1.48 |
| config_roundtrip | 290697 | 3.44 |
| state_fromMap | 518134 | 1.93 |
| state_toMap | 543478 | 1.84 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22366 | 44.71 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 2000000 | 0.50 |
| battery_budget_heavy_drain | 666211 | 1.50 |
| battery_budget_60_samples | 1288069 | 0.78 |
| smart_motion_speed_change | 23403667 | 0.04 |
| battery_budget_single_sample | 23747321 | 0.04 |
| smart_motion_accel_change | 23467419 | 0.04 |


### 2026-08-12 — Commit 6bb1301d

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 90171 | 11.09 |
| schedule_isWithin_5_entries | 83752 | 11.94 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 93457 | 10.70 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 16666666 | 0.06 |
| persist_decider_geofence | 16666666 | 0.06 |
| config_fromMap | 537634 | 1.86 |
| config_toMap | 699300 | 1.43 |
| config_roundtrip | 296735 | 3.37 |
| state_fromMap | 500000 | 2.00 |
| state_toMap | 549450 | 1.82 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22153 | 45.14 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| smart_motion_accel_change | 23502058 | 0.04 |
| battery_budget_60_samples | 1292596 | 0.77 |
| smart_motion_speed_change | 23235718 | 0.04 |
| battery_budget_single_sample | 23772220 | 0.04 |
| battery_budget_heavy_drain | 666706 | 1.50 |


### 2026-08-12 — Commit 6532e089

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81900 | 12.21 |
| schedule_isWithin_5_entries | 73746 | 13.56 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 456621 | 2.19 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 90334 | 11.07 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 16666666 | 0.06 |
| persist_decider_geofence | 16666666 | 0.06 |
| config_fromMap | 571428 | 1.75 |
| config_toMap | 709219 | 1.41 |
| config_roundtrip | 303030 | 3.30 |
| state_fromMap | 523560 | 1.91 |
| state_toMap | 568181 | 1.76 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21710 | 46.06 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| smart_motion_speed_change | 21891188 | 0.05 |
| smart_motion_accel_change | 22140181 | 0.05 |
| battery_budget_heavy_drain | 660657 | 1.51 |
| battery_budget_single_sample | 22030423 | 0.05 |
| battery_budget_60_samples | 1283422 | 0.78 |


### 2026-08-12 — Commit d3a561c8

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 87642 | 11.41 |
| schedule_isWithin_5_entries | 81103 | 12.33 |
| location_fromMap | 1492537 | 0.67 |
| location_toMap | 641025 | 1.56 |
| location_fromMap_toMap_roundtrip | 460829 | 2.17 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 93370 | 10.71 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 591715 | 1.69 |
| config_toMap | 666666 | 1.50 |
| config_roundtrip | 311526 | 3.21 |
| state_fromMap | 543478 | 1.84 |
| state_toMap | 549450 | 1.82 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22421 | 44.60 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| smart_motion_accel_change | 23449259 | 0.04 |
| battery_budget_heavy_drain | 666767 | 1.50 |
| battery_budget_60_samples | 1294790 | 0.77 |
| smart_motion_speed_change | 23397612 | 0.04 |
| battery_budget_single_sample | 23554713 | 0.04 |


### 2026-08-12 — Commit f81912ff

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 89605 | 11.16 |
| schedule_isWithin_5_entries | 81168 | 12.32 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1515151 | 0.66 |
| carbon_trip_100_locations | 91827 | 10.89 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 555555 | 1.80 |
| config_toMap | 680272 | 1.47 |
| config_roundtrip | 297619 | 3.36 |
| state_fromMap | 500000 | 2.00 |
| state_toMap | 555555 | 1.80 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22361 | 44.72 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 2083333 | 0.48 |
| battery_budget_60_samples | 1289008 | 0.78 |
| battery_budget_heavy_drain | 665886 | 1.50 |
| battery_budget_single_sample | 23577061 | 0.04 |
| smart_motion_speed_change | 23403874 | 0.04 |
| smart_motion_accel_change | 23545358 | 0.04 |


### 2026-08-12 — Commit 7f93f43f

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 88652 | 11.28 |
| schedule_isWithin_5_entries | 77942 | 12.83 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 662251 | 1.51 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4761904 | 0.21 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 92936 | 10.76 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 555555 | 1.80 |
| config_toMap | 694444 | 1.44 |
| config_roundtrip | 298507 | 3.35 |
| state_fromMap | 520833 | 1.92 |
| state_toMap | 555555 | 1.80 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22271 | 44.90 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| smart_motion_accel_change | 23539783 | 0.04 |
| battery_budget_heavy_drain | 666406 | 1.50 |
| battery_budget_60_samples | 1290690 | 0.77 |
| battery_budget_single_sample | 23548163 | 0.04 |
| smart_motion_speed_change | 23367533 | 0.04 |


### 2026-08-11 — Commit c4bb0b49

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 87108 | 11.48 |
| schedule_isWithin_5_entries | 78740 | 12.70 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 448430 | 2.23 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1515151 | 0.66 |
| carbon_trip_100_locations | 92165 | 10.85 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 578034 | 1.73 |
| config_toMap | 675675 | 1.48 |
| config_roundtrip | 303951 | 3.29 |
| state_fromMap | 529100 | 1.89 |
| state_toMap | 546448 | 1.83 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22261 | 44.92 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| smart_motion_accel_change | 23569581 | 0.04 |
| battery_budget_60_samples | 1291465 | 0.77 |
| smart_motion_speed_change | 23076671 | 0.04 |
| battery_budget_single_sample | 23583771 | 0.04 |
| battery_budget_heavy_drain | 666032 | 1.50 |


### 2026-08-11 — Commit b43081fc

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2631578 | 0.38 |
| schedule_matches | 85910 | 11.64 |
| schedule_isWithin_5_entries | 79428 | 12.59 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 628930 | 1.59 |
| location_fromMap_toMap_roundtrip | 456621 | 2.19 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 90090 | 11.10 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 543478 | 1.84 |
| config_toMap | 671140 | 1.49 |
| config_roundtrip | 293255 | 3.41 |
| state_fromMap | 505050 | 1.98 |
| state_toMap | 531914 | 1.88 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22079 | 45.29 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2000000 | 0.50 |
| smart_motion_speed_change | 23273520 | 0.04 |
| battery_budget_heavy_drain | 665738 | 1.50 |
| battery_budget_60_samples | 1292507 | 0.77 |
| smart_motion_accel_change | 23533698 | 0.04 |
| battery_budget_single_sample | 23572625 | 0.04 |


### 2026-08-11 — Commit aee09848

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 87950 | 11.37 |
| schedule_isWithin_5_entries | 80906 | 12.36 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 448430 | 2.23 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 95057 | 10.52 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 546448 | 1.83 |
| config_toMap | 689655 | 1.45 |
| config_roundtrip | 294985 | 3.39 |
| state_fromMap | 510204 | 1.96 |
| state_toMap | 549450 | 1.82 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22799 | 43.86 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_60_samples | 1296161 | 0.77 |
| battery_budget_single_sample | 23589985 | 0.04 |
| battery_budget_heavy_drain | 660658 | 1.51 |
| smart_motion_accel_change | 23558468 | 0.04 |
| smart_motion_speed_change | 23413772 | 0.04 |


### 2026-08-11 — Commit 8bcb4a05

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 82169 | 12.17 |
| schedule_isWithin_5_entries | 75987 | 13.16 |
| location_fromMap | 1515151 | 0.66 |
| location_toMap | 641025 | 1.56 |
| location_fromMap_toMap_roundtrip | 452488 | 2.21 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4166666 | 0.24 |
| geofence_fromMap_polygon | 1449275 | 0.69 |
| carbon_trip_100_locations | 88652 | 11.28 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 555555 | 1.80 |
| config_toMap | 689655 | 1.45 |
| config_roundtrip | 302114 | 3.31 |
| state_fromMap | 518134 | 1.93 |
| state_toMap | 555555 | 1.80 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21150 | 47.28 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_single_sample | 22045009 | 0.05 |
| battery_budget_60_samples | 1289703 | 0.78 |
| battery_budget_heavy_drain | 664071 | 1.51 |
| smart_motion_accel_change | 22171673 | 0.05 |
| smart_motion_speed_change | 21795497 | 0.05 |


### 2026-08-11 — Commit e6a58212

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 90009 | 11.11 |
| schedule_isWithin_5_entries | 81967 | 12.20 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 448430 | 2.23 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 93109 | 10.74 |
| carbon_onLocation | 3846153 | 0.26 |
| carbon_setActivity | 7692307 | 0.13 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 571428 | 1.75 |
| config_toMap | 632911 | 1.58 |
| config_roundtrip | 289017 | 3.46 |
| state_fromMap | 515463 | 1.94 |
| state_toMap | 518134 | 1.93 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22133 | 45.18 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_60_samples | 1290449 | 0.77 |
| battery_budget_heavy_drain | 665694 | 1.50 |
| smart_motion_accel_change | 23481854 | 0.04 |
| battery_budget_single_sample | 23587638 | 0.04 |
| smart_motion_speed_change | 23362808 | 0.04 |


### 2026-08-10 — Commit 72bd48e6

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 4761904 | 0.21 |
| schedule_matches | 125628 | 7.96 |
| schedule_isWithin_5_entries | 115874 | 8.63 |
| location_fromMap | 2857142 | 0.35 |
| location_toMap | 1176470 | 0.85 |
| location_fromMap_toMap_roundtrip | 840336 | 1.19 |
| location_copyWithCoords | 16666666 | 0.06 |
| geofence_fromMap_circular | 7692307 | 0.13 |
| geofence_fromMap_polygon | 2777777 | 0.36 |
| carbon_trip_100_locations | 167785 | 5.96 |
| carbon_onLocation | 6666666 | 0.15 |
| carbon_setActivity | 14285714 | 0.07 |
| carbon_cumulative_report | 4545454 | 0.22 |
| persist_decider_location | 25000000 | 0.04 |
| persist_decider_geofence | 25000000 | 0.04 |
| config_fromMap | 980392 | 1.02 |
| config_toMap | 1333333 | 0.75 |
| config_roundtrip | 540540 | 1.85 |
| state_fromMap | 892857 | 1.12 |
| state_toMap | 1020408 | 0.98 |
| route_context_toMap | 5263157 | 0.19 |
| route_context_fromMap | 4347826 | 0.23 |
| route_context_roundtrip | 2564102 | 0.39 |
| sync_body_context_toMap_50 | 11111111 | 0.09 |
| sync_body_context_fromMap_50 | 41050 | 24.36 |
| http_config_ssl_toMap | 10000000 | 0.10 |
| http_config_ssl_fromMap | 5263157 | 0.19 |
| http_config_ssl_roundtrip | 3703703 | 0.27 |
| smart_motion_speed_change | 20127410 | 0.05 |
| battery_budget_heavy_drain | 577541 | 1.73 |
| battery_budget_60_samples | 1139449 | 0.88 |
| smart_motion_accel_change | 20835310 | 0.05 |
| battery_budget_single_sample | 26327704 | 0.04 |


### 2026-08-10 — Commit f58500b2

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88339 | 11.32 |
| schedule_isWithin_5_entries | 80321 | 12.45 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 456621 | 2.19 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 94161 | 10.62 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 515463 | 1.94 |
| config_toMap | 671140 | 1.49 |
| config_roundtrip | 289855 | 3.45 |
| state_fromMap | 483091 | 2.07 |
| state_toMap | 543478 | 1.84 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22391 | 44.66 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2941176 | 0.34 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_60_samples | 1292446 | 0.77 |
| battery_budget_heavy_drain | 665846 | 1.50 |
| smart_motion_speed_change | 22882279 | 0.04 |
| smart_motion_accel_change | 23531197 | 0.04 |
| battery_budget_single_sample | 23743212 | 0.04 |


### 2026-08-10 — Commit 75810295

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 89126 | 11.22 |
| schedule_isWithin_5_entries | 82850 | 12.07 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 454545 | 2.20 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 91157 | 10.97 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 571428 | 1.75 |
| config_toMap | 699300 | 1.43 |
| config_roundtrip | 304878 | 3.28 |
| state_fromMap | 526315 | 1.90 |
| state_toMap | 549450 | 1.82 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 21482 | 46.55 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_heavy_drain | 666679 | 1.50 |
| battery_budget_60_samples | 1293359 | 0.77 |
| battery_budget_single_sample | 23690247 | 0.04 |
| smart_motion_accel_change | 22923816 | 0.04 |
| smart_motion_speed_change | 23069600 | 0.04 |


### 2026-08-10 — Commit 52eba02e

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 80645 | 12.40 |
| schedule_isWithin_5_entries | 74183 | 13.48 |
| location_fromMap | 1492537 | 0.67 |
| location_toMap | 632911 | 1.58 |
| location_fromMap_toMap_roundtrip | 452488 | 2.21 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 90334 | 11.07 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 558659 | 1.79 |
| config_toMap | 694444 | 1.44 |
| config_roundtrip | 291545 | 3.43 |
| state_fromMap | 510204 | 1.96 |
| state_toMap | 540540 | 1.85 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 20420 | 48.97 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_60_samples | 1285317 | 0.78 |
| smart_motion_speed_change | 21912378 | 0.05 |
| battery_budget_single_sample | 21989387 | 0.05 |
| battery_budget_heavy_drain | 662892 | 1.51 |
| smart_motion_accel_change | 22166770 | 0.05 |


### 2026-08-08 — Commit a2259eb3

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88495 | 11.30 |
| schedule_isWithin_5_entries | 80580 | 12.41 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 93545 | 10.69 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 581395 | 1.72 |
| config_toMap | 689655 | 1.45 |
| config_roundtrip | 304878 | 3.28 |
| state_fromMap | 543478 | 1.84 |
| state_toMap | 552486 | 1.81 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22351 | 44.74 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 2000000 | 0.50 |
| battery_budget_60_samples | 1292124 | 0.77 |
| battery_budget_single_sample | 23761336 | 0.04 |
| smart_motion_speed_change | 23316739 | 0.04 |
| smart_motion_accel_change | 23547828 | 0.04 |
| battery_budget_heavy_drain | 666531 | 1.50 |


### 2026-08-08 — Commit ac96c671

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88967 | 11.24 |
| schedule_isWithin_5_entries | 82236 | 12.16 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 456621 | 2.19 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 92336 | 10.83 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 571428 | 1.75 |
| config_toMap | 689655 | 1.45 |
| config_roundtrip | 294117 | 3.40 |
| state_fromMap | 512820 | 1.95 |
| state_toMap | 555555 | 1.80 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22376 | 44.69 |
| http_config_ssl_toMap | 5882352 | 0.17 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 2040816 | 0.49 |
| battery_budget_heavy_drain | 665652 | 1.50 |
| battery_budget_single_sample | 23555946 | 0.04 |
| battery_budget_60_samples | 1292550 | 0.77 |
| smart_motion_accel_change | 23566826 | 0.04 |
| smart_motion_speed_change | 23448561 | 0.04 |


### 2026-08-08 — Commit be382f1c

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 79872 | 12.52 |
| schedule_isWithin_5_entries | 74626 | 13.40 |
| location_fromMap | 1515151 | 0.66 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 460829 | 2.17 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 89365 | 11.19 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 490196 | 2.04 |
| config_toMap | 1063829 | 0.94 |
| config_roundtrip | 333333 | 3.00 |
| state_fromMap | 458715 | 2.18 |
| state_toMap | 763358 | 1.31 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21523 | 46.46 |
| http_config_ssl_toMap | 5555555 | 0.18 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 2083333 | 0.48 |
| battery_budget_single_sample | 22008397 | 0.05 |
| battery_budget_60_samples | 1286997 | 0.78 |
| battery_budget_heavy_drain | 661752 | 1.51 |
| smart_motion_accel_change | 21722712 | 0.05 |
| smart_motion_speed_change | 21923056 | 0.05 |


### 2026-08-08 — Commit f83f301f

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 83612 | 11.96 |
| schedule_isWithin_5_entries | 76219 | 13.12 |
| location_fromMap | 1388888 | 0.72 |
| location_toMap | 621118 | 1.61 |
| location_fromMap_toMap_roundtrip | 448430 | 2.23 |
| location_copyWithCoords | 8333333 | 0.12 |
| geofence_fromMap_circular | 4000000 | 0.25 |
| geofence_fromMap_polygon | 1515151 | 0.66 |
| carbon_trip_100_locations | 87719 | 11.40 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 14285714 | 0.07 |
| persist_decider_geofence | 14285714 | 0.07 |
| config_fromMap | 343642 | 2.91 |
| config_toMap | 106609 | 9.38 |
| config_roundtrip | 81366 | 12.29 |
| state_fromMap | 331125 | 3.02 |
| state_toMap | 103412 | 9.67 |
| route_context_toMap | 2702702 | 0.37 |
| route_context_fromMap | 2083333 | 0.48 |
| route_context_roundtrip | 1298701 | 0.77 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21584 | 46.33 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2380952 | 0.42 |
| http_config_ssl_roundtrip | 552486 | 1.81 |
| smart_motion_accel_change | 22161728 | 0.05 |
| battery_budget_single_sample | 22041407 | 0.05 |
| smart_motion_speed_change | 21927621 | 0.05 |
| battery_budget_60_samples | 1289365 | 0.78 |
| battery_budget_heavy_drain | 663243 | 1.51 |


### 2026-08-07 — Commit 9fdad1ea

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2941176 | 0.34 |
| schedule_matches | 141043 | 7.09 |
| schedule_isWithin_5_entries | 118764 | 8.42 |
| location_fromMap | 1515151 | 0.66 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 462962 | 2.16 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1666666 | 0.60 |
| carbon_trip_100_locations | 105485 | 9.48 |
| carbon_onLocation | 4347826 | 0.23 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 334448 | 2.99 |
| config_toMap | 99601 | 10.04 |
| config_roundtrip | 77041 | 12.98 |
| state_fromMap | 325732 | 3.07 |
| state_toMap | 97465 | 10.26 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21701 | 46.08 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 568181 | 1.76 |
| battery_budget_single_sample | 24005285 | 0.04 |
| battery_budget_60_samples | 842830 | 1.19 |
| smart_motion_accel_change | 17542940 | 0.06 |
| smart_motion_speed_change | 17547228 | 0.06 |
| battery_budget_heavy_drain | 424092 | 2.36 |


### 2026-08-07 — Commit b9474f98

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81499 | 12.27 |
| schedule_isWithin_5_entries | 73746 | 13.56 |
| location_fromMap | 1515151 | 0.66 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 460829 | 2.17 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 90744 | 11.02 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 8333333 | 0.12 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 342465 | 2.92 |
| config_toMap | 101010 | 9.90 |
| config_roundtrip | 77101 | 12.97 |
| state_fromMap | 324675 | 3.08 |
| state_toMap | 97465 | 10.26 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21934 | 45.59 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 568181 | 1.76 |
| battery_budget_single_sample | 22029535 | 0.05 |
| battery_budget_heavy_drain | 656650 | 1.52 |
| smart_motion_accel_change | 22143114 | 0.05 |
| smart_motion_speed_change | 21918769 | 0.05 |
| battery_budget_60_samples | 1275165 | 0.78 |


### 2026-08-07 — Commit 327fbf1f

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88339 | 11.32 |
| schedule_isWithin_5_entries | 80775 | 12.38 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 641025 | 1.56 |
| location_fromMap_toMap_roundtrip | 456621 | 2.19 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 94073 | 10.63 |
| carbon_onLocation | 3846153 | 0.26 |
| carbon_setActivity | 8333333 | 0.12 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 338983 | 2.95 |
| config_toMap | 101419 | 9.86 |
| config_roundtrip | 77942 | 12.83 |
| state_fromMap | 325732 | 3.07 |
| state_toMap | 98328 | 10.17 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22815 | 43.83 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 552486 | 1.81 |
| battery_budget_single_sample | 23756031 | 0.04 |
| battery_budget_heavy_drain | 666871 | 1.50 |
| battery_budget_60_samples | 1293979 | 0.77 |
| smart_motion_accel_change | 23501585 | 0.04 |
| smart_motion_speed_change | 23422986 | 0.04 |


### 2026-08-06 — Commit c45c0992

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81366 | 12.29 |
| schedule_isWithin_5_entries | 74571 | 13.41 |
| location_fromMap | 1470588 | 0.68 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 440528 | 2.27 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4166666 | 0.24 |
| geofence_fromMap_polygon | 1492537 | 0.67 |
| carbon_trip_100_locations | 91575 | 10.92 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 335570 | 2.98 |
| config_toMap | 101729 | 9.83 |
| config_roundtrip | 77101 | 12.97 |
| state_fromMap | 321543 | 3.11 |
| state_toMap | 97943 | 10.21 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21843 | 45.78 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| battery_budget_60_samples | 1286461 | 0.78 |
| smart_motion_accel_change | 22139231 | 0.05 |
| battery_budget_heavy_drain | 662484 | 1.51 |
| battery_budget_single_sample | 22037531 | 0.05 |
| smart_motion_speed_change | 21848921 | 0.05 |


### 2026-08-06 — Commit 3a8472a2

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 89365 | 11.19 |
| schedule_isWithin_5_entries | 81037 | 12.34 |
| location_fromMap | 1449275 | 0.69 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 444444 | 2.25 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 92678 | 10.79 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 342465 | 2.92 |
| config_toMap | 102249 | 9.78 |
| config_roundtrip | 78864 | 12.68 |
| state_fromMap | 334448 | 2.99 |
| state_toMap | 96899 | 10.32 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22441 | 44.56 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| smart_motion_accel_change | 23370380 | 0.04 |
| smart_motion_speed_change | 23460503 | 0.04 |
| battery_budget_single_sample | 23544574 | 0.04 |
| battery_budget_60_samples | 1293832 | 0.77 |
| battery_budget_heavy_drain | 665258 | 1.50 |


### 2026-08-06 — Commit 286f97a6

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88967 | 11.24 |
| schedule_isWithin_5_entries | 79744 | 12.54 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 442477 | 2.26 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1492537 | 0.67 |
| carbon_trip_100_locations | 92336 | 10.83 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 341296 | 2.93 |
| config_toMap | 98135 | 10.19 |
| config_roundtrip | 76394 | 13.09 |
| state_fromMap | 326797 | 3.06 |
| state_toMap | 94607 | 10.57 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22026 | 45.40 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_60_samples | 1294017 | 0.77 |
| smart_motion_accel_change | 23568370 | 0.04 |
| smart_motion_speed_change | 23308383 | 0.04 |
| battery_budget_single_sample | 23782146 | 0.04 |
| battery_budget_heavy_drain | 661988 | 1.51 |


### 2026-08-06 — Commit 401d75d7

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 89686 | 11.15 |
| schedule_isWithin_5_entries | 80385 | 12.44 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 617283 | 1.62 |
| location_fromMap_toMap_roundtrip | 452488 | 2.21 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 93109 | 10.74 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 340136 | 2.94 |
| config_toMap | 99601 | 10.04 |
| config_roundtrip | 77160 | 12.96 |
| state_fromMap | 323624 | 3.09 |
| state_toMap | 95510 | 10.47 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21915 | 45.63 |
| http_config_ssl_toMap | 680272 | 1.47 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 546448 | 1.83 |
| battery_budget_heavy_drain | 665439 | 1.50 |
| battery_budget_single_sample | 23573519 | 0.04 |
| battery_budget_60_samples | 1283214 | 0.78 |
| smart_motion_accel_change | 23142208 | 0.04 |
| smart_motion_speed_change | 23373391 | 0.04 |


### 2026-08-05 — Commit 9855c523

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2941176 | 0.34 |
| schedule_matches | 141442 | 7.07 |
| schedule_isWithin_5_entries | 118764 | 8.42 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 641025 | 1.56 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1666666 | 0.60 |
| carbon_trip_100_locations | 105932 | 9.44 |
| carbon_onLocation | 4347826 | 0.23 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 337837 | 2.96 |
| config_toMap | 101419 | 9.86 |
| config_roundtrip | 79302 | 12.61 |
| state_fromMap | 327868 | 3.05 |
| state_toMap | 98231 | 10.18 |
| route_context_toMap | 2777777 | 0.36 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21734 | 46.01 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 564971 | 1.77 |
| smart_motion_speed_change | 17529148 | 0.06 |
| battery_budget_single_sample | 23981751 | 0.04 |
| battery_budget_heavy_drain | 422803 | 2.37 |
| battery_budget_60_samples | 842488 | 1.19 |
| smart_motion_accel_change | 17541174 | 0.06 |


### 2026-08-05 — Commit cd5f81ef

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 87565 | 11.42 |
| schedule_isWithin_5_entries | 80000 | 12.50 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 456621 | 2.19 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 94073 | 10.63 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 338983 | 2.95 |
| config_toMap | 101010 | 9.90 |
| config_roundtrip | 75528 | 13.24 |
| state_fromMap | 321543 | 3.11 |
| state_toMap | 98231 | 10.18 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1265822 | 0.79 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22217 | 45.01 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 552486 | 1.81 |
| smart_motion_speed_change | 23436119 | 0.04 |
| battery_budget_60_samples | 1289015 | 0.78 |
| smart_motion_accel_change | 23526718 | 0.04 |
| battery_budget_single_sample | 23550940 | 0.04 |
| battery_budget_heavy_drain | 666002 | 1.50 |


### 2026-08-04 — Commit c981815d

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3030303 | 0.33 |
| schedule_matches | 166666 | 6.00 |
| schedule_isWithin_5_entries | 133689 | 7.48 |
| location_fromMap | 1724137 | 0.58 |
| location_toMap | 704225 | 1.42 |
| location_fromMap_toMap_roundtrip | 502512 | 1.99 |
| location_copyWithCoords | 12500000 | 0.08 |
| geofence_fromMap_circular | 5263157 | 0.19 |
| geofence_fromMap_polygon | 1923076 | 0.52 |
| carbon_trip_100_locations | 132625 | 7.54 |
| carbon_onLocation | 5000000 | 0.20 |
| carbon_setActivity | 11111111 | 0.09 |
| carbon_cumulative_report | 2777777 | 0.36 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 370370 | 2.70 |
| config_toMap | 112994 | 8.85 |
| config_roundtrip | 85689 | 11.67 |
| state_fromMap | 359712 | 2.78 |
| state_toMap | 108459 | 9.22 |
| route_context_toMap | 3333333 | 0.30 |
| route_context_fromMap | 2631578 | 0.38 |
| route_context_roundtrip | 1538461 | 0.65 |
| sync_body_context_toMap_50 | 7692307 | 0.13 |
| sync_body_context_fromMap_50 | 26001 | 38.46 |
| http_config_ssl_toMap | 769230 | 1.30 |
| http_config_ssl_fromMap | 2857142 | 0.35 |
| http_config_ssl_roundtrip | 613496 | 1.63 |
| battery_budget_heavy_drain | 403520 | 2.48 |
| battery_budget_60_samples | 792044 | 1.26 |
| smart_motion_speed_change | 15903875 | 0.06 |
| battery_budget_single_sample | 20407251 | 0.05 |
| smart_motion_accel_change | 15629153 | 0.06 |


### 2026-08-04 — Commit 96c37395

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 90171 | 11.09 |
| schedule_isWithin_5_entries | 81234 | 12.31 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 90334 | 11.07 |
| carbon_onLocation | 3846153 | 0.26 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 327868 | 3.05 |
| config_toMap | 100908 | 9.91 |
| config_roundtrip | 76982 | 12.99 |
| state_fromMap | 322580 | 3.10 |
| state_toMap | 98911 | 10.11 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22241 | 44.96 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 552486 | 1.81 |
| smart_motion_speed_change | 23348169 | 0.04 |
| battery_budget_60_samples | 1285475 | 0.78 |
| battery_budget_single_sample | 23750274 | 0.04 |
| battery_budget_heavy_drain | 666605 | 1.50 |
| smart_motion_accel_change | 23551017 | 0.04 |


### 2026-08-03 — Commit 2d100bd0

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 90991 | 10.99 |
| schedule_isWithin_5_entries | 80645 | 12.40 |
| location_fromMap | 1470588 | 0.68 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 432900 | 2.31 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 93632 | 10.68 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 350877 | 2.85 |
| config_toMap | 99800 | 10.02 |
| config_roundtrip | 79491 | 12.58 |
| state_fromMap | 336700 | 2.97 |
| state_toMap | 97656 | 10.24 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22099 | 45.25 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_single_sample | 23729048 | 0.04 |
| battery_budget_heavy_drain | 660092 | 1.51 |
| smart_motion_speed_change | 23360992 | 0.04 |
| battery_budget_60_samples | 1284433 | 0.78 |
| smart_motion_accel_change | 23528131 | 0.04 |


### 2026-08-02 — Commit 36824add

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 86206 | 11.60 |
| schedule_isWithin_5_entries | 79365 | 12.60 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 92421 | 10.82 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 338983 | 2.95 |
| config_toMap | 100401 | 9.96 |
| config_roundtrip | 77220 | 12.95 |
| state_fromMap | 331125 | 3.02 |
| state_toMap | 96432 | 10.37 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21992 | 45.47 |
| http_config_ssl_toMap | 671140 | 1.49 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 543478 | 1.84 |
| battery_budget_60_samples | 1289349 | 0.78 |
| battery_budget_single_sample | 23585100 | 0.04 |
| smart_motion_speed_change | 22997437 | 0.04 |
| battery_budget_heavy_drain | 666248 | 1.50 |
| smart_motion_accel_change | 23540390 | 0.04 |


### 2026-08-01 — Commit 5f9e9893

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 81566 | 12.26 |
| schedule_isWithin_5_entries | 74738 | 13.38 |
| location_fromMap | 1515151 | 0.66 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 452488 | 2.21 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1515151 | 0.66 |
| carbon_trip_100_locations | 91827 | 10.89 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 350877 | 2.85 |
| config_toMap | 102880 | 9.72 |
| config_roundtrip | 79554 | 12.57 |
| state_fromMap | 337837 | 2.96 |
| state_toMap | 99304 | 10.07 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21616 | 46.26 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| smart_motion_accel_change | 22176043 | 0.05 |
| battery_budget_heavy_drain | 662375 | 1.51 |
| smart_motion_speed_change | 22010968 | 0.05 |
| battery_budget_60_samples | 1287523 | 0.78 |
| battery_budget_single_sample | 22012383 | 0.05 |


### 2026-08-01 — Commit 598aa6b7

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 89847 | 11.13 |
| schedule_isWithin_5_entries | 82034 | 12.19 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 632911 | 1.58 |
| location_fromMap_toMap_roundtrip | 467289 | 2.14 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 92506 | 10.81 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 348432 | 2.87 |
| config_toMap | 102880 | 9.72 |
| config_roundtrip | 78988 | 12.66 |
| state_fromMap | 337837 | 2.96 |
| state_toMap | 97751 | 10.23 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22084 | 45.28 |
| http_config_ssl_toMap | 714285 | 1.40 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| smart_motion_speed_change | 23346592 | 0.04 |
| battery_budget_single_sample | 23761741 | 0.04 |
| battery_budget_60_samples | 1290687 | 0.77 |
| battery_budget_heavy_drain | 664460 | 1.50 |
| smart_motion_accel_change | 23512280 | 0.04 |


### 2026-08-01 — Commit d776795a

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 87032 | 11.49 |
| schedule_isWithin_5_entries | 81833 | 12.22 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4761904 | 0.21 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 90744 | 11.02 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 342465 | 2.92 |
| config_toMap | 102669 | 9.74 |
| config_roundtrip | 78616 | 12.72 |
| state_fromMap | 330033 | 3.03 |
| state_toMap | 97847 | 10.22 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1428571 | 0.70 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 21920 | 45.62 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_single_sample | 23768327 | 0.04 |
| battery_budget_heavy_drain | 666285 | 1.50 |
| smart_motion_speed_change | 23484561 | 0.04 |
| smart_motion_accel_change | 23494562 | 0.04 |
| battery_budget_60_samples | 1294098 | 0.77 |


### 2026-08-01 — Commit 24f6fcbb

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 87950 | 11.37 |
| schedule_isWithin_5_entries | 81366 | 12.29 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 446428 | 2.24 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1515151 | 0.66 |
| carbon_trip_100_locations | 92592 | 10.80 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 349650 | 2.86 |
| config_toMap | 101112 | 9.89 |
| config_roundtrip | 77459 | 12.91 |
| state_fromMap | 335570 | 2.98 |
| state_toMap | 97560 | 10.25 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22133 | 45.18 |
| http_config_ssl_toMap | 680272 | 1.47 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 549450 | 1.82 |
| battery_budget_heavy_drain | 665956 | 1.50 |
| battery_budget_single_sample | 23549848 | 0.04 |
| battery_budget_60_samples | 1291709 | 0.77 |
| smart_motion_speed_change | 23384740 | 0.04 |
| smart_motion_accel_change | 23500208 | 0.04 |


### 2026-08-01 — Commit 082e2d8b

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 86880 | 11.51 |
| schedule_isWithin_5_entries | 79872 | 12.52 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 454545 | 2.20 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 92336 | 10.83 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 350877 | 2.85 |
| config_toMap | 101419 | 9.86 |
| config_roundtrip | 77700 | 12.87 |
| state_fromMap | 336700 | 2.97 |
| state_toMap | 97751 | 10.23 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22296 | 44.85 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 549450 | 1.82 |
| smart_motion_speed_change | 23332802 | 0.04 |
| battery_budget_60_samples | 1292855 | 0.77 |
| battery_budget_single_sample | 23764896 | 0.04 |
| battery_budget_heavy_drain | 665575 | 1.50 |
| smart_motion_accel_change | 23547219 | 0.04 |


### 2026-07-29 — Commit 098edc89

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88028 | 11.36 |
| schedule_isWithin_5_entries | 79302 | 12.61 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 448430 | 2.23 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 93632 | 10.68 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 327868 | 3.05 |
| config_toMap | 100401 | 9.96 |
| config_roundtrip | 77220 | 12.95 |
| state_fromMap | 326797 | 3.06 |
| state_toMap | 97656 | 10.24 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22002 | 45.45 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| smart_motion_accel_change | 23525729 | 0.04 |
| smart_motion_speed_change | 23225030 | 0.04 |
| battery_budget_single_sample | 23600150 | 0.04 |
| battery_budget_60_samples | 1292530 | 0.77 |
| battery_budget_heavy_drain | 665934 | 1.50 |


### 2026-07-29 — Commit 280f5945

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81766 | 12.23 |
| schedule_isWithin_5_entries | 74738 | 13.38 |
| location_fromMap | 1470588 | 0.68 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 460829 | 2.17 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 86206 | 11.60 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 350877 | 2.85 |
| config_toMap | 100908 | 9.91 |
| config_roundtrip | 76628 | 13.05 |
| state_fromMap | 335570 | 2.98 |
| state_toMap | 97943 | 10.21 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21663 | 46.16 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 564971 | 1.77 |
| battery_budget_single_sample | 22035677 | 0.05 |
| battery_budget_60_samples | 1280100 | 0.78 |
| smart_motion_accel_change | 21962397 | 0.05 |
| smart_motion_speed_change | 21489479 | 0.05 |
| battery_budget_heavy_drain | 663160 | 1.51 |


