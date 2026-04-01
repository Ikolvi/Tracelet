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

### 2026-04-01 — Commit 0329541

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7226951 | 0.14 |
| kalman_process_100_fixes | 95672 | 10.45 |
| kalman_process_1k_fixes | 9678 | 103.33 |
| kalman_reset | 6650181 | 0.15 |
| haversine_single | 7891211 | 0.13 |
| haversine_1k_pairs | 13752 | 72.72 |
| pip_4v | 12897556 | 0.08 |
| pip_10v | 9914822 | 0.10 |
| pip_50v | 3790011 | 0.26 |
| pip_100v | 2027082 | 0.49 |
| pip_500v | 415679 | 2.41 |
| geofence_eval_10_circular | 632631 | 1.58 |
| geofence_eval_100_circular | 69257 | 14.44 |
| geofence_eval_500_circular | 13393 | 74.67 |
| geofence_eval_10_polygon_6v | 412431 | 2.42 |
| geofence_eval_50_polygon_6v | 83523 | 11.97 |
| processor_1k_fixes | 9065 | 110.31 |
| processor_1k_adaptive | 8481 | 117.91 |
| trip_manager_5k_waypoints | 73 | 13740.72 |
| schedule_parse | 2863647 | 0.35 |
| schedule_matches | 130673 | 7.65 |
| schedule_isWithin_5_entries | 124814 | 8.01 |
| adaptive_compute | 12664392 | 0.08 |
| location_fromMap | 1646021 | 0.61 |
| location_toMap | 662579 | 1.51 |
| location_fromMap_toMap_roundtrip | 486840 | 2.05 |
| location_copyWithCoords | 11522016 | 0.09 |
| geofence_fromMap_circular | 4040899 | 0.25 |
| geofence_fromMap_polygon | 1523908 | 0.66 |
| delta_encode_10 | 28791 | 34.73 |
| delta_decode_10 | 97256 | 10.28 |
| delta_encode_100 | 4089 | 244.56 |
| delta_decode_100 | 11040 | 90.58 |
| delta_encode_500 | 839 | 1191.24 |
| delta_decode_500 | 2321 | 430.77 |
| delta_roundtrip_100 | 2954 | 338.49 |
| battery_budget_single_sample | 8657560 | 0.12 |
| battery_budget_60_samples | 284882 | 3.51 |
| battery_budget_heavy_drain | 146224 | 6.84 |
| carbon_trip_100_locations | 94418 | 10.59 |
| carbon_onLocation | 4173526 | 0.24 |
| carbon_setActivity | 9514029 | 0.11 |
| carbon_cumulative_report | 2683539 | 0.37 |
| persist_decider_location | 19988041 | 0.05 |
| persist_decider_geofence | 19933488 | 0.05 |
| config_fromMap | 431975 | 2.31 |
| config_toMap | 157221 | 6.36 |
| config_roundtrip | 114863 | 8.71 |
| state_fromMap | 409382 | 2.44 |
| state_toMap | 151053 | 6.62 |
| route_context_toMap | 3026093 | 0.33 |
| route_context_fromMap | 2339292 | 0.43 |
| route_context_roundtrip | 1420323 | 0.70 |
| sync_body_context_toMap_50 | 8231748 | 0.12 |
| sync_body_context_fromMap_50 | 23228 | 43.05 |
| http_config_ssl_toMap | 775807 | 1.29 |
| http_config_ssl_fromMap | 1402150 | 0.71 |
| http_config_ssl_roundtrip | 502751 | 1.99 |


