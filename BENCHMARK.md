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


### 2026-07-29 — Commit c8085b48

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2631578 | 0.38 |
| schedule_matches | 88809 | 11.26 |
| schedule_isWithin_5_entries | 80256 | 12.46 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 625000 | 1.60 |
| location_fromMap_toMap_roundtrip | 467289 | 2.14 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 92336 | 10.83 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 342465 | 2.92 |
| config_toMap | 100908 | 9.91 |
| config_roundtrip | 77399 | 12.92 |
| state_fromMap | 334448 | 2.99 |
| state_toMap | 98039 | 10.20 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21724 | 46.03 |
| http_config_ssl_toMap | 680272 | 1.47 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_heavy_drain | 664823 | 1.50 |
| battery_budget_single_sample | 23767168 | 0.04 |
| battery_budget_60_samples | 1285405 | 0.78 |
| smart_motion_accel_change | 23555759 | 0.04 |
| smart_motion_speed_change | 23173450 | 0.04 |


### 2026-07-29 — Commit 6586832e

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 86580 | 11.55 |
| schedule_isWithin_5_entries | 79554 | 12.57 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 471698 | 2.12 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 89928 | 11.12 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 343642 | 2.91 |
| config_toMap | 100000 | 10.00 |
| config_roundtrip | 78003 | 12.82 |
| state_fromMap | 333333 | 3.00 |
| state_toMap | 96432 | 10.37 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22011 | 45.43 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 549450 | 1.82 |
| battery_budget_single_sample | 23633894 | 0.04 |
| smart_motion_accel_change | 23484984 | 0.04 |
| battery_budget_60_samples | 1290882 | 0.77 |
| battery_budget_heavy_drain | 665618 | 1.50 |
| smart_motion_speed_change | 23387971 | 0.04 |


### 2026-07-29 — Commit f1d110e5

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 88495 | 11.30 |
| schedule_isWithin_5_entries | 79872 | 12.52 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 94250 | 10.61 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 334448 | 2.99 |
| config_toMap | 100704 | 9.93 |
| config_roundtrip | 77160 | 12.96 |
| state_fromMap | 328947 | 3.04 |
| state_toMap | 96899 | 10.32 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22158 | 45.13 |
| http_config_ssl_toMap | 680272 | 1.47 |
| http_config_ssl_fromMap | 2702702 | 0.37 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_single_sample | 23741753 | 0.04 |
| smart_motion_speed_change | 23333781 | 0.04 |
| battery_budget_60_samples | 1279909 | 0.78 |
| smart_motion_accel_change | 23279360 | 0.04 |
| battery_budget_heavy_drain | 666137 | 1.50 |


### 2026-07-29 — Commit 4c56f385

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 88809 | 11.26 |
| schedule_isWithin_5_entries | 80000 | 12.50 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 657894 | 1.52 |
| location_fromMap_toMap_roundtrip | 469483 | 2.13 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 91911 | 10.88 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 343642 | 2.91 |
| config_toMap | 100100 | 9.99 |
| config_roundtrip | 77519 | 12.90 |
| state_fromMap | 324675 | 3.08 |
| state_toMap | 94517 | 10.58 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 21834 | 45.80 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 546448 | 1.83 |
| battery_budget_single_sample | 22769749 | 0.04 |
| battery_budget_60_samples | 1244048 | 0.80 |
| smart_motion_accel_change | 23540224 | 0.04 |
| smart_motion_speed_change | 23387982 | 0.04 |
| battery_budget_heavy_drain | 646693 | 1.55 |


### 2026-07-29 — Commit e241844d

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81833 | 12.22 |
| schedule_isWithin_5_entries | 74294 | 13.46 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 91575 | 10.92 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 347222 | 2.88 |
| config_toMap | 103519 | 9.66 |
| config_roundtrip | 78308 | 12.77 |
| state_fromMap | 327868 | 3.05 |
| state_toMap | 100908 | 9.91 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21691 | 46.10 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_heavy_drain | 663146 | 1.51 |
| battery_budget_60_samples | 1285579 | 0.78 |
| smart_motion_speed_change | 21986715 | 0.05 |
| smart_motion_accel_change | 22147128 | 0.05 |
| battery_budget_single_sample | 22034442 | 0.05 |


### 2026-07-28 — Commit 271f8465

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 87796 | 11.39 |
| schedule_isWithin_5_entries | 79365 | 12.60 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 454545 | 2.20 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 91911 | 10.88 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 335570 | 2.98 |
| config_toMap | 102145 | 9.79 |
| config_roundtrip | 79491 | 12.58 |
| state_fromMap | 324675 | 3.08 |
| state_toMap | 98619 | 10.14 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22148 | 45.15 |
| http_config_ssl_toMap | 684931 | 1.46 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| smart_motion_speed_change | 23359934 | 0.04 |
| smart_motion_accel_change | 23499802 | 0.04 |
| battery_budget_60_samples | 1291751 | 0.77 |
| battery_budget_heavy_drain | 665803 | 1.50 |
| battery_budget_single_sample | 23552824 | 0.04 |


