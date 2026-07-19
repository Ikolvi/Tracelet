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

### 2026-07-19 — Commit e992cfd9

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81833 | 12.22 |
| schedule_isWithin_5_entries | 75187 | 13.30 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 454545 | 2.20 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 89206 | 11.21 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 346020 | 2.89 |
| config_toMap | 102774 | 9.73 |
| config_roundtrip | 77942 | 12.83 |
| state_fromMap | 325732 | 3.07 |
| state_toMap | 99108 | 10.09 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1298701 | 0.77 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21772 | 45.93 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 552486 | 1.81 |
| battery_budget_single_sample | 22035044 | 0.05 |
| battery_budget_heavy_drain | 657440 | 1.52 |
| smart_motion_accel_change | 22202000 | 0.05 |
| battery_budget_60_samples | 1288451 | 0.78 |
| smart_motion_speed_change | 21879210 | 0.05 |


### 2026-07-19 — Commit 1441afdc

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 87873 | 11.38 |
| schedule_isWithin_5_entries | 80321 | 12.45 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 458715 | 2.18 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 94073 | 10.63 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 340136 | 2.94 |
| config_toMap | 101626 | 9.84 |
| config_roundtrip | 77459 | 12.91 |
| state_fromMap | 324675 | 3.08 |
| state_toMap | 98328 | 10.17 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21877 | 45.71 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 552486 | 1.81 |
| battery_budget_single_sample | 23762586 | 0.04 |
| smart_motion_speed_change | 23034406 | 0.04 |
| battery_budget_60_samples | 1291910 | 0.77 |
| smart_motion_accel_change | 23539282 | 0.04 |
| battery_budget_heavy_drain | 665476 | 1.50 |


### 2026-07-18 — Commit a38a2bdd

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 81566 | 12.26 |
| schedule_isWithin_5_entries | 74349 | 13.45 |
| location_fromMap | 1562500 | 0.64 |
| location_toMap | 625000 | 1.60 |
| location_fromMap_toMap_roundtrip | 454545 | 2.20 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 90661 | 11.03 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 343642 | 2.91 |
| config_toMap | 102145 | 9.79 |
| config_roundtrip | 79176 | 12.63 |
| state_fromMap | 333333 | 3.00 |
| state_toMap | 98619 | 10.14 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1315789 | 0.76 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21630 | 46.23 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| smart_motion_speed_change | 22005646 | 0.05 |
| battery_budget_single_sample | 22011524 | 0.05 |
| smart_motion_accel_change | 22185277 | 0.05 |
| battery_budget_heavy_drain | 663469 | 1.51 |
| battery_budget_60_samples | 1282564 | 0.78 |


### 2026-07-18 — Commit 82c93b65

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3333333 | 0.30 |
| schedule_matches | 195312 | 5.12 |
| schedule_isWithin_5_entries | 153139 | 6.53 |
| location_fromMap | 2127659 | 0.47 |
| location_toMap | 763358 | 1.31 |
| location_fromMap_toMap_roundtrip | 584795 | 1.71 |
| location_copyWithCoords | 14285714 | 0.07 |
| geofence_fromMap_circular | 6250000 | 0.16 |
| geofence_fromMap_polygon | 2222222 | 0.45 |
| carbon_trip_100_locations | 158982 | 6.29 |
| carbon_onLocation | 5555555 | 0.18 |
| carbon_setActivity | 12500000 | 0.08 |
| carbon_cumulative_report | 3225806 | 0.31 |
| persist_decider_location | 25000000 | 0.04 |
| persist_decider_geofence | 25000000 | 0.04 |
| config_fromMap | 483091 | 2.07 |
| config_toMap | 127226 | 7.86 |
| config_roundtrip | 100401 | 9.96 |
| state_fromMap | 471698 | 2.12 |
| state_toMap | 124843 | 8.01 |
| route_context_toMap | 3703703 | 0.27 |
| route_context_fromMap | 3125000 | 0.32 |
| route_context_roundtrip | 1754385 | 0.57 |
| sync_body_context_toMap_50 | 8333333 | 0.12 |
| sync_body_context_fromMap_50 | 29103 | 34.36 |
| http_config_ssl_toMap | 847457 | 1.18 |
| http_config_ssl_fromMap | 3448275 | 0.29 |
| http_config_ssl_roundtrip | 699300 | 1.43 |
| battery_budget_single_sample | 23252974 | 0.04 |
| battery_budget_heavy_drain | 458678 | 2.18 |
| smart_motion_speed_change | 17302854 | 0.06 |
| battery_budget_60_samples | 902087 | 1.11 |
| smart_motion_accel_change | 17980269 | 0.06 |


### 2026-07-18 — Commit d57eeb84

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 87873 | 11.38 |
| schedule_isWithin_5_entries | 79491 | 12.58 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 93109 | 10.74 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 348432 | 2.87 |
| config_toMap | 104384 | 9.58 |
| config_roundtrip | 80645 | 12.40 |
| state_fromMap | 336700 | 2.97 |
| state_toMap | 102145 | 9.79 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22665 | 44.12 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| smart_motion_speed_change | 23476091 | 0.04 |
| battery_budget_heavy_drain | 665796 | 1.50 |
| battery_budget_60_samples | 1293552 | 0.77 |
| battery_budget_single_sample | 23605848 | 0.04 |
| smart_motion_accel_change | 23584490 | 0.04 |


### 2026-07-17 — Commit 663e700a

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 80840 | 12.37 |
| schedule_isWithin_5_entries | 75187 | 13.30 |
| location_fromMap | 1538461 | 0.65 |
| location_toMap | 641025 | 1.56 |
| location_fromMap_toMap_roundtrip | 467289 | 2.14 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 90661 | 11.03 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 349650 | 2.86 |
| config_toMap | 103519 | 9.66 |
| config_roundtrip | 78926 | 12.67 |
| state_fromMap | 335570 | 2.98 |
| state_toMap | 100100 | 9.99 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1315789 | 0.76 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21427 | 46.67 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| smart_motion_speed_change | 21996802 | 0.05 |
| battery_budget_heavy_drain | 655030 | 1.53 |
| battery_budget_60_samples | 1256333 | 0.80 |
| smart_motion_accel_change | 22132497 | 0.05 |
| battery_budget_single_sample | 21944817 | 0.05 |