### 2026-03-30 — Commit 63b30e7

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7080710 | 0.14 |
| kalman_process_100_fixes | 97640 | 10.24 |
| kalman_process_1k_fixes | 9935 | 100.65 |
| kalman_reset | 6703632 | 0.15 |
| haversine_single | 9244348 | 0.11 |
| haversine_1k_pairs | 16933 | 59.06 |
| pip_4v | 13226488 | 0.08 |
| pip_10v | 10242004 | 0.10 |
| pip_50v | 4022997 | 0.25 |
| pip_100v | 2203301 | 0.45 |
| pip_500v | 446138 | 2.24 |
| geofence_eval_10_circular | 677603 | 1.48 |
| geofence_eval_100_circular | 74499 | 13.42 |
| geofence_eval_500_circular | 14329 | 69.79 |
| geofence_eval_10_polygon_6v | 442178 | 2.26 |
| geofence_eval_50_polygon_6v | 88080 | 11.35 |
| processor_1k_fixes | 10793 | 92.65 |
| processor_1k_adaptive | 10161 | 98.42 |
| trip_manager_5k_waypoints | 140 | 7128.91 |
| schedule_parse | 3110674 | 0.32 |
| schedule_matches | 260526 | 3.84 |
| schedule_isWithin_5_entries | 230949 | 4.33 |
| adaptive_compute | 14132643 | 0.07 |
| location_fromMap | 1691123 | 0.59 |
| location_toMap | 621353 | 1.61 |
| location_fromMap_toMap_roundtrip | 463969 | 2.16 |
| location_copyWithCoords | 11370648 | 0.09 |
| geofence_fromMap_circular | 4368756 | 0.23 |
| geofence_fromMap_polygon | 1504990 | 0.66 |
| delta_encode_10 | 31829 | 31.42 |
| delta_decode_10 | 92163 | 10.85 |
| delta_encode_100 | 4173 | 239.66 |
| delta_decode_100 | 10856 | 92.12 |
| delta_encode_500 | 779 | 1283.96 |
| delta_decode_500 | 1972 | 507.14 |
| delta_roundtrip_100 | 3050 | 327.89 |
| battery_budget_single_sample | 8365585 | 0.12 |
| battery_budget_60_samples | 290414 | 3.44 |
| battery_budget_heavy_drain | 150527 | 6.64 |
| carbon_trip_100_locations | 104244 | 9.59 |
| carbon_onLocation | 4392900 | 0.23 |
| carbon_setActivity | 10862352 | 0.09 |
| carbon_cumulative_report | 2794122 | 0.36 |
| persist_decider_location | 20520683 | 0.05 |
| persist_decider_geofence | 20578060 | 0.05 |
| config_fromMap | 449352 | 2.23 |
| config_toMap | 162033 | 6.17 |
| config_roundtrip | 114934 | 8.70 |
| state_fromMap | 419511 | 2.38 |
| state_toMap | 153668 | 6.51 |
| route_context_toMap | 2999995 | 0.33 |
| route_context_fromMap | 2480226 | 0.40 |
| route_context_roundtrip | 1376628 | 0.73 |
| sync_body_context_toMap_50 | 8559913 | 0.12 |
| sync_body_context_fromMap_50 | 22755 | 43.95 |
| http_config_ssl_toMap | 764360 | 1.31 |
| http_config_ssl_fromMap | 1411645 | 0.71 |
| http_config_ssl_roundtrip | 490960 | 2.04 |