### 2026-07-28 — Commit c29e8cb5

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 90661 | 11.03 |
| schedule_isWithin_5_entries | 83263 | 12.01 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 641025 | 1.56 |
| location_fromMap_toMap_roundtrip | 467289 | 2.14 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1369863 | 0.73 |
| carbon_trip_100_locations | 92250 | 10.84 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 354609 | 2.82 |
| config_toMap | 101729 | 9.83 |
| config_roundtrip | 79302 | 12.61 |
| state_fromMap | 341296 | 2.93 |
| state_toMap | 99502 | 10.05 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22119 | 45.21 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_60_samples | 1288893 | 0.78 |
| smart_motion_speed_change | 21880782 | 0.05 |
| smart_motion_accel_change | 23538314 | 0.04 |
| battery_budget_heavy_drain | 665788 | 1.50 |
| battery_budget_single_sample | 23773793 | 0.04 |


### 2026-07-27 — Commit cf68d56d

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 87950 | 11.37 |
| schedule_isWithin_5_entries | 81366 | 12.29 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4166666 | 0.24 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 92764 | 10.78 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 16666666 | 0.06 |
| persist_decider_geofence | 16666666 | 0.06 |
| config_fromMap | 337837 | 2.96 |
| config_toMap | 101010 | 9.90 |
| config_roundtrip | 77942 | 12.83 |
| state_fromMap | 324675 | 3.08 |
| state_toMap | 98619 | 10.14 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6250000 | 0.16 |
| sync_body_context_fromMap_50 | 22133 | 45.18 |
| http_config_ssl_toMap | 680272 | 1.47 |
| http_config_ssl_fromMap | 2500000 | 0.40 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_single_sample | 23586407 | 0.04 |
| battery_budget_60_samples | 1288662 | 0.78 |
| smart_motion_accel_change | 23356220 | 0.04 |
| battery_budget_heavy_drain | 665090 | 1.50 |
| smart_motion_speed_change | 23425642 | 0.04 |


### 2026-07-27 — Commit 2d7b5c95

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3333333 | 0.30 |
| schedule_matches | 197628 | 5.06 |
| schedule_isWithin_5_entries | 160771 | 6.22 |
| location_fromMap | 2040816 | 0.49 |
| location_toMap | 775193 | 1.29 |
| location_fromMap_toMap_roundtrip | 558659 | 1.79 |
| location_copyWithCoords | 14285714 | 0.07 |
| geofence_fromMap_circular | 5882352 | 0.17 |
| geofence_fromMap_polygon | 2083333 | 0.48 |
| carbon_trip_100_locations | 124378 | 8.04 |
| carbon_onLocation | 5000000 | 0.20 |
| carbon_setActivity | 12500000 | 0.08 |
| carbon_cumulative_report | 3225806 | 0.31 |
| persist_decider_location | 25000000 | 0.04 |
| persist_decider_geofence | 25000000 | 0.04 |
| config_fromMap | 425531 | 2.35 |
| config_toMap | 124843 | 8.01 |
| config_roundtrip | 95057 | 10.52 |
| state_fromMap | 413223 | 2.42 |
| state_toMap | 119760 | 8.35 |
| route_context_toMap | 3571428 | 0.28 |
| route_context_fromMap | 3030303 | 0.33 |
| route_context_roundtrip | 1754385 | 0.57 |
| sync_body_context_toMap_50 | 8333333 | 0.12 |
| sync_body_context_fromMap_50 | 28042 | 35.66 |
| http_config_ssl_toMap | 819672 | 1.22 |
| http_config_ssl_fromMap | 3225806 | 0.31 |
| http_config_ssl_roundtrip | 666666 | 1.50 |
| battery_budget_60_samples | 907586 | 1.10 |
| battery_budget_heavy_drain | 458669 | 2.18 |
| smart_motion_accel_change | 17798857 | 0.06 |
| smart_motion_speed_change | 18074414 | 0.06 |
| battery_budget_single_sample | 23564819 | 0.04 |


### 2026-07-27 — Commit 15363213

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 90991 | 10.99 |
| schedule_isWithin_5_entries | 83542 | 11.97 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 657894 | 1.52 |
| location_fromMap_toMap_roundtrip | 476190 | 2.10 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 92250 | 10.84 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 355871 | 2.81 |
| config_toMap | 103842 | 9.63 |
| config_roundtrip | 80775 | 12.38 |
| state_fromMap | 346020 | 2.89 |
| state_toMap | 101010 | 9.90 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22805 | 43.85 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| battery_budget_heavy_drain | 666423 | 1.50 |
| smart_motion_accel_change | 23559437 | 0.04 |
| battery_budget_single_sample | 23726772 | 0.04 |
| battery_budget_60_samples | 1292963 | 0.77 |
| smart_motion_speed_change | 23370577 | 0.04 |


### 2026-07-26 — Commit 18540324

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81566 | 12.26 |
| schedule_isWithin_5_entries | 74738 | 13.38 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 641025 | 1.56 |
| location_fromMap_toMap_roundtrip | 460829 | 2.17 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 90497 | 11.05 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 353356 | 2.83 |
| config_toMap | 103305 | 9.68 |
| config_roundtrip | 77339 | 12.93 |
| state_fromMap | 332225 | 3.01 |
| state_toMap | 97943 | 10.21 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1315789 | 0.76 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21781 | 45.91 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_heavy_drain | 661290 | 1.51 |
| battery_budget_single_sample | 22035639 | 0.05 |
| battery_budget_60_samples | 1276187 | 0.78 |
| smart_motion_accel_change | 22130092 | 0.05 |
| smart_motion_speed_change | 21914165 | 0.05 |