### 2026-07-17 — Commit 00d8bdd6

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3225806 | 0.31 |
| schedule_matches | 163398 | 6.12 |
| schedule_isWithin_5_entries | 137741 | 7.26 |
| location_fromMap | 1818181 | 0.55 |
| location_toMap | 694444 | 1.44 |
| location_fromMap_toMap_roundtrip | 505050 | 1.98 |
| location_copyWithCoords | 12500000 | 0.08 |
| geofence_fromMap_circular | 5555555 | 0.18 |
| geofence_fromMap_polygon | 1886792 | 0.53 |
| carbon_trip_100_locations | 138121 | 7.24 |
| carbon_onLocation | 5000000 | 0.20 |
| carbon_setActivity | 11111111 | 0.09 |
| carbon_cumulative_report | 2857142 | 0.35 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 389105 | 2.57 |
| config_toMap | 113378 | 8.82 |
| config_roundtrip | 85251 | 11.73 |
| state_fromMap | 373134 | 2.68 |
| state_toMap | 108225 | 9.24 |
| route_context_toMap | 3125000 | 0.32 |
| route_context_fromMap | 2631578 | 0.38 |
| route_context_roundtrip | 1515151 | 0.66 |
| sync_body_context_toMap_50 | 7692307 | 0.13 |
| sync_body_context_fromMap_50 | 25400 | 39.37 |
| http_config_ssl_toMap | 763358 | 1.31 |
| http_config_ssl_fromMap | 3030303 | 0.33 |
| http_config_ssl_roundtrip | 613496 | 1.63 |
| battery_budget_single_sample | 19738458 | 0.05 |
| smart_motion_speed_change | 15288504 | 0.07 |
| smart_motion_accel_change | 15370200 | 0.07 |
| battery_budget_heavy_drain | 386438 | 2.59 |
| battery_budget_60_samples | 757269 | 1.32 |


### 2026-07-17 — Commit c0299042

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 92421 | 10.82 |
| schedule_isWithin_5_entries | 83752 | 11.94 |
| location_fromMap | 1694915 | 0.59 |
| location_toMap | 641025 | 1.56 |
| location_fromMap_toMap_roundtrip | 473933 | 2.11 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 92250 | 10.84 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 357142 | 2.80 |
| config_toMap | 104493 | 9.57 |
| config_roundtrip | 81632 | 12.25 |
| state_fromMap | 347222 | 2.88 |
| state_toMap | 100603 | 9.94 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 21997 | 45.46 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_single_sample | 23781898 | 0.04 |
| battery_budget_heavy_drain | 656259 | 1.52 |
| battery_budget_60_samples | 1269536 | 0.79 |
| smart_motion_speed_change | 23341395 | 0.04 |
| smart_motion_accel_change | 23542168 | 0.04 |


### 2026-07-16 — Commit 7251d5d6

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88888 | 11.25 |
| schedule_isWithin_5_entries | 81833 | 12.22 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 91996 | 10.87 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 346020 | 2.89 |
| config_toMap | 102145 | 9.79 |
| config_roundtrip | 77881 | 12.84 |
| state_fromMap | 331125 | 3.02 |
| state_toMap | 99304 | 10.07 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22346 | 44.75 |
| http_config_ssl_toMap | 684931 | 1.46 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_single_sample | 23580756 | 0.04 |
| smart_motion_speed_change | 23360328 | 0.04 |
| battery_budget_60_samples | 1288310 | 0.78 |
| battery_budget_heavy_drain | 662706 | 1.51 |
| smart_motion_accel_change | 23516115 | 0.04 |


### 2026-07-16 — Commit 976a5a61

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 81566 | 12.26 |
| schedule_isWithin_5_entries | 75471 | 13.25 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 465116 | 2.15 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 91491 | 10.93 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 344827 | 2.90 |
| config_toMap | 103412 | 9.67 |
| config_roundtrip | 79491 | 12.58 |
| state_fromMap | 336700 | 2.97 |
| state_toMap | 100603 | 9.94 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21673 | 46.14 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 568181 | 1.76 |
| smart_motion_speed_change | 22025228 | 0.05 |
| battery_budget_60_samples | 1288556 | 0.78 |
| battery_budget_single_sample | 21988724 | 0.05 |
| smart_motion_accel_change | 22046190 | 0.05 |
| battery_budget_heavy_drain | 663259 | 1.51 |


### 2026-07-16 — Commit 173874d5

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 4000000 | 0.25 |
| schedule_matches | 244498 | 4.09 |
| schedule_isWithin_5_entries | 194931 | 5.13 |
| location_fromMap | 2564102 | 0.39 |
| location_toMap | 909090 | 1.10 |
| location_fromMap_toMap_roundtrip | 675675 | 1.48 |
| location_copyWithCoords | 12500000 | 0.08 |
| geofence_fromMap_circular | 5882352 | 0.17 |
| geofence_fromMap_polygon | 2325581 | 0.43 |
| carbon_trip_100_locations | 184842 | 5.41 |
| carbon_onLocation | 5555555 | 0.18 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 3703703 | 0.27 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 581395 | 1.72 |
| config_toMap | 137362 | 7.28 |
| config_roundtrip | 112485 | 8.89 |
| state_fromMap | 526315 | 1.90 |
| state_toMap | 146412 | 6.83 |
| route_context_toMap | 4000000 | 0.25 |
| route_context_fromMap | 3448275 | 0.29 |
| route_context_roundtrip | 2000000 | 0.50 |
| sync_body_context_toMap_50 | 9090909 | 0.11 |
| sync_body_context_fromMap_50 | 32701 | 30.58 |
| http_config_ssl_toMap | 847457 | 1.18 |
| http_config_ssl_fromMap | 4000000 | 0.25 |
| http_config_ssl_roundtrip | 793650 | 1.26 |
| smart_motion_accel_change | 22254349 | 0.04 |
| smart_motion_speed_change | 22204013 | 0.05 |
| battery_budget_single_sample | 27222391 | 0.04 |
| battery_budget_60_samples | 1182784 | 0.85 |
| battery_budget_heavy_drain | 586008 | 1.71 |


### 2026-07-16 — Commit 2ba6b82e

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 90009 | 11.11 |
| schedule_isWithin_5_entries | 82169 | 12.17 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 462962 | 2.16 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 92506 | 10.81 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 343642 | 2.91 |
| config_toMap | 102249 | 9.78 |
| config_roundtrip | 78431 | 12.75 |
| state_fromMap | 334448 | 2.99 |
| state_toMap | 98425 | 10.16 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22182 | 45.08 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2500000 | 0.40 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| smart_motion_speed_change | 23404195 | 0.04 |
| battery_budget_single_sample | 23732915 | 0.04 |
| battery_budget_heavy_drain | 666545 | 1.50 |
| smart_motion_accel_change | 23523570 | 0.04 |
| battery_budget_60_samples | 1291982 | 0.77 |


### 2026-07-16 — Commit fb0868f8

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2631578 | 0.38 |
| schedule_matches | 89928 | 11.12 |
| schedule_isWithin_5_entries | 81967 | 12.20 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 476190 | 2.10 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 93196 | 10.73 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 8333333 | 0.12 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 350877 | 2.85 |
| config_toMap | 103950 | 9.62 |
| config_roundtrip | 79681 | 12.55 |
| state_fromMap | 340136 | 2.94 |
| state_toMap | 99700 | 10.03 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6250000 | 0.16 |
| sync_body_context_fromMap_50 | 22552 | 44.34 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2500000 | 0.40 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| smart_motion_accel_change | 23301875 | 0.04 |
| battery_budget_single_sample | 23617603 | 0.04 |
| battery_budget_60_samples | 1290018 | 0.78 |
| smart_motion_speed_change | 23304724 | 0.04 |
| battery_budget_heavy_drain | 667609 | 1.50 |