### 2026-03-29 — Commit 1258494

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7026361 | 0.14 |
| kalman_process_100_fixes | 97043 | 10.30 |
| kalman_process_1k_fixes | 9460 | 105.71 |
| kalman_reset | 6256418 | 0.16 |
| haversine_single | 8564177 | 0.12 |
| haversine_1k_pairs | 18997 | 52.64 |
| pip_4v | 10757937 | 0.09 |
| pip_10v | 9075937 | 0.11 |
| pip_50v | 3893096 | 0.26 |
| pip_100v | 2153842 | 0.46 |
| pip_500v | 439403 | 2.28 |
| geofence_eval_10_circular | 664413 | 1.51 |
| geofence_eval_100_circular | 75622 | 13.22 |
| geofence_eval_500_circular | 14429 | 69.30 |
| geofence_eval_10_polygon_6v | 439243 | 2.28 |
| geofence_eval_50_polygon_6v | 88437 | 11.31 |
| processor_1k_fixes | 10832 | 92.32 |
| processor_1k_adaptive | 9868 | 101.33 |
| trip_manager_5k_waypoints | 138 | 7250.65 |
| schedule_parse | 2880918 | 0.35 |
| schedule_matches | 255325 | 3.92 |
| schedule_isWithin_5_entries | 226491 | 4.42 |
| adaptive_compute | 10981052 | 0.09 |
| location_fromMap | 1584987 | 0.63 |
| location_toMap | 577746 | 1.73 |
| location_fromMap_toMap_roundtrip | 437715 | 2.28 |
| location_copyWithCoords | 9570446 | 0.10 |
| geofence_fromMap_circular | 3980189 | 0.25 |
| geofence_fromMap_polygon | 1458748 | 0.69 |
| delta_encode_10 | 31285 | 31.96 |
| delta_decode_10 | 87119 | 11.48 |
| delta_encode_100 | 4142 | 241.41 |
| delta_decode_100 | 10385 | 96.29 |
| delta_encode_500 | 803 | 1244.83 |
| delta_decode_500 | 2070 | 483.18 |
| delta_roundtrip_100 | 2969 | 336.82 |
| battery_budget_single_sample | 8497237 | 0.12 |
| battery_budget_60_samples | 301919 | 3.31 |
| battery_budget_heavy_drain | 153047 | 6.53 |
| carbon_trip_100_locations | 109427 | 9.14 |
| carbon_onLocation | 4339950 | 0.23 |
| carbon_setActivity | 10465245 | 0.10 |
| carbon_cumulative_report | 2683003 | 0.37 |
| persist_decider_location | 17043038 | 0.06 |
| persist_decider_geofence | 17467422 | 0.06 |
| config_fromMap | 419960 | 2.38 |
| config_toMap | 158752 | 6.30 |
| config_roundtrip | 111237 | 8.99 |
| state_fromMap | 392979 | 2.54 |
| state_toMap | 149957 | 6.67 |
| route_context_toMap | 2779081 | 0.36 |
| route_context_fromMap | 2259254 | 0.44 |
| route_context_roundtrip | 1280381 | 0.78 |
| sync_body_context_toMap_50 | 7550483 | 0.13 |
| sync_body_context_fromMap_50 | 22175 | 45.10 |
| http_config_ssl_toMap | 744694 | 1.34 |
| http_config_ssl_fromMap | 1393815 | 0.72 |
| http_config_ssl_roundtrip | 476175 | 2.10 |


### 2026-03-28 — Commit bcca81f

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7272348 | 0.14 |
| kalman_process_100_fixes | 96247 | 10.39 |
| kalman_process_1k_fixes | 9692 | 103.18 |
| kalman_reset | 6716344 | 0.15 |
| haversine_single | 8021636 | 0.12 |
| haversine_1k_pairs | 13766 | 72.64 |
| pip_4v | 13222730 | 0.08 |
| pip_10v | 9617157 | 0.10 |
| pip_50v | 4019635 | 0.25 |
| pip_100v | 2178092 | 0.46 |
| pip_500v | 426279 | 2.35 |
| geofence_eval_10_circular | 644141 | 1.55 |
| geofence_eval_100_circular | 70012 | 14.28 |
| geofence_eval_500_circular | 13385 | 74.71 |
| geofence_eval_10_polygon_6v | 418340 | 2.39 |
| geofence_eval_50_polygon_6v | 83059 | 12.04 |
| processor_1k_fixes | 8945 | 111.79 |
| processor_1k_adaptive | 8471 | 118.04 |
| trip_manager_5k_waypoints | 71 | 14071.13 |
| schedule_parse | 2901118 | 0.34 |
| schedule_matches | 130810 | 7.64 |
| schedule_isWithin_5_entries | 123226 | 8.12 |
| adaptive_compute | 13251011 | 0.08 |
| location_fromMap | 1679609 | 0.60 |
| location_toMap | 664087 | 1.51 |
| location_fromMap_toMap_roundtrip | 475724 | 2.10 |
| location_copyWithCoords | 11924095 | 0.08 |
| geofence_fromMap_circular | 4418598 | 0.23 |
| geofence_fromMap_polygon | 1254275 | 0.80 |
| delta_encode_10 | 28186 | 35.48 |
| delta_decode_10 | 93278 | 10.72 |
| delta_encode_100 | 3902 | 256.26 |
| delta_decode_100 | 10386 | 96.28 |
| delta_encode_500 | 847 | 1180.05 |
| delta_decode_500 | 2074 | 482.06 |
| delta_roundtrip_100 | 2913 | 343.32 |
| battery_budget_single_sample | 8990311 | 0.11 |
| battery_budget_60_samples | 283914 | 3.52 |
| battery_budget_heavy_drain | 146782 | 6.81 |
| carbon_trip_100_locations | 89752 | 11.14 |
| carbon_onLocation | 4200358 | 0.24 |
| carbon_setActivity | 9834123 | 0.10 |
| carbon_cumulative_report | 2730240 | 0.37 |
| persist_decider_location | 19386065 | 0.05 |
| persist_decider_geofence | 19480324 | 0.05 |
| config_fromMap | 420559 | 2.38 |
| config_toMap | 158518 | 6.31 |
| config_roundtrip | 113372 | 8.82 |
| state_fromMap | 397494 | 2.52 |
| state_toMap | 150155 | 6.66 |
| route_context_toMap | 3088072 | 0.32 |
| route_context_fromMap | 2279913 | 0.44 |
| route_context_roundtrip | 1391739 | 0.72 |
| sync_body_context_toMap_50 | 8404992 | 0.12 |
| sync_body_context_fromMap_50 | 22794 | 43.87 |
| http_config_ssl_toMap | 763437 | 1.31 |
| http_config_ssl_fromMap | 1424953 | 0.70 |
| http_config_ssl_roundtrip | 499494 | 2.00 |