### 2026-07-26 — Commit 14fc70df

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3571428 | 0.28 |
| schedule_matches | 106609 | 9.38 |
| schedule_isWithin_5_entries | 95147 | 10.51 |
| location_fromMap | 2040816 | 0.49 |
| location_toMap | 800000 | 1.25 |
| location_fromMap_toMap_roundtrip | 588235 | 1.70 |
| location_copyWithCoords | 14285714 | 0.07 |
| geofence_fromMap_circular | 5555555 | 0.18 |
| geofence_fromMap_polygon | 1960784 | 0.51 |
| carbon_trip_100_locations | 116822 | 8.56 |
| carbon_onLocation | 5000000 | 0.20 |
| carbon_setActivity | 11111111 | 0.09 |
| carbon_cumulative_report | 3125000 | 0.32 |
| persist_decider_location | 25000000 | 0.04 |
| persist_decider_geofence | 25000000 | 0.04 |
| config_fromMap | 440528 | 2.27 |
| config_toMap | 129366 | 7.73 |
| config_roundtrip | 99900 | 10.01 |
| state_fromMap | 413223 | 2.42 |
| state_toMap | 125786 | 7.95 |
| route_context_toMap | 3571428 | 0.28 |
| route_context_fromMap | 2702702 | 0.37 |
| route_context_roundtrip | 1666666 | 0.60 |
| sync_body_context_toMap_50 | 8333333 | 0.12 |
| sync_body_context_fromMap_50 | 27839 | 35.92 |
| http_config_ssl_toMap | 840336 | 1.19 |
| http_config_ssl_fromMap | 3225806 | 0.31 |
| http_config_ssl_roundtrip | 680272 | 1.47 |
| smart_motion_speed_change | 28192608 | 0.04 |
| battery_budget_heavy_drain | 844798 | 1.18 |
| battery_budget_single_sample | 28410743 | 0.04 |
| battery_budget_60_samples | 1639418 | 0.61 |
| smart_motion_accel_change | 28481772 | 0.04 |


### 2026-07-26 — Commit 5cf3ddcf

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 86730 | 11.53 |
| schedule_isWithin_5_entries | 79051 | 12.65 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 92506 | 10.81 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 338983 | 2.95 |
| config_toMap | 103842 | 9.63 |
| config_roundtrip | 78802 | 12.69 |
| state_fromMap | 322580 | 3.10 |
| state_toMap | 99009 | 10.10 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22084 | 45.28 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 549450 | 1.82 |
| battery_budget_single_sample | 23754660 | 0.04 |
| battery_budget_60_samples | 1291649 | 0.77 |
| battery_budget_heavy_drain | 665552 | 1.50 |
| smart_motion_speed_change | 23292178 | 0.04 |
| smart_motion_accel_change | 23521559 | 0.04 |


### 2026-07-26 — Commit d932b680

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 89365 | 11.19 |
| schedule_isWithin_5_entries | 80906 | 12.36 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 467289 | 2.14 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 91827 | 10.89 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 16666666 | 0.06 |
| config_fromMap | 330033 | 3.03 |
| config_toMap | 100300 | 9.97 |
| config_roundtrip | 77942 | 12.83 |
| state_fromMap | 321543 | 3.11 |
| state_toMap | 97370 | 10.27 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21372 | 46.79 |
| http_config_ssl_toMap | 680272 | 1.47 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 546448 | 1.83 |
| smart_motion_accel_change | 23098038 | 0.04 |
| battery_budget_single_sample | 23477282 | 0.04 |
| smart_motion_speed_change | 23177396 | 0.04 |
| battery_budget_heavy_drain | 665595 | 1.50 |
| battery_budget_60_samples | 1292231 | 0.77 |


### 2026-07-26 — Commit 5bfde2d9

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3030303 | 0.33 |
| schedule_matches | 145985 | 6.85 |
| schedule_isWithin_5_entries | 124378 | 8.04 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 657894 | 1.52 |
| location_fromMap_toMap_roundtrip | 469483 | 2.13 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 110497 | 9.05 |
| carbon_onLocation | 4347826 | 0.23 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 358422 | 2.79 |
| config_toMap | 109409 | 9.14 |
| config_roundtrip | 83542 | 11.97 |
| state_fromMap | 353356 | 2.83 |
| state_toMap | 105263 | 9.50 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22930 | 43.61 |
| http_config_ssl_toMap | 729927 | 1.37 |
| http_config_ssl_fromMap | 2702702 | 0.37 |
| http_config_ssl_roundtrip | 588235 | 1.70 |
| battery_budget_60_samples | 842986 | 1.19 |
| battery_budget_single_sample | 23981098 | 0.04 |
| smart_motion_accel_change | 17539721 | 0.06 |
| smart_motion_speed_change | 17560723 | 0.06 |
| battery_budget_heavy_drain | 422496 | 2.37 |


### 2026-07-26 — Commit 3ac66f4e

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 88652 | 11.28 |
| schedule_isWithin_5_entries | 82440 | 12.13 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4761904 | 0.21 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 93457 | 10.70 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 336700 | 2.97 |
| config_toMap | 101214 | 9.88 |
| config_roundtrip | 77041 | 12.98 |
| state_fromMap | 323624 | 3.09 |
| state_toMap | 98911 | 10.11 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21944 | 45.57 |
| http_config_ssl_toMap | 684931 | 1.46 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 546448 | 1.83 |
| smart_motion_speed_change | 23447496 | 0.04 |
| battery_budget_60_samples | 1291154 | 0.77 |
| battery_budget_heavy_drain | 665735 | 1.50 |
| battery_budget_single_sample | 23561778 | 0.04 |
| smart_motion_accel_change | 23556241 | 0.04 |