### 2026-07-16 — Commit 77ad6734

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 90171 | 11.09 |
| schedule_isWithin_5_entries | 83194 | 12.02 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 478468 | 2.09 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 94250 | 10.61 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 359712 | 2.78 |
| config_toMap | 104821 | 9.54 |
| config_roundtrip | 79365 | 12.60 |
| state_fromMap | 344827 | 2.90 |
| state_toMap | 99900 | 10.01 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22436 | 44.57 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_60_samples | 1292719 | 0.77 |
| smart_motion_accel_change | 23282568 | 0.04 |
| battery_budget_single_sample | 23770025 | 0.04 |
| smart_motion_speed_change | 23335669 | 0.04 |
| battery_budget_heavy_drain | 668154 | 1.50 |


### 2026-07-16 — Commit fdba03c6

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3571428 | 0.28 |
| schedule_matches | 227272 | 4.40 |
| schedule_isWithin_5_entries | 200803 | 4.98 |
| location_fromMap | 2631578 | 0.38 |
| location_toMap | 961538 | 1.04 |
| location_fromMap_toMap_roundtrip | 709219 | 1.41 |
| location_copyWithCoords | 16666666 | 0.06 |
| geofence_fromMap_circular | 7692307 | 0.13 |
| geofence_fromMap_polygon | 2380952 | 0.42 |
| carbon_trip_100_locations | 161550 | 6.19 |
| carbon_onLocation | 6250000 | 0.16 |
| carbon_setActivity | 14285714 | 0.07 |
| carbon_cumulative_report | 4000000 | 0.25 |
| persist_decider_location | 25000000 | 0.04 |
| persist_decider_geofence | 25000000 | 0.04 |
| config_fromMap | 588235 | 1.70 |
| config_toMap | 154320 | 6.48 |
| config_roundtrip | 119047 | 8.40 |
| state_fromMap | 571428 | 1.75 |
| state_toMap | 149253 | 6.70 |
| route_context_toMap | 4347826 | 0.23 |
| route_context_fromMap | 3571428 | 0.28 |
| route_context_roundtrip | 2083333 | 0.48 |
| sync_body_context_toMap_50 | 9090909 | 0.11 |
| sync_body_context_fromMap_50 | 32605 | 30.67 |
| http_config_ssl_toMap | 1041666 | 0.96 |
| http_config_ssl_fromMap | 4000000 | 0.25 |
| http_config_ssl_roundtrip | 819672 | 1.22 |
| battery_budget_single_sample | 28218996 | 0.04 |
| smart_motion_accel_change | 22268506 | 0.04 |
| battery_budget_60_samples | 1184578 | 0.84 |
| smart_motion_speed_change | 22288045 | 0.04 |
| battery_budget_heavy_drain | 599847 | 1.67 |


### 2026-07-16 — Commit e7b3045a

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3571428 | 0.28 |
| schedule_matches | 107411 | 9.31 |
| schedule_isWithin_5_entries | 98619 | 10.14 |
| location_fromMap | 2083333 | 0.48 |
| location_toMap | 813008 | 1.23 |
| location_fromMap_toMap_roundtrip | 606060 | 1.65 |
| location_copyWithCoords | 14285714 | 0.07 |
| geofence_fromMap_circular | 5882352 | 0.17 |
| geofence_fromMap_polygon | 2000000 | 0.50 |
| carbon_trip_100_locations | 116822 | 8.56 |
| carbon_onLocation | 5263157 | 0.19 |
| carbon_setActivity | 11111111 | 0.09 |
| carbon_cumulative_report | 3225806 | 0.31 |
| persist_decider_location | 25000000 | 0.04 |
| persist_decider_geofence | 25000000 | 0.04 |
| config_fromMap | 450450 | 2.22 |
| config_toMap | 132978 | 7.52 |
| config_roundtrip | 102354 | 9.77 |
| state_fromMap | 432900 | 2.31 |
| state_toMap | 129533 | 7.72 |
| route_context_toMap | 3846153 | 0.26 |
| route_context_fromMap | 2777777 | 0.36 |
| route_context_roundtrip | 1724137 | 0.58 |
| sync_body_context_toMap_50 | 8333333 | 0.12 |
| sync_body_context_fromMap_50 | 27932 | 35.80 |
| http_config_ssl_toMap | 909090 | 1.10 |
| http_config_ssl_fromMap | 3333333 | 0.30 |
| http_config_ssl_roundtrip | 729927 | 1.37 |
| smart_motion_accel_change | 28514842 | 0.04 |
| battery_budget_60_samples | 1660067 | 0.60 |
| battery_budget_single_sample | 28400854 | 0.04 |
| battery_budget_heavy_drain | 847395 | 1.18 |
| smart_motion_speed_change | 28309146 | 0.04 |


### 2026-07-16 — Commit b42c25b3

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 82372 | 12.14 |
| schedule_isWithin_5_entries | 75357 | 13.27 |
| location_fromMap | 1587301 | 0.63 |
| location_toMap | 628930 | 1.59 |
| location_fromMap_toMap_roundtrip | 452488 | 2.21 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 91074 | 10.98 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 348432 | 2.87 |
| config_toMap | 101419 | 9.86 |
| config_roundtrip | 78186 | 12.79 |
| state_fromMap | 332225 | 3.01 |
| state_toMap | 98911 | 10.11 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1315789 | 0.76 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21829 | 45.81 |
| http_config_ssl_toMap | 714285 | 1.40 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| battery_budget_single_sample | 21959480 | 0.05 |
| battery_budget_60_samples | 1288573 | 0.78 |
| smart_motion_accel_change | 22139817 | 0.05 |
| battery_budget_heavy_drain | 663472 | 1.51 |
| smart_motion_speed_change | 21951369 | 0.05 |


### 2026-07-15 — Commit 995ab5fa

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 91074 | 10.98 |
| schedule_isWithin_5_entries | 81103 | 12.33 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 641025 | 1.56 |
| location_fromMap_toMap_roundtrip | 471698 | 2.12 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 91827 | 10.89 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 355871 | 2.81 |
| config_toMap | 103519 | 9.66 |
| config_roundtrip | 79428 | 12.59 |
| state_fromMap | 343642 | 2.91 |
| state_toMap | 98328 | 10.17 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21920 | 45.62 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_single_sample | 23563028 | 0.04 |
| smart_motion_speed_change | 22506363 | 0.04 |
| battery_budget_60_samples | 1287446 | 0.78 |
| battery_budget_heavy_drain | 665252 | 1.50 |
| smart_motion_accel_change | 23486956 | 0.04 |