### 2026-03-27 — Commit 57d4fa9

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7285353 | 0.14 |
| kalman_process_100_fixes | 96427 | 10.37 |
| kalman_process_1k_fixes | 9574 | 104.45 |
| kalman_reset | 6861993 | 0.15 |
| haversine_single | 8073029 | 0.12 |
| haversine_1k_pairs | 13876 | 72.07 |
| pip_4v | 13153184 | 0.08 |
| pip_10v | 9790368 | 0.10 |
| pip_50v | 3747141 | 0.27 |
| pip_100v | 2050202 | 0.49 |
| pip_500v | 420379 | 2.38 |
| geofence_eval_10_circular | 634760 | 1.58 |
| geofence_eval_100_circular | 69403 | 14.41 |
| geofence_eval_500_circular | 13313 | 75.11 |
| geofence_eval_10_polygon_6v | 415192 | 2.41 |
| geofence_eval_50_polygon_6v | 83791 | 11.93 |
| processor_1k_fixes | 9021 | 110.85 |
| processor_1k_adaptive | 8530 | 117.24 |
| trip_manager_5k_waypoints | 73 | 13761.61 |
| schedule_parse | 2833658 | 0.35 |
| schedule_matches | 131421 | 7.61 |
| schedule_isWithin_5_entries | 124397 | 8.04 |
| adaptive_compute | 13656546 | 0.07 |
| location_fromMap | 1725768 | 0.58 |
| location_toMap | 651762 | 1.53 |
| location_fromMap_toMap_roundtrip | 474837 | 2.11 |
| location_copyWithCoords | 11635751 | 0.09 |
| geofence_fromMap_circular | 4443717 | 0.23 |
| geofence_fromMap_polygon | 1564869 | 0.64 |
| delta_encode_10 | 29080 | 34.39 |
| delta_decode_10 | 95783 | 10.44 |
| delta_encode_100 | 3938 | 253.93 |
| delta_decode_100 | 10880 | 91.92 |
| delta_encode_500 | 811 | 1232.57 |
| delta_decode_500 | 2092 | 477.92 |
| delta_roundtrip_100 | 2892 | 345.77 |
| battery_budget_single_sample | 9132601 | 0.11 |
| battery_budget_60_samples | 289502 | 3.45 |
| battery_budget_heavy_drain | 147599 | 6.78 |
| carbon_trip_100_locations | 90861 | 11.01 |
| carbon_onLocation | 4133365 | 0.24 |
| carbon_setActivity | 9906920 | 0.10 |
| carbon_cumulative_report | 2599177 | 0.38 |
| persist_decider_location | 19926943 | 0.05 |
| persist_decider_geofence | 19987898 | 0.05 |
| config_fromMap | 421472 | 2.37 |
| config_toMap | 158058 | 6.33 |
| config_roundtrip | 113710 | 8.79 |
| state_fromMap | 398199 | 2.51 |
| state_toMap | 149234 | 6.70 |
| route_context_toMap | 3087441 | 0.32 |
| route_context_fromMap | 2355140 | 0.42 |
| route_context_roundtrip | 1431365 | 0.70 |
| sync_body_context_toMap_50 | 8317036 | 0.12 |
| sync_body_context_fromMap_50 | 22953 | 43.57 |
| http_config_ssl_toMap | 760488 | 1.31 |
| http_config_ssl_fromMap | 1447019 | 0.69 |
| http_config_ssl_roundtrip | 490478 | 2.04 |