### 2026-07-26 — Commit a69ee0e3

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 87565 | 11.42 |
| schedule_isWithin_5_entries | 79239 | 12.62 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 93545 | 10.69 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 338983 | 2.95 |
| config_toMap | 103092 | 9.70 |
| config_roundtrip | 78369 | 12.76 |
| state_fromMap | 334448 | 2.99 |
| state_toMap | 98911 | 10.11 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21786 | 45.90 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_single_sample | 23595994 | 0.04 |
| battery_budget_60_samples | 1293406 | 0.77 |
| battery_budget_heavy_drain | 664966 | 1.50 |
| smart_motion_accel_change | 23522646 | 0.04 |
| smart_motion_speed_change | 23102306 | 0.04 |


### 2026-07-26 — Commit 1555f207

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 87719 | 11.40 |
| schedule_isWithin_5_entries | 80000 | 12.50 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 632911 | 1.58 |
| location_fromMap_toMap_roundtrip | 462962 | 2.16 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 92421 | 10.82 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 333333 | 3.00 |
| config_toMap | 101936 | 9.81 |
| config_roundtrip | 78864 | 12.68 |
| state_fromMap | 321543 | 3.11 |
| state_toMap | 98814 | 10.12 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22502 | 44.44 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 552486 | 1.81 |
| battery_budget_single_sample | 23708108 | 0.04 |
| battery_budget_heavy_drain | 666590 | 1.50 |
| smart_motion_speed_change | 23390040 | 0.04 |
| battery_budget_60_samples | 1292654 | 0.77 |
| smart_motion_accel_change | 23529615 | 0.04 |


### 2026-07-25 — Commit 12506d55

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 90415 | 11.06 |
| schedule_isWithin_5_entries | 80450 | 12.43 |
| location_fromMap | 877192 | 1.14 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 373134 | 2.68 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 93632 | 10.68 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 342465 | 2.92 |
| config_toMap | 102249 | 9.78 |
| config_roundtrip | 78616 | 12.72 |
| state_fromMap | 330033 | 3.03 |
| state_toMap | 98135 | 10.19 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21920 | 45.62 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 552486 | 1.81 |
| battery_budget_60_samples | 1282731 | 0.78 |
| smart_motion_speed_change | 23387733 | 0.04 |
| battery_budget_heavy_drain | 663479 | 1.51 |
| smart_motion_accel_change | 23540779 | 0.04 |
| battery_budget_single_sample | 23578980 | 0.04 |


### 2026-07-25 — Commit 99759d12

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 89047 | 11.23 |
| schedule_isWithin_5_entries | 82034 | 12.19 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 91575 | 10.92 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 344827 | 2.90 |
| config_toMap | 103199 | 9.69 |
| config_roundtrip | 78554 | 12.73 |
| state_fromMap | 328947 | 3.04 |
| state_toMap | 98619 | 10.14 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22371 | 44.70 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_heavy_drain | 664052 | 1.51 |
| smart_motion_speed_change | 23324768 | 0.04 |
| battery_budget_single_sample | 23592610 | 0.04 |
| smart_motion_accel_change | 23412088 | 0.04 |
| battery_budget_60_samples | 1291842 | 0.77 |


### 2026-07-25 — Commit 692f7c09

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 89047 | 11.23 |
| schedule_isWithin_5_entries | 79872 | 12.52 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 93196 | 10.73 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 344827 | 2.90 |
| config_toMap | 103734 | 9.64 |
| config_roundtrip | 78926 | 12.67 |
| state_fromMap | 332225 | 3.01 |
| state_toMap | 98425 | 10.16 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22104 | 45.24 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2500000 | 0.40 |
| http_config_ssl_roundtrip | 546448 | 1.83 |
| battery_budget_single_sample | 23590997 | 0.04 |
| battery_budget_60_samples | 1292208 | 0.77 |
| smart_motion_accel_change | 23586133 | 0.04 |
| battery_budget_heavy_drain | 666233 | 1.50 |
| smart_motion_speed_change | 23428292 | 0.04 |


### 2026-07-24 — Commit aaa2d8f7

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2941176 | 0.34 |
| schedule_matches | 136986 | 7.30 |
| schedule_isWithin_5_entries | 117924 | 8.48 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 617283 | 1.62 |
| location_fromMap_toMap_roundtrip | 450450 | 2.22 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 108932 | 9.18 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 342465 | 2.92 |
| config_toMap | 103305 | 9.68 |
| config_roundtrip | 81037 | 12.34 |
| state_fromMap | 336700 | 2.97 |
| state_toMap | 101522 | 9.85 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 21612 | 46.27 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 568181 | 1.76 |
| battery_budget_60_samples | 843534 | 1.19 |
| smart_motion_accel_change | 17493681 | 0.06 |
| smart_motion_speed_change | 17557454 | 0.06 |
| battery_budget_heavy_drain | 423515 | 2.36 |
| battery_budget_single_sample | 23979367 | 0.04 |