### 2026-07-13 — Commit daccf1cd

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 84104 | 11.89 |
| schedule_isWithin_5_entries | 76569 | 13.06 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 454545 | 2.20 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 91157 | 10.97 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 344827 | 2.90 |
| config_toMap | 101112 | 9.89 |
| config_roundtrip | 78740 | 12.70 |
| state_fromMap | 336700 | 2.97 |
| state_toMap | 98716 | 10.13 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21668 | 46.15 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2439024 | 0.41 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_60_samples | 1287961 | 0.78 |
| smart_motion_speed_change | 21879181 | 0.05 |
| battery_budget_single_sample | 21973120 | 0.05 |
| battery_budget_heavy_drain | 658698 | 1.52 |
| smart_motion_accel_change | 22099690 | 0.05 |


### 2026-07-12 — Commit 632a90df

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88888 | 11.25 |
| schedule_isWithin_5_entries | 80840 | 12.37 |
| location_fromMap | 1694915 | 0.59 |
| location_toMap | 662251 | 1.51 |
| location_fromMap_toMap_roundtrip | 473933 | 2.11 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 93196 | 10.73 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 346020 | 2.89 |
| config_toMap | 105042 | 9.52 |
| config_roundtrip | 81103 | 12.33 |
| state_fromMap | 333333 | 3.00 |
| state_toMap | 99304 | 10.07 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22109 | 45.23 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2702702 | 0.37 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| smart_motion_accel_change | 23278438 | 0.04 |
| battery_budget_60_samples | 1292755 | 0.77 |
| smart_motion_speed_change | 23306579 | 0.04 |
| battery_budget_heavy_drain | 665833 | 1.50 |
| battery_budget_single_sample | 23550648 | 0.04 |


### 2026-07-12 — Commit 516ff01a

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 88495 | 11.30 |
| schedule_isWithin_5_entries | 80645 | 12.40 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 471698 | 2.12 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 91491 | 10.93 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 330033 | 3.03 |
| config_toMap | 102145 | 9.79 |
| config_roundtrip | 77639 | 12.88 |
| state_fromMap | 320512 | 3.12 |
| state_toMap | 98328 | 10.17 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22371 | 44.70 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| smart_motion_speed_change | 23295806 | 0.04 |
| battery_budget_single_sample | 23737150 | 0.04 |
| battery_budget_60_samples | 1291294 | 0.77 |
| smart_motion_accel_change | 23252571 | 0.04 |
| battery_budget_heavy_drain | 667349 | 1.50 |


### 2026-07-12 — Commit 744e50a3

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 87719 | 11.40 |
| schedule_isWithin_5_entries | 81300 | 12.30 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 657894 | 1.52 |
| location_fromMap_toMap_roundtrip | 469483 | 2.13 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 94250 | 10.61 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 332225 | 3.01 |
| config_toMap | 105042 | 9.52 |
| config_roundtrip | 78802 | 12.69 |
| state_fromMap | 325732 | 3.07 |
| state_toMap | 101522 | 9.85 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 21949 | 45.56 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| smart_motion_accel_change | 23115350 | 0.04 |
| battery_budget_60_samples | 1293118 | 0.77 |
| battery_budget_heavy_drain | 667823 | 1.50 |
| smart_motion_speed_change | 23119020 | 0.04 |
| battery_budget_single_sample | 23714134 | 0.04 |


### 2026-07-12 — Commit 69a96ab8

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2631578 | 0.38 |
| schedule_matches | 87642 | 11.41 |
| schedule_isWithin_5_entries | 81632 | 12.25 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 467289 | 2.14 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 93808 | 10.66 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 341296 | 2.93 |
| config_toMap | 101522 | 9.85 |
| config_roundtrip | 79428 | 12.59 |
| state_fromMap | 332225 | 3.01 |
| state_toMap | 98716 | 10.13 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22182 | 45.08 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| smart_motion_accel_change | 23360045 | 0.04 |
| battery_budget_single_sample | 23763808 | 0.04 |
| smart_motion_speed_change | 23324056 | 0.04 |
| battery_budget_60_samples | 1287913 | 0.78 |
| battery_budget_heavy_drain | 667196 | 1.50 |


### 2026-07-12 — Commit 60287f1e

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 87796 | 11.39 |
| schedule_isWithin_5_entries | 81900 | 12.21 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 476190 | 2.10 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 94428 | 10.59 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 350877 | 2.85 |
| config_toMap | 103950 | 9.62 |
| config_roundtrip | 79617 | 12.56 |
| state_fromMap | 337837 | 2.96 |
| state_toMap | 99800 | 10.02 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22482 | 44.48 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 571428 | 1.75 |
| battery_budget_60_samples | 1293174 | 0.77 |
| smart_motion_speed_change | 23268186 | 0.04 |
| battery_budget_single_sample | 23592441 | 0.04 |
| smart_motion_accel_change | 23294161 | 0.04 |
| battery_budget_heavy_drain | 667298 | 1.50 |


### 2026-07-09 — Commit 3b91265a

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3448275 | 0.29 |
| schedule_matches | 176678 | 5.66 |
| schedule_isWithin_5_entries | 146412 | 6.83 |
| location_fromMap | 2000000 | 0.50 |
| location_toMap | 719424 | 1.39 |
| location_fromMap_toMap_roundtrip | 529100 | 1.89 |
| location_copyWithCoords | 12500000 | 0.08 |
| geofence_fromMap_circular | 5555555 | 0.18 |
| geofence_fromMap_polygon | 1818181 | 0.55 |
| carbon_trip_100_locations | 144508 | 6.92 |
| carbon_onLocation | 5263157 | 0.19 |
| carbon_setActivity | 11111111 | 0.09 |
| carbon_cumulative_report | 3030303 | 0.33 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 398406 | 2.51 |
| config_toMap | 115740 | 8.64 |
| config_roundtrip | 86805 | 11.52 |
| state_fromMap | 377358 | 2.65 |
| state_toMap | 111856 | 8.94 |
| route_context_toMap | 3333333 | 0.30 |
| route_context_fromMap | 2857142 | 0.35 |
| route_context_roundtrip | 1612903 | 0.62 |
| sync_body_context_toMap_50 | 7692307 | 0.13 |
| sync_body_context_fromMap_50 | 27412 | 36.48 |
| http_config_ssl_toMap | 819672 | 1.22 |
| http_config_ssl_fromMap | 3225806 | 0.31 |
| http_config_ssl_roundtrip | 649350 | 1.54 |
| battery_budget_single_sample | 22136473 | 0.05 |
| battery_budget_60_samples | 838301 | 1.19 |
| smart_motion_speed_change | 16778495 | 0.06 |
| smart_motion_accel_change | 16640832 | 0.06 |
| battery_budget_heavy_drain | 420823 | 2.38 |