### 2026-03-26 — Commit 5283304

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7082534 | 0.14 |
| kalman_process_100_fixes | 95655 | 10.45 |
| kalman_process_1k_fixes | 9502 | 105.24 |
| kalman_reset | 6710118 | 0.15 |
| haversine_single | 8172926 | 0.12 |
| haversine_1k_pairs | 14056 | 71.14 |
| pip_4v | 12509575 | 0.08 |
| pip_10v | 9822685 | 0.10 |
| pip_50v | 3646230 | 0.27 |
| pip_100v | 1986608 | 0.50 |
| pip_500v | 420890 | 2.38 |
| geofence_eval_10_circular | 644127 | 1.55 |
| geofence_eval_100_circular | 69381 | 14.41 |
| geofence_eval_500_circular | 13547 | 73.82 |
| geofence_eval_10_polygon_6v | 421169 | 2.37 |
| geofence_eval_50_polygon_6v | 86171 | 11.60 |
| processor_1k_fixes | 9081 | 110.12 |
| processor_1k_adaptive | 8587 | 116.45 |
| trip_manager_5k_waypoints | 66 | 15166.94 |
| schedule_parse | 2878457 | 0.35 |
| schedule_matches | 119440 | 8.37 |
| schedule_isWithin_5_entries | 112617 | 8.88 |
| adaptive_compute | 13468433 | 0.07 |
| location_fromMap | 1568820 | 0.64 |
| location_toMap | 637919 | 1.57 |
| location_fromMap_toMap_roundtrip | 447697 | 2.23 |
| location_copyWithCoords | 12083980 | 0.08 |
| geofence_fromMap_circular | 4405850 | 0.23 |
| geofence_fromMap_polygon | 1576386 | 0.63 |
| delta_encode_10 | 29246 | 34.19 |
| delta_decode_10 | 94737 | 10.56 |
| delta_encode_100 | 3988 | 250.73 |
| delta_decode_100 | 10710 | 93.37 |
| delta_encode_500 | 819 | 1220.92 |
| delta_decode_500 | 2095 | 477.29 |
| delta_roundtrip_100 | 2922 | 342.18 |
| battery_budget_single_sample | 8085151 | 0.12 |
| battery_budget_60_samples | 227224 | 4.40 |
| battery_budget_heavy_drain | 116169 | 8.61 |
| carbon_trip_100_locations | 93757 | 10.67 |
| carbon_onLocation | 3951538 | 0.25 |
| carbon_setActivity | 8547843 | 0.12 |
| carbon_cumulative_report | 2667484 | 0.37 |
| persist_decider_location | 19601614 | 0.05 |
| persist_decider_geofence | 19657979 | 0.05 |
| config_fromMap | 403894 | 2.48 |
| config_toMap | 156513 | 6.39 |
| config_roundtrip | 110629 | 9.04 |
| state_fromMap | 394604 | 2.53 |
| state_toMap | 145311 | 6.88 |
| route_context_toMap | 2888324 | 0.35 |
| route_context_fromMap | 2353751 | 0.42 |
| route_context_roundtrip | 1402620 | 0.71 |
| sync_body_context_toMap_50 | 8444838 | 0.12 |
| sync_body_context_fromMap_50 | 23308 | 42.90 |
| http_config_ssl_toMap | 779285 | 1.28 |
| http_config_ssl_fromMap | 1390798 | 0.72 |
| http_config_ssl_roundtrip | 501129 | 2.00 |