### 2026-07-24 — Commit eb346ecd

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 82781 | 12.08 |
| schedule_isWithin_5_entries | 75414 | 13.26 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 462962 | 2.16 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 90744 | 11.02 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 328947 | 3.04 |
| config_toMap | 102986 | 9.71 |
| config_roundtrip | 78988 | 12.66 |
| state_fromMap | 330033 | 3.03 |
| state_toMap | 98911 | 10.11 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1315789 | 0.76 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21317 | 46.91 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_single_sample | 22025636 | 0.05 |
| smart_motion_accel_change | 22163203 | 0.05 |
| battery_budget_60_samples | 1287714 | 0.78 |
| smart_motion_speed_change | 21859430 | 0.05 |
| battery_budget_heavy_drain | 663001 | 1.51 |


### 2026-07-24 — Commit a2cf23af

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81300 | 12.30 |
| schedule_isWithin_5_entries | 74794 | 13.37 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 632911 | 1.58 |
| location_fromMap_toMap_roundtrip | 467289 | 2.14 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 89525 | 11.17 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 8333333 | 0.12 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 341296 | 2.93 |
| config_toMap | 101317 | 9.87 |
| config_roundtrip | 77639 | 12.88 |
| state_fromMap | 333333 | 3.00 |
| state_toMap | 99700 | 10.03 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1315789 | 0.76 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21431 | 46.66 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| battery_budget_60_samples | 1286991 | 0.78 |
| battery_budget_heavy_drain | 662765 | 1.51 |
| battery_budget_single_sample | 22042618 | 0.05 |
| smart_motion_speed_change | 21958543 | 0.05 |
| smart_motion_accel_change | 22149694 | 0.05 |


### 2026-07-24 — Commit 29241c65

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 89928 | 11.12 |
| schedule_isWithin_5_entries | 81499 | 12.27 |
| location_fromMap | 1515151 | 0.66 |
| location_toMap | 625000 | 1.60 |
| location_fromMap_toMap_roundtrip | 448430 | 2.23 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 92165 | 10.85 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 344827 | 2.90 |
| config_toMap | 99403 | 10.06 |
| config_roundtrip | 76277 | 13.11 |
| state_fromMap | 331125 | 3.02 |
| state_toMap | 98328 | 10.17 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1315789 | 0.76 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22114 | 45.22 |
| http_config_ssl_toMap | 628930 | 1.59 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 512820 | 1.95 |
| smart_motion_speed_change | 23474651 | 0.04 |
| battery_budget_heavy_drain | 663034 | 1.51 |
| smart_motion_accel_change | 22982985 | 0.04 |
| battery_budget_single_sample | 23573287 | 0.04 |
| battery_budget_60_samples | 1291611 | 0.77 |


### 2026-07-24 — Commit 3f69dd0b

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 79744 | 12.54 |
| schedule_isWithin_5_entries | 75075 | 13.32 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 469483 | 2.13 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 90909 | 11.00 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 344827 | 2.90 |
| config_toMap | 103734 | 9.64 |
| config_roundtrip | 79681 | 12.55 |
| state_fromMap | 330033 | 3.03 |
| state_toMap | 98814 | 10.12 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1315789 | 0.76 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21570 | 46.36 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 568181 | 1.76 |
| smart_motion_accel_change | 22124460 | 0.05 |
| battery_budget_heavy_drain | 663678 | 1.51 |
| battery_budget_single_sample | 22041141 | 0.05 |
| smart_motion_speed_change | 22017084 | 0.05 |
| battery_budget_60_samples | 1288747 | 0.78 |


### 2026-07-24 — Commit 854eed97

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 83194 | 12.02 |
| schedule_isWithin_5_entries | 76335 | 13.10 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 446428 | 2.24 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 91407 | 10.94 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 320512 | 3.12 |
| config_toMap | 103092 | 9.70 |
| config_roundtrip | 78003 | 12.82 |
| state_fromMap | 333333 | 3.00 |
| state_toMap | 100806 | 9.92 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21901 | 45.66 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2439024 | 0.41 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_60_samples | 1287853 | 0.78 |
| battery_budget_single_sample | 21999519 | 0.05 |
| battery_budget_heavy_drain | 659421 | 1.52 |
| smart_motion_speed_change | 21899867 | 0.05 |
| smart_motion_accel_change | 22134116 | 0.05 |


### 2026-07-23 — Commit d76267ae

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 88105 | 11.35 |
| schedule_isWithin_5_entries | 79872 | 12.52 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 467289 | 2.14 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 93196 | 10.73 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 342465 | 2.92 |
| config_toMap | 102145 | 9.79 |
| config_roundtrip | 77881 | 12.84 |
| state_fromMap | 328947 | 3.04 |
| state_toMap | 96246 | 10.39 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21838 | 45.79 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 549450 | 1.82 |
| smart_motion_speed_change | 23409056 | 0.04 |
| battery_budget_single_sample | 23588051 | 0.04 |
| battery_budget_60_samples | 1292294 | 0.77 |
| battery_budget_heavy_drain | 664392 | 1.51 |
| smart_motion_accel_change | 23542434 | 0.04 |