### 2026-07-09 — Commit 051c87a9

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3030303 | 0.33 |
| schedule_matches | 141442 | 7.07 |
| schedule_isWithin_5_entries | 122100 | 8.19 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 473933 | 2.11 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 104712 | 9.55 |
| carbon_onLocation | 4347826 | 0.23 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2702702 | 0.37 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 330033 | 3.03 |
| config_toMap | 107526 | 9.30 |
| config_roundtrip | 82101 | 12.18 |
| state_fromMap | 317460 | 3.15 |
| state_toMap | 100603 | 9.94 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 21687 | 46.11 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2500000 | 0.40 |
| http_config_ssl_roundtrip | 549450 | 1.82 |
| battery_budget_heavy_drain | 432502 | 2.31 |
| battery_budget_60_samples | 855044 | 1.17 |
| smart_motion_accel_change | 17504225 | 0.06 |
| smart_motion_speed_change | 17370717 | 0.06 |
| battery_budget_single_sample | 22880755 | 0.04 |


### 2026-07-09 — Commit c7db1665

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 88809 | 11.26 |
| schedule_isWithin_5_entries | 80645 | 12.40 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 471698 | 2.12 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 93196 | 10.73 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 349650 | 2.86 |
| config_toMap | 102669 | 9.74 |
| config_roundtrip | 78308 | 12.77 |
| state_fromMap | 334448 | 2.99 |
| state_toMap | 99009 | 10.10 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1428571 | 0.70 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22089 | 45.27 |
| http_config_ssl_toMap | 689655 | 1.45 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_single_sample | 23596394 | 0.04 |
| smart_motion_accel_change | 23300158 | 0.04 |
| battery_budget_heavy_drain | 665246 | 1.50 |
| battery_budget_60_samples | 1292886 | 0.77 |
| smart_motion_speed_change | 23301957 | 0.04 |


### 2026-07-09 — Commit 9b084bb3

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 88809 | 11.26 |
| schedule_isWithin_5_entries | 81699 | 12.24 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 471698 | 2.12 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 90415 | 11.06 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 333333 | 3.00 |
| config_toMap | 102564 | 9.75 |
| config_roundtrip | 79176 | 12.63 |
| state_fromMap | 325732 | 3.07 |
| state_toMap | 98814 | 10.12 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 21978 | 45.50 |
| http_config_ssl_toMap | 684931 | 1.46 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 552486 | 1.81 |
| battery_budget_60_samples | 1302861 | 0.77 |
| smart_motion_accel_change | 23452510 | 0.04 |
| battery_budget_single_sample | 23549093 | 0.04 |
| battery_budget_heavy_drain | 677881 | 1.48 |
| smart_motion_speed_change | 23153985 | 0.04 |


### 2026-07-07 — Commit 88014114

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 89126 | 11.22 |
| schedule_isWithin_5_entries | 82576 | 12.11 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 625000 | 1.60 |
| location_fromMap_toMap_roundtrip | 469483 | 2.13 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 87032 | 11.49 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 341296 | 2.93 |
| config_toMap | 102564 | 9.75 |
| config_roundtrip | 78247 | 12.78 |
| state_fromMap | 334448 | 2.99 |
| state_toMap | 99403 | 10.06 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22296 | 44.85 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| smart_motion_accel_change | 23447280 | 0.04 |
| battery_budget_heavy_drain | 676554 | 1.48 |
| battery_budget_single_sample | 23576542 | 0.04 |
| smart_motion_speed_change | 23190839 | 0.04 |
| battery_budget_60_samples | 1294261 | 0.77 |


### 2026-07-07 — Commit 00de62fc

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 82508 | 12.12 |
| schedule_isWithin_5_entries | 76045 | 13.15 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 446428 | 2.24 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 89047 | 11.23 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 347222 | 2.88 |
| config_toMap | 103842 | 9.63 |
| config_roundtrip | 79365 | 12.60 |
| state_fromMap | 333333 | 3.00 |
| state_toMap | 100502 | 9.95 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1315789 | 0.76 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21519 | 46.47 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_heavy_drain | 660418 | 1.51 |
| battery_budget_single_sample | 21959759 | 0.05 |
| battery_budget_60_samples | 1284131 | 0.78 |
| smart_motion_accel_change | 22126160 | 0.05 |
| smart_motion_speed_change | 22007582 | 0.05 |


### 2026-07-07 — Commit a63ac289

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 90090 | 11.10 |
| schedule_isWithin_5_entries | 82508 | 12.12 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 476190 | 2.10 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 92165 | 10.85 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 358422 | 2.79 |
| config_toMap | 104821 | 9.54 |
| config_roundtrip | 80000 | 12.50 |
| state_fromMap | 349650 | 2.86 |
| state_toMap | 100200 | 9.98 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22716 | 44.02 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2702702 | 0.37 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| smart_motion_speed_change | 23386262 | 0.04 |
| smart_motion_accel_change | 23310076 | 0.04 |
| battery_budget_heavy_drain | 678018 | 1.47 |
| battery_budget_single_sample | 23605932 | 0.04 |
| battery_budget_60_samples | 1301855 | 0.77 |


### 2026-07-02 — Commit 66d9a28c

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2857142 | 0.35 |
| schedule_matches | 93984 | 10.64 |
| schedule_isWithin_5_entries | 84175 | 11.88 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 478468 | 2.09 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 92678 | 10.79 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 341296 | 2.93 |
| config_toMap | 104602 | 9.56 |
| config_roundtrip | 80385 | 12.44 |
| state_fromMap | 306748 | 3.26 |
| state_toMap | 101214 | 9.88 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22512 | 44.42 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 564971 | 1.77 |
| smart_motion_accel_change | 23167647 | 0.04 |
| battery_budget_single_sample | 23137236 | 0.04 |
| smart_motion_speed_change | 23372648 | 0.04 |
| battery_budget_60_samples | 1303188 | 0.77 |
| battery_budget_heavy_drain | 675648 | 1.48 |


