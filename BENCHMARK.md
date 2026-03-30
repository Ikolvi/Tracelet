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

### 2026-03-30 — Commit 86c231f

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7160247 | 0.14 |
| kalman_process_100_fixes | 95779 | 10.44 |
| kalman_process_1k_fixes | 9591 | 104.27 |
| kalman_reset | 6487242 | 0.15 |
| haversine_single | 8071291 | 0.12 |
| haversine_1k_pairs | 13752 | 72.72 |
| pip_4v | 13067635 | 0.08 |
| pip_10v | 10097428 | 0.10 |
| pip_50v | 3896926 | 0.26 |
| pip_100v | 2009005 | 0.50 |
| pip_500v | 420893 | 2.38 |
| geofence_eval_10_circular | 636606 | 1.57 |
| geofence_eval_100_circular | 69368 | 14.42 |
| geofence_eval_500_circular | 13182 | 75.86 |
| geofence_eval_10_polygon_6v | 409466 | 2.44 |
| geofence_eval_50_polygon_6v | 83360 | 12.00 |
| processor_1k_fixes | 8950 | 111.73 |
| processor_1k_adaptive | 8412 | 118.88 |
| trip_manager_5k_waypoints | 71 | 14032.69 |
| schedule_parse | 2882983 | 0.35 |
| schedule_matches | 130762 | 7.65 |
| schedule_isWithin_5_entries | 123751 | 8.08 |
| adaptive_compute | 13644371 | 0.07 |
| location_fromMap | 1703640 | 0.59 |
| location_toMap | 673279 | 1.49 |
| location_fromMap_toMap_roundtrip | 474892 | 2.11 |
| location_copyWithCoords | 11830997 | 0.08 |
| geofence_fromMap_circular | 4442934 | 0.23 |
| geofence_fromMap_polygon | 1579165 | 0.63 |
| delta_encode_10 | 30523 | 32.76 |
| delta_decode_10 | 95744 | 10.44 |
| delta_encode_100 | 4117 | 242.92 |
| delta_decode_100 | 10648 | 93.92 |
| delta_encode_500 | 858 | 1165.59 |
| delta_decode_500 | 2306 | 433.58 |
| delta_roundtrip_100 | 3016 | 331.58 |
| battery_budget_single_sample | 9003171 | 0.11 |
| battery_budget_60_samples | 290519 | 3.44 |
| battery_budget_heavy_drain | 147995 | 6.76 |
| carbon_trip_100_locations | 87860 | 11.38 |
| carbon_onLocation | 3892555 | 0.26 |
| carbon_setActivity | 9762885 | 0.10 |
| carbon_cumulative_report | 2720789 | 0.37 |
| persist_decider_location | 19498825 | 0.05 |
| persist_decider_geofence | 19816476 | 0.05 |
| config_fromMap | 427978 | 2.34 |
| config_toMap | 159592 | 6.27 |
| config_roundtrip | 113410 | 8.82 |
| state_fromMap | 397694 | 2.51 |
| state_toMap | 149370 | 6.69 |
| route_context_toMap | 2962061 | 0.34 |
| route_context_fromMap | 2382277 | 0.42 |
| route_context_roundtrip | 1435899 | 0.70 |
| sync_body_context_toMap_50 | 7793326 | 0.13 |
| sync_body_context_fromMap_50 | 22973 | 43.53 |
| http_config_ssl_toMap | 759694 | 1.32 |
| http_config_ssl_fromMap | 1456801 | 0.69 |
| http_config_ssl_roundtrip | 504579 | 1.98 |


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


### 2026-03-24 — Commit 0d42efa

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7284537 | 0.14 |
| kalman_process_100_fixes | 94963 | 10.53 |
| kalman_process_1k_fixes | 9647 | 103.65 |
| kalman_reset | 6797170 | 0.15 |
| haversine_single | 7978740 | 0.13 |
| haversine_1k_pairs | 13779 | 72.57 |
| pip_4v | 13264227 | 0.08 |
| pip_10v | 10070397 | 0.10 |
| pip_50v | 3855537 | 0.26 |
| pip_100v | 2068942 | 0.48 |
| pip_500v | 415335 | 2.41 |
| geofence_eval_10_circular | 626087 | 1.60 |
| geofence_eval_100_circular | 67726 | 14.77 |
| geofence_eval_500_circular | 13172 | 75.92 |
| geofence_eval_10_polygon_6v | 404722 | 2.47 |
| geofence_eval_50_polygon_6v | 82227 | 12.16 |
| processor_1k_fixes | 8666 | 115.40 |
| processor_1k_adaptive | 8235 | 121.43 |
| trip_manager_5k_waypoints | 65 | 15391.66 |
| schedule_parse | 2869716 | 0.35 |
| schedule_matches | 118008 | 8.47 |
| schedule_isWithin_5_entries | 113540 | 8.81 |
| adaptive_compute | 13895268 | 0.07 |
| location_fromMap | 1704084 | 0.59 |
| location_toMap | 654439 | 1.53 |
| location_fromMap_toMap_roundtrip | 476581 | 2.10 |
| location_copyWithCoords | 11860403 | 0.08 |
| geofence_fromMap_circular | 4410252 | 0.23 |
| geofence_fromMap_polygon | 1579227 | 0.63 |
| delta_encode_10 | 29091 | 34.37 |
| delta_decode_10 | 95266 | 10.50 |
| delta_encode_100 | 3955 | 252.82 |
| delta_decode_100 | 10673 | 93.70 |
| delta_encode_500 | 806 | 1241.43 |
| delta_decode_500 | 1998 | 500.46 |
| delta_roundtrip_100 | 2859 | 349.83 |
| battery_budget_single_sample | 9299814 | 0.11 |
| battery_budget_60_samples | 251618 | 3.97 |
| battery_budget_heavy_drain | 127695 | 7.83 |
| carbon_trip_100_locations | 88717 | 11.27 |
| carbon_onLocation | 4047692 | 0.25 |
| carbon_setActivity | 9603858 | 0.10 |
| carbon_cumulative_report | 2677278 | 0.37 |
| persist_decider_location | 19906641 | 0.05 |
| persist_decider_geofence | 19938724 | 0.05 |
| config_fromMap | 421886 | 2.37 |
| config_toMap | 154894 | 6.46 |
| config_roundtrip | 112012 | 8.93 |
| state_fromMap | 392716 | 2.55 |
| state_toMap | 145418 | 6.88 |
| route_context_toMap | 3042610 | 0.33 |
| route_context_fromMap | 2257511 | 0.44 |
| route_context_roundtrip | 1375989 | 0.73 |
| sync_body_context_toMap_50 | 7764549 | 0.13 |
| sync_body_context_fromMap_50 | 23212 | 43.08 |
| http_config_ssl_toMap | 764764 | 1.31 |
| http_config_ssl_fromMap | 1417260 | 0.71 |
| http_config_ssl_roundtrip | 488823 | 2.05 |