### 2026-07-23 — Commit baa66e5d

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3571428 | 0.28 |
| schedule_matches | 200803 | 4.98 |
| schedule_isWithin_5_entries | 163666 | 6.11 |
| location_fromMap | 2127659 | 0.47 |
| location_toMap | 806451 | 1.24 |
| location_fromMap_toMap_roundtrip | 598802 | 1.67 |
| location_copyWithCoords | 14285714 | 0.07 |
| geofence_fromMap_circular | 6250000 | 0.16 |
| geofence_fromMap_polygon | 2000000 | 0.50 |
| carbon_trip_100_locations | 160513 | 6.23 |
| carbon_onLocation | 5882352 | 0.17 |
| carbon_setActivity | 12500000 | 0.08 |
| carbon_cumulative_report | 3448275 | 0.29 |
| persist_decider_location | 25000000 | 0.04 |
| persist_decider_geofence | 25000000 | 0.04 |
| config_fromMap | 446428 | 2.24 |
| config_toMap | 134228 | 7.45 |
| config_roundtrip | 103092 | 9.70 |
| state_fromMap | 432900 | 2.31 |
| state_toMap | 126742 | 7.89 |
| route_context_toMap | 3846153 | 0.26 |
| route_context_fromMap | 3225806 | 0.31 |
| route_context_roundtrip | 1851851 | 0.54 |
| sync_body_context_toMap_50 | 9090909 | 0.11 |
| sync_body_context_fromMap_50 | 30590 | 32.69 |
| http_config_ssl_toMap | 909090 | 1.10 |
| http_config_ssl_fromMap | 3448275 | 0.29 |
| http_config_ssl_roundtrip | 735294 | 1.36 |
| battery_budget_60_samples | 909548 | 1.10 |
| battery_budget_heavy_drain | 459763 | 2.18 |
| smart_motion_accel_change | 18194048 | 0.05 |
| battery_budget_single_sample | 23752147 | 0.04 |
| smart_motion_speed_change | 18216035 | 0.05 |


### 2026-07-23 — Commit cf545800

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2941176 | 0.34 |
| schedule_matches | 158730 | 6.30 |
| schedule_isWithin_5_entries | 129701 | 7.71 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 478468 | 2.09 |
| location_copyWithCoords | 12500000 | 0.08 |
| geofence_fromMap_circular | 4761904 | 0.21 |
| geofence_fromMap_polygon | 1754385 | 0.57 |
| carbon_trip_100_locations | 132802 | 7.53 |
| carbon_onLocation | 4761904 | 0.21 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2857142 | 0.35 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 342465 | 2.92 |
| config_toMap | 108108 | 9.25 |
| config_roundtrip | 79176 | 12.63 |
| state_fromMap | 333333 | 3.00 |
| state_toMap | 105263 | 9.50 |
| route_context_toMap | 3125000 | 0.32 |
| route_context_fromMap | 2564102 | 0.39 |
| route_context_roundtrip | 1470588 | 0.68 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 24975 | 40.04 |
| http_config_ssl_toMap | 729927 | 1.37 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 564971 | 1.77 |
| battery_budget_single_sample | 20022936 | 0.05 |
| battery_budget_60_samples | 762731 | 1.31 |
| smart_motion_speed_change | 15312132 | 0.07 |
| battery_budget_heavy_drain | 387668 | 2.58 |
| smart_motion_accel_change | 15383167 | 0.07 |


### 2026-07-23 — Commit 0122e269

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 4545454 | 0.22 |
| schedule_matches | 246305 | 4.06 |
| schedule_isWithin_5_entries | 196850 | 5.08 |
| location_fromMap | 2500000 | 0.40 |
| location_toMap | 961538 | 1.04 |
| location_fromMap_toMap_roundtrip | 699300 | 1.43 |
| location_copyWithCoords | 16666666 | 0.06 |
| geofence_fromMap_circular | 7142857 | 0.14 |
| geofence_fromMap_polygon | 2702702 | 0.37 |
| carbon_trip_100_locations | 187265 | 5.34 |
| carbon_onLocation | 5882352 | 0.17 |
| carbon_setActivity | 14285714 | 0.07 |
| carbon_cumulative_report | 4000000 | 0.25 |
| persist_decider_location | 25000000 | 0.04 |
| persist_decider_geofence | 25000000 | 0.04 |
| config_fromMap | 564971 | 1.77 |
| config_toMap | 152905 | 6.54 |
| config_roundtrip | 117233 | 8.53 |
| state_fromMap | 546448 | 1.83 |
| state_toMap | 148367 | 6.74 |
| route_context_toMap | 4347826 | 0.23 |
| route_context_fromMap | 3571428 | 0.28 |
| route_context_roundtrip | 2040816 | 0.49 |
| sync_body_context_toMap_50 | 10000000 | 0.10 |
| sync_body_context_fromMap_50 | 36166 | 27.65 |
| http_config_ssl_toMap | 1063829 | 0.94 |
| http_config_ssl_fromMap | 4166666 | 0.24 |
| http_config_ssl_roundtrip | 840336 | 1.19 |
| smart_motion_accel_change | 19857600 | 0.05 |
| battery_budget_single_sample | 27232971 | 0.04 |
| battery_budget_60_samples | 1026570 | 0.97 |
| battery_budget_heavy_drain | 539348 | 1.85 |
| smart_motion_speed_change | 19758198 | 0.05 |