### 2026-07-02 — Commit a51a81f4

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 90090 | 11.10 |
| schedule_isWithin_5_entries | 82987 | 12.05 |
| location_fromMap | 1098901 | 0.91 |
| location_toMap | 574712 | 1.74 |
| location_fromMap_toMap_roundtrip | 377358 | 2.65 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 3225806 | 0.31 |
| geofence_fromMap_polygon | 1470588 | 0.68 |
| carbon_trip_100_locations | 80321 | 12.45 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 315457 | 3.17 |
| config_toMap | 95785 | 10.44 |
| config_roundtrip | 73909 | 13.53 |
| state_fromMap | 331125 | 3.02 |
| state_toMap | 90991 | 10.99 |
| route_context_toMap | 2777777 | 0.36 |
| route_context_fromMap | 2040816 | 0.49 |
| route_context_roundtrip | 1123595 | 0.89 |
| sync_body_context_toMap_50 | 6250000 | 0.16 |
| sync_body_context_fromMap_50 | 21968 | 45.52 |
| http_config_ssl_toMap | 645161 | 1.55 |
| http_config_ssl_fromMap | 1851851 | 0.54 |
| http_config_ssl_roundtrip | 485436 | 2.06 |
| battery_budget_60_samples | 1298665 | 0.77 |
| battery_budget_heavy_drain | 677792 | 1.48 |
| smart_motion_accel_change | 23433002 | 0.04 |
| smart_motion_speed_change | 23026809 | 0.04 |
| battery_budget_single_sample | 23715052 | 0.04 |


### 2026-06-30 — Commit 7de4d95e

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 85106 | 11.75 |
| schedule_isWithin_5_entries | 77760 | 12.86 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 632911 | 1.58 |
| location_fromMap_toMap_roundtrip | 469483 | 2.13 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4166666 | 0.24 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 91659 | 10.91 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 347222 | 2.88 |
| config_toMap | 103734 | 9.64 |
| config_roundtrip | 79365 | 12.60 |
| state_fromMap | 330033 | 3.03 |
| state_toMap | 100100 | 9.99 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21696 | 46.09 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 564971 | 1.77 |
| battery_budget_60_samples | 1283790 | 0.78 |
| smart_motion_accel_change | 22135874 | 0.05 |
| smart_motion_speed_change | 21967055 | 0.05 |
| battery_budget_heavy_drain | 665635 | 1.50 |
| battery_budget_single_sample | 21811020 | 0.05 |


### 2026-06-30 — Commit 36e04290

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 92936 | 10.76 |
| schedule_isWithin_5_entries | 84245 | 11.87 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 636942 | 1.57 |
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
| config_toMap | 104058 | 9.61 |
| config_roundtrip | 80321 | 12.45 |
| state_fromMap | 337837 | 2.96 |
| state_toMap | 98911 | 10.11 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22436 | 44.57 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2702702 | 0.37 |
| http_config_ssl_roundtrip | 558659 | 1.79 |
| battery_budget_single_sample | 23740018 | 0.04 |
| smart_motion_speed_change | 23199862 | 0.04 |
| battery_budget_60_samples | 1299981 | 0.77 |
| smart_motion_accel_change | 23451049 | 0.04 |
| battery_budget_heavy_drain | 677757 | 1.48 |


### 2026-06-30 — Commit 9845e7ca

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 93457 | 10.70 |
| schedule_isWithin_5_entries | 84889 | 11.78 |
| location_fromMap | 1694915 | 0.59 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 476190 | 2.10 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 91659 | 10.91 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2631578 | 0.38 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 352112 | 2.84 |
| config_toMap | 103199 | 9.69 |
| config_roundtrip | 79872 | 12.52 |
| state_fromMap | 342465 | 2.92 |
| state_toMap | 99108 | 10.09 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22371 | 44.70 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 568181 | 1.76 |
| smart_motion_accel_change | 23447359 | 0.04 |
| battery_budget_single_sample | 23591801 | 0.04 |
| battery_budget_60_samples | 1302045 | 0.77 |
| battery_budget_heavy_drain | 678422 | 1.47 |
| smart_motion_speed_change | 23134390 | 0.04 |


### 2026-06-30 — Commit 1e96ec1f

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2857142 | 0.35 |
| schedule_matches | 97656 | 10.24 |
| schedule_isWithin_5_entries | 91743 | 10.90 |
| location_fromMap | 1754385 | 0.57 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 460829 | 2.17 |
| location_copyWithCoords | 12500000 | 0.08 |
| geofence_fromMap_circular | 4761904 | 0.21 |
| geofence_fromMap_polygon | 1639344 | 0.61 |
| carbon_trip_100_locations | 99304 | 10.07 |
| carbon_onLocation | 4347826 | 0.23 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2702702 | 0.37 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 375939 | 2.66 |
| config_toMap | 103199 | 9.69 |
| config_roundtrip | 80192 | 12.47 |
| state_fromMap | 353356 | 2.83 |
| state_toMap | 101214 | 9.88 |
| route_context_toMap | 3030303 | 0.33 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 23191 | 43.12 |
| http_config_ssl_toMap | 684931 | 1.46 |
| http_config_ssl_fromMap | 2777777 | 0.36 |
| http_config_ssl_roundtrip | 549450 | 1.82 |
| battery_budget_60_samples | 1338691 | 0.75 |
| smart_motion_speed_change | 24772472 | 0.04 |
| battery_budget_single_sample | 24644096 | 0.04 |
| battery_budget_heavy_drain | 693782 | 1.44 |
| smart_motion_accel_change | 24576368 | 0.04 |


### 2026-06-30 — Commit f4542e6c

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2857142 | 0.35 |
| schedule_matches | 152207 | 6.57 |
| schedule_isWithin_5_entries | 130039 | 7.69 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 625000 | 1.60 |
| location_fromMap_toMap_roundtrip | 469483 | 2.13 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4761904 | 0.21 |
| geofence_fromMap_polygon | 1785714 | 0.56 |
| carbon_trip_100_locations | 129198 | 7.74 |
| carbon_onLocation | 4761904 | 0.21 |
| carbon_setActivity | 10000000 | 0.10 |
| carbon_cumulative_report | 2857142 | 0.35 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 325732 | 3.07 |
| config_toMap | 102145 | 9.79 |
| config_roundtrip | 76745 | 13.03 |
| state_fromMap | 335570 | 2.98 |
| state_toMap | 100100 | 9.99 |
| route_context_toMap | 3125000 | 0.32 |
| route_context_fromMap | 2631578 | 0.38 |
| route_context_roundtrip | 1492537 | 0.67 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 23337 | 42.85 |
| http_config_ssl_toMap | 671140 | 1.49 |
| http_config_ssl_fromMap | 2500000 | 0.40 |
| http_config_ssl_roundtrip | 549450 | 1.82 |
| battery_budget_heavy_drain | 397361 | 2.52 |
| smart_motion_speed_change | 15459725 | 0.06 |
| battery_budget_60_samples | 786243 | 1.27 |
| smart_motion_accel_change | 15435529 | 0.06 |
| battery_budget_single_sample | 20131555 | 0.05 |