### 2026-07-23 — Commit 4507e4e3

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88967 | 11.24 |
| schedule_isWithin_5_entries | 78926 | 12.67 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 662251 | 1.51 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4761904 | 0.21 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 93023 | 10.75 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 348432 | 2.87 |
| config_toMap | 103305 | 9.68 |
| config_roundtrip | 79617 | 12.56 |
| state_fromMap | 335570 | 2.98 |
| state_toMap | 100502 | 9.95 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22301 | 44.84 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| battery_budget_single_sample | 23778506 | 0.04 |
| battery_budget_heavy_drain | 666623 | 1.50 |
| battery_budget_60_samples | 1293199 | 0.77 |
| smart_motion_speed_change | 23176230 | 0.04 |
| smart_motion_accel_change | 23536262 | 0.04 |


### 2026-07-23 — Commit 624f670d

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 87565 | 11.42 |
| schedule_isWithin_5_entries | 80906 | 12.36 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 632911 | 1.58 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 93370 | 10.71 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 337837 | 2.96 |
| config_toMap | 101317 | 9.87 |
| config_roundtrip | 78740 | 12.70 |
| state_fromMap | 330033 | 3.03 |
| state_toMap | 99700 | 10.03 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 21905 | 45.65 |
| http_config_ssl_toMap | 684931 | 1.46 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 549450 | 1.82 |
| battery_budget_60_samples | 1292588 | 0.77 |
| smart_motion_accel_change | 23543537 | 0.04 |
| smart_motion_speed_change | 23388962 | 0.04 |
| battery_budget_single_sample | 23775615 | 0.04 |
| battery_budget_heavy_drain | 665873 | 1.50 |


### 2026-07-22 — Commit bf65354b

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2941176 | 0.34 |
| schedule_matches | 165562 | 6.04 |
| schedule_isWithin_5_entries | 136054 | 7.35 |
| location_fromMap | 1851851 | 0.54 |
| location_toMap | 689655 | 1.45 |
| location_fromMap_toMap_roundtrip | 495049 | 2.02 |
| location_copyWithCoords | 12500000 | 0.08 |
| geofence_fromMap_circular | 5555555 | 0.18 |
| geofence_fromMap_polygon | 1923076 | 0.52 |
| carbon_trip_100_locations | 138312 | 7.23 |
| carbon_onLocation | 4761904 | 0.21 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2857142 | 0.35 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 381679 | 2.62 |
| config_toMap | 112485 | 8.89 |
| config_roundtrip | 84674 | 11.81 |
| state_fromMap | 371747 | 2.69 |
| state_toMap | 109409 | 9.14 |
| route_context_toMap | 3125000 | 0.32 |
| route_context_fromMap | 2631578 | 0.38 |
| route_context_roundtrip | 1515151 | 0.66 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 25960 | 38.52 |
| http_config_ssl_toMap | 757575 | 1.32 |
| http_config_ssl_fromMap | 3125000 | 0.32 |
| http_config_ssl_roundtrip | 613496 | 1.63 |
| battery_budget_heavy_drain | 392137 | 2.55 |
| smart_motion_speed_change | 15234123 | 0.07 |
| battery_budget_single_sample | 19970142 | 0.05 |
| smart_motion_accel_change | 15316635 | 0.07 |
| battery_budget_60_samples | 783023 | 1.28 |


### 2026-07-22 — Commit 39455735

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 86880 | 11.51 |
| schedule_isWithin_5_entries | 81433 | 12.28 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 460829 | 2.17 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 92336 | 10.83 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 348432 | 2.87 |
| config_toMap | 102354 | 9.77 |
| config_roundtrip | 78492 | 12.74 |
| state_fromMap | 335570 | 2.98 |
| state_toMap | 98619 | 10.14 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22431 | 44.58 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_heavy_drain | 665705 | 1.50 |
| battery_budget_single_sample | 23672451 | 0.04 |
| smart_motion_accel_change | 23498509 | 0.04 |
| smart_motion_speed_change | 23157025 | 0.04 |
| battery_budget_60_samples | 1291766 | 0.77 |


### 2026-07-22 — Commit 8f74eac0

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 89365 | 11.19 |
| schedule_isWithin_5_entries | 81632 | 12.25 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 641025 | 1.56 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 92592 | 10.80 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 341296 | 2.93 |
| config_toMap | 102040 | 9.80 |
| config_roundtrip | 78616 | 12.72 |
| state_fromMap | 322580 | 3.10 |
| state_toMap | 97943 | 10.21 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21829 | 45.81 |
| http_config_ssl_toMap | 684931 | 1.46 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_60_samples | 1264582 | 0.79 |
| smart_motion_speed_change | 23394936 | 0.04 |
| battery_budget_single_sample | 23487143 | 0.04 |
| battery_budget_heavy_drain | 664010 | 1.51 |
| smart_motion_accel_change | 23510191 | 0.04 |


### 2026-07-22 — Commit b514db35

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88339 | 11.32 |
| schedule_isWithin_5_entries | 81300 | 12.30 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 93896 | 10.65 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 344827 | 2.90 |
| config_toMap | 102880 | 9.72 |
| config_roundtrip | 78740 | 12.70 |
| state_fromMap | 333333 | 3.00 |
| state_toMap | 99108 | 10.09 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22256 | 44.93 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| battery_budget_60_samples | 1293013 | 0.77 |
| battery_budget_single_sample | 23622028 | 0.04 |
| smart_motion_speed_change | 23476514 | 0.04 |
| smart_motion_accel_change | 23565931 | 0.04 |
| battery_budget_heavy_drain | 666871 | 1.50 |


### 2026-07-22 — Commit ae2c9660

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2941176 | 0.34 |
| schedule_matches | 165016 | 6.06 |
| schedule_isWithin_5_entries | 136425 | 7.33 |
| location_fromMap | 1818181 | 0.55 |
| location_toMap | 699300 | 1.43 |
| location_fromMap_toMap_roundtrip | 518134 | 1.93 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 5000000 | 0.20 |
| geofence_fromMap_polygon | 1754385 | 0.57 |
| carbon_trip_100_locations | 141043 | 7.09 |
| carbon_onLocation | 4761904 | 0.21 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2857142 | 0.35 |
| persist_decider_location | 16666666 | 0.06 |
| persist_decider_geofence | 16666666 | 0.06 |
| config_fromMap | 409836 | 2.44 |
| config_toMap | 113507 | 8.81 |
| config_roundtrip | 88417 | 11.31 |
| state_fromMap | 392156 | 2.55 |
| state_toMap | 111358 | 8.98 |
| route_context_toMap | 3125000 | 0.32 |
| route_context_fromMap | 2702702 | 0.37 |
| route_context_roundtrip | 1562500 | 0.64 |
| sync_body_context_toMap_50 | 7692307 | 0.13 |
| sync_body_context_fromMap_50 | 25947 | 38.54 |
| http_config_ssl_toMap | 769230 | 1.30 |
| http_config_ssl_fromMap | 2941176 | 0.34 |
| http_config_ssl_roundtrip | 628930 | 1.59 |
| battery_budget_single_sample | 20283997 | 0.05 |
| battery_budget_60_samples | 803782 | 1.24 |
| smart_motion_accel_change | 15675972 | 0.06 |
| battery_budget_heavy_drain | 406193 | 2.46 |
| smart_motion_speed_change | 15679525 | 0.06 |


### 2026-07-22 — Commit bc214d59

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 89928 | 11.12 |
| schedule_isWithin_5_entries | 81234 | 12.31 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 628930 | 1.59 |
| location_fromMap_toMap_roundtrip | 456621 | 2.19 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 92936 | 10.76 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 349650 | 2.86 |
| config_toMap | 102249 | 9.78 |
| config_roundtrip | 79302 | 12.61 |
| state_fromMap | 333333 | 3.00 |
| state_toMap | 98039 | 10.20 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 21834 | 45.80 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2702702 | 0.37 |
| http_config_ssl_roundtrip | 546448 | 1.83 |
| battery_budget_60_samples | 1289266 | 0.78 |
| smart_motion_accel_change | 23537096 | 0.04 |
| smart_motion_speed_change | 23357607 | 0.04 |
| battery_budget_single_sample | 23746817 | 0.04 |
| battery_budget_heavy_drain | 665842 | 1.50 |


### 2026-07-22 — Commit 57f76ab1

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 89285 | 11.20 |
| schedule_isWithin_5_entries | 81833 | 12.22 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 632911 | 1.58 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1515151 | 0.66 |
| carbon_trip_100_locations | 93720 | 10.67 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 350877 | 2.85 |
| config_toMap | 101317 | 9.87 |
| config_roundtrip | 78864 | 12.68 |
| state_fromMap | 338983 | 2.95 |
| state_toMap | 99601 | 10.04 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22031 | 45.39 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_heavy_drain | 666165 | 1.50 |
| battery_budget_single_sample | 23768076 | 0.04 |
| battery_budget_60_samples | 1293303 | 0.77 |
| smart_motion_speed_change | 23368010 | 0.04 |
| smart_motion_accel_change | 23557473 | 0.04 |


### 2026-07-22 — Commit 5a64e0e7

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 88339 | 11.32 |
| schedule_isWithin_5_entries | 80256 | 12.46 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 462962 | 2.16 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 93109 | 10.74 |
| carbon_onLocation | 3846153 | 0.26 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 343642 | 2.91 |
| config_toMap | 102774 | 9.73 |
| config_roundtrip | 79554 | 12.57 |
| state_fromMap | 326797 | 3.06 |
| state_toMap | 98716 | 10.13 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21815 | 45.84 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2500000 | 0.40 |
| http_config_ssl_roundtrip | 540540 | 1.85 |
| smart_motion_accel_change | 23537056 | 0.04 |
| battery_budget_heavy_drain | 663982 | 1.51 |
| battery_budget_single_sample | 23706635 | 0.04 |
| smart_motion_speed_change | 23270826 | 0.04 |
| battery_budget_60_samples | 1290139 | 0.78 |


### 2026-07-21 — Commit eb84d2fc

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 82644 | 12.10 |
| schedule_isWithin_5_entries | 76045 | 13.15 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 456621 | 2.19 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4166666 | 0.24 |
| geofence_fromMap_polygon | 1515151 | 0.66 |
| carbon_trip_100_locations | 88652 | 11.28 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 340136 | 2.94 |
| config_toMap | 103626 | 9.65 |
| config_roundtrip | 78988 | 12.66 |
| state_fromMap | 336700 | 2.97 |
| state_toMap | 100704 | 9.93 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21381 | 46.77 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| battery_budget_single_sample | 21919025 | 0.05 |
| smart_motion_speed_change | 21645002 | 0.05 |
| smart_motion_accel_change | 22170219 | 0.05 |
| battery_budget_60_samples | 1287519 | 0.78 |
| battery_budget_heavy_drain | 661648 | 1.51 |