### 2026-06-30 — Commit 3da9454a

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 89445 | 11.18 |
| schedule_isWithin_5_entries | 84459 | 11.84 |
| location_fromMap | 1694915 | 0.59 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 473933 | 2.11 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 91996 | 10.87 |
| carbon_onLocation | 3703703 | 0.27 |
| carbon_setActivity | 8333333 | 0.12 |
| carbon_cumulative_report | 2439024 | 0.41 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 344827 | 2.90 |
| config_toMap | 101832 | 9.82 |
| config_roundtrip | 79239 | 12.62 |
| state_fromMap | 331125 | 3.02 |
| state_toMap | 100200 | 9.98 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22281 | 44.88 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2702702 | 0.37 |
| http_config_ssl_roundtrip | 564971 | 1.77 |
| smart_motion_accel_change | 23163912 | 0.04 |
| smart_motion_speed_change | 23451981 | 0.04 |
| battery_budget_single_sample | 23781640 | 0.04 |
| battery_budget_60_samples | 1306876 | 0.77 |
| battery_budget_heavy_drain | 674902 | 1.48 |


### 2026-06-23 — Commit c9748157

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 85543 | 11.69 |
| schedule_isWithin_5_entries | 77881 | 12.84 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 478468 | 2.09 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 91074 | 10.98 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 347222 | 2.88 |
| config_toMap | 104602 | 9.56 |
| config_roundtrip | 79491 | 12.58 |
| state_fromMap | 328947 | 3.04 |
| state_toMap | 100908 | 9.91 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21734 | 46.01 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 568181 | 1.76 |
| battery_budget_heavy_drain | 662338 | 1.51 |
| battery_budget_60_samples | 1281788 | 0.78 |
| battery_budget_single_sample | 22027941 | 0.05 |
| smart_motion_accel_change | 22088299 | 0.05 |
| smart_motion_speed_change | 21997760 | 0.05 |


### 2026-06-19 — Commit fc989ca0

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 94696 | 10.56 |
| schedule_isWithin_5_entries | 86281 | 11.59 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 460829 | 2.17 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4761904 | 0.21 |
| geofence_fromMap_polygon | 1538461 | 0.65 |
| carbon_trip_100_locations | 93109 | 10.74 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 352112 | 2.84 |
| config_toMap | 103519 | 9.66 |
| config_roundtrip | 80321 | 12.45 |
| state_fromMap | 344827 | 2.90 |
| state_toMap | 99304 | 10.07 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2325581 | 0.43 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22011 | 45.43 |
| http_config_ssl_toMap | 694444 | 1.44 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| smart_motion_speed_change | 23329519 | 0.04 |
| battery_budget_heavy_drain | 677213 | 1.48 |
| smart_motion_accel_change | 23486682 | 0.04 |
| battery_budget_60_samples | 1308460 | 0.76 |
| battery_budget_single_sample | 23762297 | 0.04 |


### 2026-06-19 — Commit 20c31b34

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 89847 | 11.13 |
| schedule_isWithin_5_entries | 84388 | 11.85 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 467289 | 2.14 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 91324 | 10.95 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 359712 | 2.78 |
| config_toMap | 102669 | 9.74 |
| config_roundtrip | 80192 | 12.47 |
| state_fromMap | 344827 | 2.90 |
| state_toMap | 101010 | 9.90 |
| route_context_toMap | 2857142 | 0.35 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1408450 | 0.71 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 22507 | 44.43 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| battery_budget_60_samples | 1296969 | 0.77 |
| battery_budget_heavy_drain | 675109 | 1.48 |
| battery_budget_single_sample | 23765936 | 0.04 |
| smart_motion_accel_change | 23477185 | 0.04 |
| smart_motion_speed_change | 23421792 | 0.04 |


### 2026-06-19 — Commit d2dec1aa

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 83402 | 11.99 |
| schedule_isWithin_5_entries | 77579 | 12.89 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 471698 | 2.12 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 89847 | 11.13 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 349650 | 2.86 |
| config_toMap | 103199 | 9.69 |
| config_roundtrip | 79176 | 12.63 |
| state_fromMap | 328947 | 3.04 |
| state_toMap | 100401 | 9.96 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21886 | 45.69 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2500000 | 0.40 |
| http_config_ssl_roundtrip | 552486 | 1.81 |
| battery_budget_single_sample | 22013568 | 0.05 |
| battery_budget_60_samples | 1287616 | 0.78 |
| battery_budget_heavy_drain | 665302 | 1.50 |
| smart_motion_accel_change | 22155018 | 0.05 |
| smart_motion_speed_change | 21966513 | 0.05 |


### 2026-06-19 — Commit 3805e471

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 84817 | 11.79 |
| schedule_isWithin_5_entries | 77459 | 12.91 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 653594 | 1.53 |
| location_fromMap_toMap_roundtrip | 473933 | 2.11 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 91074 | 10.98 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 349650 | 2.86 |
| config_toMap | 103519 | 9.66 |
| config_roundtrip | 78864 | 12.68 |
| state_fromMap | 333333 | 3.00 |
| state_toMap | 101112 | 9.89 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21579 | 46.34 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 568181 | 1.76 |
| battery_budget_single_sample | 21994372 | 0.05 |
| smart_motion_speed_change | 21960862 | 0.05 |
| battery_budget_heavy_drain | 665470 | 1.50 |
| battery_budget_60_samples | 1287957 | 0.78 |
| smart_motion_accel_change | 22120831 | 0.05 |


### 2026-06-19 — Commit 4244535e

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 90991 | 10.99 |
| schedule_isWithin_5_entries | 82576 | 12.11 |
| location_fromMap | 1694915 | 0.59 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 469483 | 2.13 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 91240 | 10.96 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 341296 | 2.93 |
| config_toMap | 103626 | 9.65 |
| config_roundtrip | 78492 | 12.74 |
| state_fromMap | 328947 | 3.04 |
| state_toMap | 98039 | 10.20 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1388888 | 0.72 |
| sync_body_context_toMap_50 | 7142857 | 0.14 |
| sync_body_context_fromMap_50 | 22177 | 45.09 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| smart_motion_speed_change | 23389453 | 0.04 |
| smart_motion_accel_change | 23462756 | 0.04 |
| battery_budget_60_samples | 1300669 | 0.77 |
| battery_budget_heavy_drain | 677365 | 1.48 |
| battery_budget_single_sample | 23593181 | 0.04 |


### 2026-06-18 — Commit 06c4d1e8

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 3225806 | 0.31 |
| schedule_matches | 110375 | 9.06 |
| schedule_isWithin_5_entries | 100200 | 9.98 |
| location_fromMap | 2127659 | 0.47 |
| location_toMap | 840336 | 1.19 |
| location_fromMap_toMap_roundtrip | 609756 | 1.64 |
| location_copyWithCoords | 12500000 | 0.08 |
| geofence_fromMap_circular | 5555555 | 0.18 |
| geofence_fromMap_polygon | 2040816 | 0.49 |
| carbon_trip_100_locations | 117647 | 8.50 |
| carbon_onLocation | 5263157 | 0.19 |
| carbon_setActivity | 11111111 | 0.09 |
| carbon_cumulative_report | 3333333 | 0.30 |
| persist_decider_location | 25000000 | 0.04 |
| persist_decider_geofence | 25000000 | 0.04 |
| config_fromMap | 460829 | 2.17 |
| config_toMap | 136798 | 7.31 |
| config_roundtrip | 106157 | 9.42 |
| state_fromMap | 446428 | 2.24 |
| state_toMap | 134589 | 7.43 |
| route_context_toMap | 3846153 | 0.26 |
| route_context_fromMap | 2857142 | 0.35 |
| route_context_roundtrip | 1754385 | 0.57 |
| sync_body_context_toMap_50 | 9090909 | 0.11 |
| sync_body_context_fromMap_50 | 28240 | 35.41 |
| http_config_ssl_toMap | 917431 | 1.09 |
| http_config_ssl_fromMap | 3333333 | 0.30 |
| http_config_ssl_roundtrip | 729927 | 1.37 |
| smart_motion_speed_change | 28235667 | 0.04 |
| battery_budget_60_samples | 1661893 | 0.60 |
| battery_budget_heavy_drain | 857881 | 1.17 |
| battery_budget_single_sample | 28414746 | 0.04 |
| smart_motion_accel_change | 28585930 | 0.03 |


### 2026-06-18 — Commit 2f86cd72

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 84745 | 11.80 |
| schedule_isWithin_5_entries | 76687 | 13.04 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 462962 | 2.16 |
| location_copyWithCoords | 10000000 | 0.10 |
| geofence_fromMap_circular | 4347826 | 0.23 |
| geofence_fromMap_polygon | 1562500 | 0.64 |
| carbon_trip_100_locations | 89686 | 11.15 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 350877 | 2.85 |
| config_toMap | 107296 | 9.32 |
| config_roundtrip | 80710 | 12.39 |
| state_fromMap | 337837 | 2.96 |
| state_toMap | 101832 | 9.82 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21630 | 46.23 |
| http_config_ssl_toMap | 699300 | 1.43 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 568181 | 1.76 |
| battery_budget_heavy_drain | 661703 | 1.51 |
| battery_budget_single_sample | 22024798 | 0.05 |
| smart_motion_speed_change | 21836457 | 0.05 |
| smart_motion_accel_change | 21872103 | 0.05 |
| battery_budget_60_samples | 1283401 | 0.78 |


### 2026-06-18 — Commit caa8d201

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2702702 | 0.37 |
| schedule_matches | 91911 | 10.88 |
| schedule_isWithin_5_entries | 81766 | 12.23 |
| location_fromMap | 1612903 | 0.62 |
| location_toMap | 636942 | 1.57 |
| location_fromMap_toMap_roundtrip | 462962 | 2.16 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 92165 | 10.85 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 361010 | 2.77 |
| config_toMap | 104712 | 9.55 |
| config_roundtrip | 80906 | 12.36 |
| state_fromMap | 350877 | 2.85 |
| state_toMap | 99009 | 10.10 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2272727 | 0.44 |
| route_context_roundtrip | 1351351 | 0.74 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21677 | 46.13 |
| http_config_ssl_toMap | 671140 | 1.49 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 555555 | 1.80 |
| battery_budget_heavy_drain | 676525 | 1.48 |
| battery_budget_single_sample | 23735820 | 0.04 |
| battery_budget_60_samples | 1305930 | 0.77 |
| smart_motion_accel_change | 23487431 | 0.04 |
| smart_motion_speed_change | 23426834 | 0.04 |


### 2026-06-18 — Commit b6f2a224

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 85324 | 11.72 |
| schedule_isWithin_5_entries | 77220 | 12.95 |
| location_fromMap | 1639344 | 0.61 |
| location_toMap | 649350 | 1.54 |
| location_fromMap_toMap_roundtrip | 467289 | 2.14 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1612903 | 0.62 |
| carbon_trip_100_locations | 92336 | 10.83 |
| carbon_onLocation | 4000000 | 0.25 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2500000 | 0.40 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 353356 | 2.83 |
| config_toMap | 107642 | 9.29 |
| config_roundtrip | 82101 | 12.18 |
| state_fromMap | 338983 | 2.95 |
| state_toMap | 104602 | 9.56 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2173913 | 0.46 |
| route_context_roundtrip | 1333333 | 0.75 |
| sync_body_context_toMap_50 | 6666666 | 0.15 |
| sync_body_context_fromMap_50 | 21663 | 46.16 |
| http_config_ssl_toMap | 704225 | 1.42 |
| http_config_ssl_fromMap | 2564102 | 0.39 |
| http_config_ssl_roundtrip | 564971 | 1.77 |
| smart_motion_speed_change | 21960805 | 0.05 |
| battery_budget_heavy_drain | 665537 | 1.50 |
| smart_motion_accel_change | 22151397 | 0.05 |
| battery_budget_single_sample | 22029519 | 0.05 |
| battery_budget_60_samples | 1288545 | 0.78 |


### 2026-06-18 — Commit ab549621

**Environment:** Dart 3.12.2, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| schedule_parse | 2777777 | 0.36 |
| schedule_matches | 92421 | 10.82 |
| schedule_isWithin_5_entries | 83194 | 12.02 |
| location_fromMap | 1666666 | 0.60 |
| location_toMap | 645161 | 1.55 |
| location_fromMap_toMap_roundtrip | 473933 | 2.11 |
| location_copyWithCoords | 11111111 | 0.09 |
| geofence_fromMap_circular | 4545454 | 0.22 |
| geofence_fromMap_polygon | 1587301 | 0.63 |
| carbon_trip_100_locations | 91911 | 10.88 |
| carbon_onLocation | 4166666 | 0.24 |
| carbon_setActivity | 9090909 | 0.11 |
| carbon_cumulative_report | 2564102 | 0.39 |
| persist_decider_location | 20000000 | 0.05 |
| persist_decider_geofence | 20000000 | 0.05 |
| config_fromMap | 364963 | 2.74 |
| config_toMap | 106382 | 9.40 |
| config_roundtrip | 82644 | 12.10 |
| state_fromMap | 350877 | 2.85 |
| state_toMap | 101832 | 9.82 |
| route_context_toMap | 2941176 | 0.34 |
| route_context_fromMap | 2222222 | 0.45 |
| route_context_roundtrip | 1369863 | 0.73 |
| sync_body_context_toMap_50 | 8333333 | 0.12 |
| sync_body_context_fromMap_50 | 22558 | 44.33 |
| http_config_ssl_toMap | 709219 | 1.41 |
| http_config_ssl_fromMap | 2631578 | 0.38 |
| http_config_ssl_roundtrip | 561797 | 1.78 |
| battery_budget_60_samples | 1307840 | 0.76 |
| battery_budget_heavy_drain | 677183 | 1.48 |
| battery_budget_single_sample | 23772363 | 0.04 |
| smart_motion_accel_change | 23530646 | 0.04 |
| smart_motion_speed_change | 23442452 | 0.04 |


