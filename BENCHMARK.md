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

### 2026-03-30 — Commit fcb7d76

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7112056 | 0.14 |
| kalman_process_100_fixes | 88526 | 11.30 |
| kalman_process_1k_fixes | 8886 | 112.53 |
| kalman_reset | 6518845 | 0.15 |
| haversine_single | 9059053 | 0.11 |
| haversine_1k_pairs | 17999 | 55.56 |
| pip_4v | 13627667 | 0.07 |
| pip_10v | 10330079 | 0.10 |
| pip_50v | 4027839 | 0.25 |
| pip_100v | 2138891 | 0.47 |
| pip_500v | 442231 | 2.26 |
| geofence_eval_10_circular | 667012 | 1.50 |
| geofence_eval_100_circular | 76138 | 13.13 |
| geofence_eval_500_circular | 14238 | 70.23 |
| geofence_eval_10_polygon_6v | 437562 | 2.29 |
| geofence_eval_50_polygon_6v | 86048 | 11.62 |
| processor_1k_fixes | 10644 | 93.95 |
| processor_1k_adaptive | 10311 | 96.98 |
| trip_manager_5k_waypoints | 138 | 7259.93 |
| schedule_parse | 2857985 | 0.35 |
| schedule_matches | 252241 | 3.96 |
| schedule_isWithin_5_entries | 225077 | 4.44 |
| adaptive_compute | 12960640 | 0.08 |
| location_fromMap | 1657981 | 0.60 |
| location_toMap | 585793 | 1.71 |
| location_fromMap_toMap_roundtrip | 453006 | 2.21 |
| location_copyWithCoords | 11010586 | 0.09 |
| geofence_fromMap_circular | 4341630 | 0.23 |
| geofence_fromMap_polygon | 1480506 | 0.68 |
| delta_encode_10 | 31966 | 31.28 |
| delta_decode_10 | 89617 | 11.16 |
| delta_encode_100 | 4205 | 237.79 |
| delta_decode_100 | 10488 | 95.35 |
| delta_encode_500 | 754 | 1326.54 |
| delta_decode_500 | 1816 | 550.60 |
| delta_roundtrip_100 | 3020 | 331.13 |
| battery_budget_single_sample | 8516527 | 0.12 |
| battery_budget_60_samples | 296654 | 3.37 |
| battery_budget_heavy_drain | 151541 | 6.60 |
| carbon_trip_100_locations | 103929 | 9.62 |
| carbon_onLocation | 4396091 | 0.23 |
| carbon_setActivity | 10152197 | 0.10 |
| carbon_cumulative_report | 2592538 | 0.39 |
| persist_decider_location | 21909266 | 0.05 |
| persist_decider_geofence | 21153490 | 0.05 |
| config_fromMap | 402348 | 2.49 |
| config_toMap | 153365 | 6.52 |
| config_roundtrip | 109504 | 9.13 |
| state_fromMap | 380014 | 2.63 |
| state_toMap | 144970 | 6.90 |
| route_context_toMap | 2877331 | 0.35 |
| route_context_fromMap | 2221170 | 0.45 |
| route_context_roundtrip | 1242728 | 0.80 |
| sync_body_context_toMap_50 | 8071749 | 0.12 |
| sync_body_context_fromMap_50 | 21781 | 45.91 |
| http_config_ssl_toMap | 731074 | 1.37 |
| http_config_ssl_fromMap | 1320979 | 0.76 |
| http_config_ssl_roundtrip | 471251 | 2.12 |


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


### 2026-03-27 — Commit 832b84e

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7214237 | 0.14 |
| kalman_process_100_fixes | 93700 | 10.67 |
| kalman_process_1k_fixes | 9419 | 106.17 |
| kalman_reset | 6712232 | 0.15 |
| haversine_single | 8035081 | 0.12 |
| haversine_1k_pairs | 13822 | 72.35 |
| pip_4v | 13302156 | 0.08 |
| pip_10v | 10171360 | 0.10 |
| pip_50v | 4004277 | 0.25 |
| pip_100v | 2138618 | 0.47 |
| pip_500v | 404377 | 2.47 |
| geofence_eval_10_circular | 639114 | 1.56 |
| geofence_eval_100_circular | 70310 | 14.22 |
| geofence_eval_500_circular | 13358 | 74.86 |
| geofence_eval_10_polygon_6v | 408615 | 2.45 |
| geofence_eval_50_polygon_6v | 83991 | 11.91 |
| processor_1k_fixes | 8932 | 111.96 |
| processor_1k_adaptive | 8488 | 117.82 |
| trip_manager_5k_waypoints | 73 | 13666.29 |
| schedule_parse | 2859806 | 0.35 |
| schedule_matches | 129613 | 7.72 |
| schedule_isWithin_5_entries | 124753 | 8.02 |
| adaptive_compute | 13754689 | 0.07 |
| location_fromMap | 1647873 | 0.61 |
| location_toMap | 659553 | 1.52 |
| location_fromMap_toMap_roundtrip | 473462 | 2.11 |
| location_copyWithCoords | 12147748 | 0.08 |
| geofence_fromMap_circular | 4510676 | 0.22 |
| geofence_fromMap_polygon | 1600693 | 0.62 |
| delta_encode_10 | 30009 | 33.32 |
| delta_decode_10 | 92778 | 10.78 |
| delta_encode_100 | 4048 | 247.04 |
| delta_decode_100 | 10809 | 92.52 |
| delta_encode_500 | 862 | 1159.51 |
| delta_decode_500 | 2301 | 434.64 |
| delta_roundtrip_100 | 2910 | 343.65 |
| battery_budget_single_sample | 8870593 | 0.11 |
| battery_budget_60_samples | 289797 | 3.45 |
| battery_budget_heavy_drain | 146645 | 6.82 |
| carbon_trip_100_locations | 87586 | 11.42 |
| carbon_onLocation | 4165616 | 0.24 |
| carbon_setActivity | 9739670 | 0.10 |
| carbon_cumulative_report | 2711341 | 0.37 |
| persist_decider_location | 19557001 | 0.05 |
| persist_decider_geofence | 19621820 | 0.05 |
| config_fromMap | 420826 | 2.38 |
| config_toMap | 154730 | 6.46 |
| config_roundtrip | 111382 | 8.98 |
| state_fromMap | 398452 | 2.51 |
| state_toMap | 146107 | 6.84 |
| route_context_toMap | 3065706 | 0.33 |
| route_context_fromMap | 2328917 | 0.43 |
| route_context_roundtrip | 1412554 | 0.71 |
| sync_body_context_toMap_50 | 7761069 | 0.13 |
| sync_body_context_fromMap_50 | 22857 | 43.75 |
| http_config_ssl_toMap | 765126 | 1.31 |
| http_config_ssl_fromMap | 1437973 | 0.70 |
| http_config_ssl_roundtrip | 493931 | 2.02 |


### 2026-03-27 — Commit 3440bc5

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7348283 | 0.14 |
| kalman_process_100_fixes | 93866 | 10.65 |
| kalman_process_1k_fixes | 9497 | 105.29 |
| kalman_reset | 6789601 | 0.15 |
| haversine_single | 7999140 | 0.13 |
| haversine_1k_pairs | 13780 | 72.57 |
| pip_4v | 12853831 | 0.08 |
| pip_10v | 9973563 | 0.10 |
| pip_50v | 3721517 | 0.27 |
| pip_100v | 1975492 | 0.51 |
| pip_500v | 422610 | 2.37 |
| geofence_eval_10_circular | 647398 | 1.54 |
| geofence_eval_100_circular | 70417 | 14.20 |
| geofence_eval_500_circular | 13549 | 73.81 |
| geofence_eval_10_polygon_6v | 420675 | 2.38 |
| geofence_eval_50_polygon_6v | 85425 | 11.71 |
| processor_1k_fixes | 8905 | 112.29 |
| processor_1k_adaptive | 8465 | 118.14 |
| trip_manager_5k_waypoints | 73 | 13740.95 |
| schedule_parse | 2884887 | 0.35 |
| schedule_matches | 131054 | 7.63 |
| schedule_isWithin_5_entries | 123593 | 8.09 |
| adaptive_compute | 13848937 | 0.07 |
| location_fromMap | 1639743 | 0.61 |
| location_toMap | 678591 | 1.47 |
| location_fromMap_toMap_roundtrip | 491672 | 2.03 |
| location_copyWithCoords | 12299535 | 0.08 |
| geofence_fromMap_circular | 4533720 | 0.22 |
| geofence_fromMap_polygon | 1597079 | 0.63 |
| delta_encode_10 | 30024 | 33.31 |
| delta_decode_10 | 97408 | 10.27 |
| delta_encode_100 | 4156 | 240.59 |
| delta_decode_100 | 10821 | 92.41 |
| delta_encode_500 | 825 | 1212.82 |
| delta_decode_500 | 2282 | 438.22 |
| delta_roundtrip_100 | 3009 | 332.28 |
| battery_budget_single_sample | 9081236 | 0.11 |
| battery_budget_60_samples | 292737 | 3.42 |
| battery_budget_heavy_drain | 147813 | 6.77 |
| carbon_trip_100_locations | 90531 | 11.05 |
| carbon_onLocation | 4173076 | 0.24 |
| carbon_setActivity | 9841706 | 0.10 |
| carbon_cumulative_report | 2735548 | 0.37 |
| persist_decider_location | 19940146 | 0.05 |
| persist_decider_geofence | 19862792 | 0.05 |
| config_fromMap | 432196 | 2.31 |
| config_toMap | 158389 | 6.31 |
| config_roundtrip | 115305 | 8.67 |
| state_fromMap | 401537 | 2.49 |
| state_toMap | 149355 | 6.70 |
| route_context_toMap | 2991496 | 0.33 |
| route_context_fromMap | 2360030 | 0.42 |
| route_context_roundtrip | 1420052 | 0.70 |
| sync_body_context_toMap_50 | 8324564 | 0.12 |
| sync_body_context_fromMap_50 | 23005 | 43.47 |
| http_config_ssl_toMap | 773407 | 1.29 |
| http_config_ssl_fromMap | 1429925 | 0.70 |
| http_config_ssl_roundtrip | 509973 | 1.96 |


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


### 2026-03-26 — Commit 61f8666

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7366030 | 0.14 |
| kalman_process_100_fixes | 96795 | 10.33 |
| kalman_process_1k_fixes | 9708 | 103.00 |
| kalman_reset | 6685215 | 0.15 |
| haversine_single | 8028238 | 0.12 |
| haversine_1k_pairs | 13819 | 72.36 |
| pip_4v | 13309269 | 0.08 |
| pip_10v | 9955021 | 0.10 |
| pip_50v | 3753360 | 0.27 |
| pip_100v | 2066585 | 0.48 |
| pip_500v | 420862 | 2.38 |
| geofence_eval_10_circular | 633555 | 1.58 |
| geofence_eval_100_circular | 69789 | 14.33 |
| geofence_eval_500_circular | 13420 | 74.52 |
| geofence_eval_10_polygon_6v | 419641 | 2.38 |
| geofence_eval_50_polygon_6v | 85277 | 11.73 |
| processor_1k_fixes | 8928 | 112.01 |
| processor_1k_adaptive | 8418 | 118.79 |
| trip_manager_5k_waypoints | 73 | 13662.49 |
| schedule_parse | 2907158 | 0.34 |
| schedule_matches | 130596 | 7.66 |
| schedule_isWithin_5_entries | 122870 | 8.14 |
| adaptive_compute | 13856955 | 0.07 |
| location_fromMap | 1719473 | 0.58 |
| location_toMap | 682447 | 1.47 |
| location_fromMap_toMap_roundtrip | 497433 | 2.01 |
| location_copyWithCoords | 12350997 | 0.08 |
| geofence_fromMap_circular | 4415366 | 0.23 |
| geofence_fromMap_polygon | 1582875 | 0.63 |
| delta_encode_10 | 29966 | 33.37 |
| delta_decode_10 | 96051 | 10.41 |
| delta_encode_100 | 4039 | 247.56 |
| delta_decode_100 | 10976 | 91.10 |
| delta_encode_500 | 856 | 1168.65 |
| delta_decode_500 | 2102 | 475.69 |
| delta_roundtrip_100 | 2942 | 339.94 |
| battery_budget_single_sample | 8851516 | 0.11 |
| battery_budget_60_samples | 291325 | 3.43 |
| battery_budget_heavy_drain | 148430 | 6.74 |
| carbon_trip_100_locations | 88484 | 11.30 |
| carbon_onLocation | 4153862 | 0.24 |
| carbon_setActivity | 9718379 | 0.10 |
| carbon_cumulative_report | 2799574 | 0.36 |
| persist_decider_location | 19654215 | 0.05 |
| persist_decider_geofence | 19357182 | 0.05 |
| config_fromMap | 412276 | 2.43 |
| config_toMap | 160494 | 6.23 |
| config_roundtrip | 114816 | 8.71 |
| state_fromMap | 389659 | 2.57 |
| state_toMap | 151879 | 6.58 |
| route_context_toMap | 3118267 | 0.32 |
| route_context_fromMap | 2395307 | 0.42 |
| route_context_roundtrip | 1451617 | 0.69 |
| sync_body_context_toMap_50 | 8324859 | 0.12 |
| sync_body_context_fromMap_50 | 22871 | 43.72 |
| http_config_ssl_toMap | 764927 | 1.31 |
| http_config_ssl_fromMap | 1429321 | 0.70 |
| http_config_ssl_roundtrip | 507057 | 1.97 |


### 2026-03-26 — Commit 0e24b9a

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7411262 | 0.13 |
| kalman_process_100_fixes | 94917 | 10.54 |
| kalman_process_1k_fixes | 9581 | 104.37 |
| kalman_reset | 6653212 | 0.15 |
| haversine_single | 7789887 | 0.13 |
| haversine_1k_pairs | 13973 | 71.56 |
| pip_4v | 12612252 | 0.08 |
| pip_10v | 9532492 | 0.10 |
| pip_50v | 3692419 | 0.27 |
| pip_100v | 2023663 | 0.49 |
| pip_500v | 421952 | 2.37 |
| geofence_eval_10_circular | 648292 | 1.54 |
| geofence_eval_100_circular | 69703 | 14.35 |
| geofence_eval_500_circular | 13362 | 74.84 |
| geofence_eval_10_polygon_6v | 414655 | 2.41 |
| geofence_eval_50_polygon_6v | 83052 | 12.04 |
| processor_1k_fixes | 8952 | 111.70 |
| processor_1k_adaptive | 8553 | 116.92 |
| trip_manager_5k_waypoints | 72 | 13951.55 |
| schedule_parse | 2878076 | 0.35 |
| schedule_matches | 130346 | 7.67 |
| schedule_isWithin_5_entries | 124768 | 8.01 |
| adaptive_compute | 13504177 | 0.07 |
| location_fromMap | 1682060 | 0.59 |
| location_toMap | 616520 | 1.62 |
| location_fromMap_toMap_roundtrip | 454715 | 2.20 |
| location_copyWithCoords | 12048173 | 0.08 |
| geofence_fromMap_circular | 4428969 | 0.23 |
| geofence_fromMap_polygon | 1615946 | 0.62 |
| delta_encode_10 | 29374 | 34.04 |
| delta_decode_10 | 91129 | 10.97 |
| delta_encode_100 | 3976 | 251.53 |
| delta_decode_100 | 10530 | 94.97 |
| delta_encode_500 | 857 | 1167.09 |
| delta_decode_500 | 1999 | 500.36 |
| delta_roundtrip_100 | 2907 | 344.00 |
| battery_budget_single_sample | 8814501 | 0.11 |
| battery_budget_60_samples | 290624 | 3.44 |
| battery_budget_heavy_drain | 147809 | 6.77 |
| carbon_trip_100_locations | 88976 | 11.24 |
| carbon_onLocation | 4185376 | 0.24 |
| carbon_setActivity | 9823410 | 0.10 |
| carbon_cumulative_report | 2699715 | 0.37 |
| persist_decider_location | 19892266 | 0.05 |
| persist_decider_geofence | 19783067 | 0.05 |
| config_fromMap | 392413 | 2.55 |
| config_toMap | 131705 | 7.59 |
| config_roundtrip | 97713 | 10.23 |
| state_fromMap | 373779 | 2.68 |
| state_toMap | 123375 | 8.11 |
| route_context_toMap | 3088580 | 0.32 |
| route_context_fromMap | 2360058 | 0.42 |
| route_context_roundtrip | 1380837 | 0.72 |
| sync_body_context_toMap_50 | 8359191 | 0.12 |
| sync_body_context_fromMap_50 | 21610 | 46.27 |
| http_config_ssl_toMap | 602766 | 1.66 |
| http_config_ssl_fromMap | 1418962 | 0.70 |
| http_config_ssl_roundtrip | 424983 | 2.35 |


### 2026-03-26 — Commit a59d2af

**Environment:** Dart 3.11.4, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7156729 | 0.14 |
| kalman_process_100_fixes | 93875 | 10.65 |
| kalman_process_1k_fixes | 9846 | 101.57 |
| kalman_reset | 6784491 | 0.15 |
| haversine_single | 9379163 | 0.11 |
| haversine_1k_pairs | 18698 | 53.48 |
| pip_4v | 12445119 | 0.08 |
| pip_10v | 9828132 | 0.10 |
| pip_50v | 3849186 | 0.26 |
| pip_100v | 2206364 | 0.45 |
| pip_500v | 444667 | 2.25 |
| geofence_eval_10_circular | 682929 | 1.46 |
| geofence_eval_100_circular | 78119 | 12.80 |
| geofence_eval_500_circular | 14730 | 67.89 |
| geofence_eval_10_polygon_6v | 429337 | 2.33 |
| geofence_eval_50_polygon_6v | 88392 | 11.31 |
| processor_1k_fixes | 10760 | 92.94 |
| processor_1k_adaptive | 10161 | 98.42 |
| trip_manager_5k_waypoints | 139 | 7183.83 |
| schedule_parse | 3190029 | 0.31 |
| schedule_matches | 251548 | 3.98 |
| schedule_isWithin_5_entries | 229844 | 4.35 |
| adaptive_compute | 13463247 | 0.07 |
| location_fromMap | 1755486 | 0.57 |
| location_toMap | 676522 | 1.48 |
| location_fromMap_toMap_roundtrip | 487794 | 2.05 |
| location_copyWithCoords | 11927153 | 0.08 |
| geofence_fromMap_circular | 4456464 | 0.22 |
| geofence_fromMap_polygon | 1668206 | 0.60 |
| delta_encode_10 | 31786 | 31.46 |
| delta_decode_10 | 94693 | 10.56 |
| delta_encode_100 | 4384 | 228.10 |
| delta_decode_100 | 11372 | 87.94 |
| delta_encode_500 | 839 | 1191.92 |
| delta_decode_500 | 2073 | 482.39 |
| delta_roundtrip_100 | 3248 | 307.91 |
| battery_budget_single_sample | 9068019 | 0.11 |
| battery_budget_60_samples | 293934 | 3.40 |
| battery_budget_heavy_drain | 154965 | 6.45 |
| carbon_trip_100_locations | 109987 | 9.09 |
| carbon_onLocation | 4452384 | 0.22 |
| carbon_setActivity | 10720658 | 0.09 |
| carbon_cumulative_report | 2816684 | 0.36 |
| persist_decider_location | 19975961 | 0.05 |
| persist_decider_geofence | 19899605 | 0.05 |
| config_fromMap | 432689 | 2.31 |
| config_toMap | 167981 | 5.95 |
| config_roundtrip | 118707 | 8.42 |
| state_fromMap | 415129 | 2.41 |
| state_toMap | 157497 | 6.35 |
| route_context_toMap | 3120627 | 0.32 |
| route_context_fromMap | 2498647 | 0.40 |
| route_context_roundtrip | 1454345 | 0.69 |
| sync_body_context_toMap_50 | 8546283 | 0.12 |
| sync_body_context_fromMap_50 | 23233 | 43.04 |
| http_config_ssl_toMap | 802613 | 1.25 |
| http_config_ssl_fromMap | 1496784 | 0.67 |
| http_config_ssl_roundtrip | 519424 | 1.93 |


### 2026-03-26 — Commit 8d530c7

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7128540 | 0.14 |
| kalman_process_100_fixes | 96007 | 10.42 |
| kalman_process_1k_fixes | 9624 | 103.91 |
| kalman_reset | 6446043 | 0.16 |
| haversine_single | 8075714 | 0.12 |
| haversine_1k_pairs | 13903 | 71.93 |
| pip_4v | 12422194 | 0.08 |
| pip_10v | 9702715 | 0.10 |
| pip_50v | 3830743 | 0.26 |
| pip_100v | 2123116 | 0.47 |
| pip_500v | 420105 | 2.38 |
| geofence_eval_10_circular | 639842 | 1.56 |
| geofence_eval_100_circular | 70038 | 14.28 |
| geofence_eval_500_circular | 13222 | 75.63 |
| geofence_eval_10_polygon_6v | 407318 | 2.46 |
| geofence_eval_50_polygon_6v | 81126 | 12.33 |
| processor_1k_fixes | 9007 | 111.03 |
| processor_1k_adaptive | 8523 | 117.33 |
| trip_manager_5k_waypoints | 66 | 15134.65 |
| schedule_parse | 2905467 | 0.34 |
| schedule_matches | 117872 | 8.48 |
| schedule_isWithin_5_entries | 111024 | 9.01 |
| adaptive_compute | 12730285 | 0.08 |
| location_fromMap | 1722806 | 0.58 |
| location_toMap | 664780 | 1.50 |
| location_fromMap_toMap_roundtrip | 486661 | 2.05 |
| location_copyWithCoords | 11517272 | 0.09 |
| geofence_fromMap_circular | 4449402 | 0.22 |
| geofence_fromMap_polygon | 1562740 | 0.64 |
| delta_encode_10 | 29471 | 33.93 |
| delta_decode_10 | 95437 | 10.48 |
| delta_encode_100 | 4078 | 245.21 |
| delta_decode_100 | 10721 | 93.28 |
| delta_encode_500 | 860 | 1163.06 |
| delta_decode_500 | 2090 | 478.52 |
| delta_roundtrip_100 | 2992 | 334.17 |
| battery_budget_single_sample | 9006270 | 0.11 |
| battery_budget_60_samples | 293741 | 3.40 |
| battery_budget_heavy_drain | 147258 | 6.79 |
| carbon_trip_100_locations | 89296 | 11.20 |
| carbon_onLocation | 4110192 | 0.24 |
| carbon_setActivity | 9591260 | 0.10 |
| carbon_cumulative_report | 2742290 | 0.36 |
| persist_decider_location | 19045993 | 0.05 |
| persist_decider_geofence | 18933025 | 0.05 |
| config_fromMap | 416506 | 2.40 |
| config_toMap | 154956 | 6.45 |
| config_roundtrip | 114833 | 8.71 |
| state_fromMap | 392746 | 2.55 |
| state_toMap | 147572 | 6.78 |
| route_context_toMap | 3066713 | 0.33 |
| route_context_fromMap | 2388223 | 0.42 |
| route_context_roundtrip | 1442855 | 0.69 |
| sync_body_context_toMap_50 | 8288575 | 0.12 |
| sync_body_context_fromMap_50 | 22947 | 43.58 |
| http_config_ssl_toMap | 769731 | 1.30 |
| http_config_ssl_fromMap | 1416782 | 0.71 |
| http_config_ssl_roundtrip | 495378 | 2.02 |


### 2026-03-26 — Commit df6535d

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7170550 | 0.14 |
| kalman_process_100_fixes | 94094 | 10.63 |
| kalman_process_1k_fixes | 9386 | 106.54 |
| kalman_reset | 6745061 | 0.15 |
| haversine_single | 7996069 | 0.13 |
| haversine_1k_pairs | 13804 | 72.44 |
| pip_4v | 13178280 | 0.08 |
| pip_10v | 9943368 | 0.10 |
| pip_50v | 3711958 | 0.27 |
| pip_100v | 2044493 | 0.49 |
| pip_500v | 417110 | 2.40 |
| geofence_eval_10_circular | 639447 | 1.56 |
| geofence_eval_100_circular | 68316 | 14.64 |
| geofence_eval_500_circular | 13373 | 74.78 |
| geofence_eval_10_polygon_6v | 410430 | 2.44 |
| geofence_eval_50_polygon_6v | 81619 | 12.25 |
| processor_1k_fixes | 8985 | 111.29 |
| processor_1k_adaptive | 8272 | 120.88 |
| trip_manager_5k_waypoints | 73 | 13753.10 |
| schedule_parse | 2755250 | 0.36 |
| schedule_matches | 131261 | 7.62 |
| schedule_isWithin_5_entries | 124326 | 8.04 |
| adaptive_compute | 13426226 | 0.07 |
| location_fromMap | 1712829 | 0.58 |
| location_toMap | 671095 | 1.49 |
| location_fromMap_toMap_roundtrip | 476776 | 2.10 |
| location_copyWithCoords | 11967848 | 0.08 |
| geofence_fromMap_circular | 4431889 | 0.23 |
| geofence_fromMap_polygon | 1573189 | 0.64 |
| delta_encode_10 | 29466 | 33.94 |
| delta_decode_10 | 98989 | 10.10 |
| delta_encode_100 | 4022 | 248.64 |
| delta_decode_100 | 11242 | 88.95 |
| delta_encode_500 | 853 | 1172.78 |
| delta_decode_500 | 2134 | 468.53 |
| delta_roundtrip_100 | 2946 | 339.41 |
| battery_budget_single_sample | 8906719 | 0.11 |
| battery_budget_60_samples | 286267 | 3.49 |
| battery_budget_heavy_drain | 145777 | 6.86 |
| carbon_trip_100_locations | 89916 | 11.12 |
| carbon_onLocation | 4127319 | 0.24 |
| carbon_setActivity | 9803697 | 0.10 |
| carbon_cumulative_report | 2742064 | 0.36 |
| persist_decider_location | 19803473 | 0.05 |
| persist_decider_geofence | 19930519 | 0.05 |
| config_fromMap | 420287 | 2.38 |
| config_toMap | 160933 | 6.21 |
| config_roundtrip | 114612 | 8.73 |
| state_fromMap | 398795 | 2.51 |
| state_toMap | 149984 | 6.67 |
| route_context_toMap | 3143279 | 0.32 |
| route_context_fromMap | 2341627 | 0.43 |
| route_context_roundtrip | 1447667 | 0.69 |
| sync_body_context_toMap_50 | 8309397 | 0.12 |
| sync_body_context_fromMap_50 | 22771 | 43.92 |
| http_config_ssl_toMap | 781832 | 1.28 |
| http_config_ssl_fromMap | 1411443 | 0.71 |
| http_config_ssl_roundtrip | 508614 | 1.97 |


### 2026-03-26 — Commit ba2c7b0

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7413995 | 0.13 |
| kalman_process_100_fixes | 94803 | 10.55 |
| kalman_process_1k_fixes | 9624 | 103.91 |
| kalman_reset | 6668544 | 0.15 |
| haversine_single | 8105770 | 0.12 |
| haversine_1k_pairs | 13784 | 72.55 |
| pip_4v | 13413204 | 0.07 |
| pip_10v | 9498395 | 0.11 |
| pip_50v | 3754684 | 0.27 |
| pip_100v | 2027996 | 0.49 |
| pip_500v | 415656 | 2.41 |
| geofence_eval_10_circular | 646549 | 1.55 |
| geofence_eval_100_circular | 70516 | 14.18 |
| geofence_eval_500_circular | 13661 | 73.20 |
| geofence_eval_10_polygon_6v | 417297 | 2.40 |
| geofence_eval_50_polygon_6v | 83920 | 11.92 |
| processor_1k_fixes | 9006 | 111.04 |
| processor_1k_adaptive | 8574 | 116.63 |
| trip_manager_5k_waypoints | 66 | 15092.38 |
| schedule_parse | 2880423 | 0.35 |
| schedule_matches | 118919 | 8.41 |
| schedule_isWithin_5_entries | 114065 | 8.77 |
| adaptive_compute | 14045394 | 0.07 |
| location_fromMap | 1718882 | 0.58 |
| location_toMap | 653825 | 1.53 |
| location_fromMap_toMap_roundtrip | 473096 | 2.11 |
| location_copyWithCoords | 12303206 | 0.08 |
| geofence_fromMap_circular | 4437745 | 0.23 |
| geofence_fromMap_polygon | 1575260 | 0.63 |
| delta_encode_10 | 29315 | 34.11 |
| delta_decode_10 | 95479 | 10.47 |
| delta_encode_100 | 3933 | 254.29 |
| delta_decode_100 | 10790 | 92.68 |
| delta_encode_500 | 795 | 1258.32 |
| delta_decode_500 | 2316 | 431.82 |
| delta_roundtrip_100 | 2934 | 340.88 |
| battery_budget_single_sample | 9107342 | 0.11 |
| battery_budget_60_samples | 292509 | 3.42 |
| battery_budget_heavy_drain | 147662 | 6.77 |
| carbon_trip_100_locations | 88424 | 11.31 |
| carbon_onLocation | 4095391 | 0.24 |
| carbon_setActivity | 9885105 | 0.10 |
| carbon_cumulative_report | 2662987 | 0.38 |
| persist_decider_location | 19874772 | 0.05 |
| persist_decider_geofence | 19763707 | 0.05 |
| config_fromMap | 424788 | 2.35 |
| config_toMap | 144842 | 6.90 |
| config_roundtrip | 107311 | 9.32 |
| state_fromMap | 408771 | 2.45 |
| state_toMap | 139795 | 7.15 |
| route_context_toMap | 2980853 | 0.34 |
| route_context_fromMap | 2195359 | 0.46 |
| route_context_roundtrip | 1320508 | 0.76 |
| sync_body_context_toMap_50 | 8302344 | 0.12 |
| sync_body_context_fromMap_50 | 22945 | 43.58 |
| http_config_ssl_toMap | 731940 | 1.37 |
| http_config_ssl_fromMap | 1402698 | 0.71 |
| http_config_ssl_roundtrip | 486306 | 2.06 |


### 2026-03-26 — Commit b84b34f

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7475116 | 0.13 |
| kalman_process_100_fixes | 94252 | 10.61 |
| kalman_process_1k_fixes | 9544 | 104.78 |
| kalman_reset | 6953331 | 0.14 |
| haversine_single | 7979192 | 0.13 |
| haversine_1k_pairs | 13983 | 71.52 |
| pip_4v | 13045125 | 0.08 |
| pip_10v | 9865592 | 0.10 |
| pip_50v | 3884720 | 0.26 |
| pip_100v | 2106531 | 0.47 |
| pip_500v | 420442 | 2.38 |
| geofence_eval_10_circular | 633622 | 1.58 |
| geofence_eval_100_circular | 70170 | 14.25 |
| geofence_eval_500_circular | 13392 | 74.67 |
| geofence_eval_10_polygon_6v | 412503 | 2.42 |
| geofence_eval_50_polygon_6v | 83500 | 11.98 |
| processor_1k_fixes | 8933 | 111.95 |
| processor_1k_adaptive | 8473 | 118.03 |
| trip_manager_5k_waypoints | 65 | 15292.52 |
| schedule_parse | 2888594 | 0.35 |
| schedule_matches | 118380 | 8.45 |
| schedule_isWithin_5_entries | 110854 | 9.02 |
| adaptive_compute | 13967899 | 0.07 |
| location_fromMap | 1723073 | 0.58 |
| location_toMap | 613999 | 1.63 |
| location_fromMap_toMap_roundtrip | 455355 | 2.20 |
| location_copyWithCoords | 12168218 | 0.08 |
| geofence_fromMap_circular | 4399473 | 0.23 |
| geofence_fromMap_polygon | 1538006 | 0.65 |
| delta_encode_10 | 29045 | 34.43 |
| delta_decode_10 | 94184 | 10.62 |
| delta_encode_100 | 4065 | 246.02 |
| delta_decode_100 | 10635 | 94.03 |
| delta_encode_500 | 809 | 1236.38 |
| delta_decode_500 | 2283 | 438.06 |
| delta_roundtrip_100 | 2967 | 337.08 |
| battery_budget_single_sample | 9150355 | 0.11 |
| battery_budget_60_samples | 293093 | 3.41 |
| battery_budget_heavy_drain | 148135 | 6.75 |
| carbon_trip_100_locations | 90643 | 11.03 |
| carbon_onLocation | 4024681 | 0.25 |
| carbon_setActivity | 9828244 | 0.10 |
| carbon_cumulative_report | 2666866 | 0.37 |
| persist_decider_location | 19950413 | 0.05 |
| persist_decider_geofence | 19902613 | 0.05 |
| config_fromMap | 384640 | 2.60 |
| config_toMap | 129735 | 7.71 |
| config_roundtrip | 98868 | 10.11 |
| state_fromMap | 398691 | 2.51 |
| state_toMap | 123663 | 8.09 |
| route_context_toMap | 3019702 | 0.33 |
| route_context_fromMap | 2343473 | 0.43 |
| route_context_roundtrip | 1401456 | 0.71 |
| sync_body_context_toMap_50 | 7976211 | 0.13 |
| sync_body_context_fromMap_50 | 21697 | 46.09 |
| http_config_ssl_toMap | 587980 | 1.70 |
| http_config_ssl_fromMap | 1447606 | 0.69 |
| http_config_ssl_roundtrip | 413673 | 2.42 |


### 2026-03-26 — Commit 14051b8

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7125301 | 0.14 |
| kalman_process_100_fixes | 95005 | 10.53 |
| kalman_process_1k_fixes | 9529 | 104.94 |
| kalman_reset | 6956628 | 0.14 |
| haversine_single | 8096132 | 0.12 |
| haversine_1k_pairs | 13570 | 73.69 |
| pip_4v | 13502905 | 0.07 |
| pip_10v | 10205346 | 0.10 |
| pip_50v | 3916581 | 0.26 |
| pip_100v | 2183170 | 0.46 |
| pip_500v | 426712 | 2.34 |
| geofence_eval_10_circular | 614183 | 1.63 |
| geofence_eval_100_circular | 67699 | 14.77 |
| geofence_eval_500_circular | 12810 | 78.06 |
| geofence_eval_10_polygon_6v | 400782 | 2.50 |
| geofence_eval_50_polygon_6v | 80966 | 12.35 |
| processor_1k_fixes | 8992 | 111.21 |
| processor_1k_adaptive | 8501 | 117.63 |
| trip_manager_5k_waypoints | 66 | 15218.58 |
| schedule_parse | 2926729 | 0.34 |
| schedule_matches | 118260 | 8.46 |
| schedule_isWithin_5_entries | 112204 | 8.91 |
| adaptive_compute | 13750384 | 0.07 |
| location_fromMap | 1670677 | 0.60 |
| location_toMap | 666809 | 1.50 |
| location_fromMap_toMap_roundtrip | 478644 | 2.09 |
| location_copyWithCoords | 12443062 | 0.08 |
| geofence_fromMap_circular | 4109204 | 0.24 |
| geofence_fromMap_polygon | 1565104 | 0.64 |
| delta_encode_10 | 29480 | 33.92 |
| delta_decode_10 | 97430 | 10.26 |
| delta_encode_100 | 4229 | 236.45 |
| delta_decode_100 | 11465 | 87.22 |
| delta_encode_500 | 859 | 1164.12 |
| delta_decode_500 | 2203 | 453.98 |
| delta_roundtrip_100 | 3008 | 332.40 |
| battery_budget_single_sample | 9036617 | 0.11 |
| battery_budget_60_samples | 285877 | 3.50 |
| battery_budget_heavy_drain | 145497 | 6.87 |
| carbon_trip_100_locations | 92750 | 10.78 |
| carbon_onLocation | 3944879 | 0.25 |
| carbon_setActivity | 9623587 | 0.10 |
| carbon_cumulative_report | 2737784 | 0.37 |
| persist_decider_location | 19528513 | 0.05 |
| persist_decider_geofence | 19503000 | 0.05 |
| config_fromMap | 419905 | 2.38 |
| config_toMap | 157866 | 6.33 |
| config_roundtrip | 112792 | 8.87 |
| state_fromMap | 382461 | 2.61 |
| state_toMap | 148466 | 6.74 |
| route_context_toMap | 3080300 | 0.32 |
| route_context_fromMap | 2428831 | 0.41 |
| route_context_roundtrip | 1468165 | 0.68 |
| sync_body_context_toMap_50 | 8536861 | 0.12 |
| sync_body_context_fromMap_50 | 22747 | 43.96 |
| http_config_ssl_toMap | 761455 | 1.31 |
| http_config_ssl_fromMap | 1388917 | 0.72 |
| http_config_ssl_roundtrip | 503725 | 1.99 |


### 2026-03-26 — Commit 84ccb61

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7279416 | 0.14 |
| kalman_process_100_fixes | 94608 | 10.57 |
| kalman_process_1k_fixes | 9486 | 105.42 |
| kalman_reset | 6856831 | 0.15 |
| haversine_single | 8044249 | 0.12 |
| haversine_1k_pairs | 13752 | 72.72 |
| pip_4v | 13059424 | 0.08 |
| pip_10v | 9883635 | 0.10 |
| pip_50v | 3742151 | 0.27 |
| pip_100v | 2059114 | 0.49 |
| pip_500v | 424034 | 2.36 |
| geofence_eval_10_circular | 627293 | 1.59 |
| geofence_eval_100_circular | 69931 | 14.30 |
| geofence_eval_500_circular | 13390 | 74.68 |
| geofence_eval_10_polygon_6v | 423749 | 2.36 |
| geofence_eval_50_polygon_6v | 85150 | 11.74 |
| processor_1k_fixes | 8982 | 111.33 |
| processor_1k_adaptive | 8483 | 117.88 |
| trip_manager_5k_waypoints | 73 | 13715.98 |
| schedule_parse | 2897463 | 0.35 |
| schedule_matches | 131615 | 7.60 |
| schedule_isWithin_5_entries | 124776 | 8.01 |
| adaptive_compute | 13245520 | 0.08 |
| location_fromMap | 1662483 | 0.60 |
| location_toMap | 668275 | 1.50 |
| location_fromMap_toMap_roundtrip | 491347 | 2.04 |
| location_copyWithCoords | 12095800 | 0.08 |
| geofence_fromMap_circular | 4487646 | 0.22 |
| geofence_fromMap_polygon | 1577095 | 0.63 |
| delta_encode_10 | 29175 | 34.28 |
| delta_decode_10 | 96681 | 10.34 |
| delta_encode_100 | 4073 | 245.53 |
| delta_decode_100 | 10848 | 92.18 |
| delta_encode_500 | 845 | 1183.48 |
| delta_decode_500 | 2124 | 470.80 |
| delta_roundtrip_100 | 2992 | 334.21 |
| battery_budget_single_sample | 9025340 | 0.11 |
| battery_budget_60_samples | 294766 | 3.39 |
| battery_budget_heavy_drain | 149038 | 6.71 |
| carbon_trip_100_locations | 90484 | 11.05 |
| carbon_onLocation | 4113840 | 0.24 |
| carbon_setActivity | 9763951 | 0.10 |
| carbon_cumulative_report | 2735927 | 0.37 |
| persist_decider_location | 19939399 | 0.05 |
| persist_decider_geofence | 20137204 | 0.05 |
| config_fromMap | 429536 | 2.33 |
| config_toMap | 159751 | 6.26 |
| config_roundtrip | 115684 | 8.64 |
| state_fromMap | 405994 | 2.46 |
| state_toMap | 149039 | 6.71 |
| route_context_toMap | 3030942 | 0.33 |
| route_context_fromMap | 2321110 | 0.43 |
| route_context_roundtrip | 1435033 | 0.70 |
| sync_body_context_toMap_50 | 8377757 | 0.12 |
| sync_body_context_fromMap_50 | 23024 | 43.43 |
| http_config_ssl_toMap | 773197 | 1.29 |
| http_config_ssl_fromMap | 1453354 | 0.69 |
| http_config_ssl_roundtrip | 505830 | 1.98 |


### 2026-03-26 — Commit f282818

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7301379 | 0.14 |
| kalman_process_100_fixes | 97033 | 10.31 |
| kalman_process_1k_fixes | 9604 | 104.13 |
| kalman_reset | 6762180 | 0.15 |
| haversine_single | 8020659 | 0.12 |
| haversine_1k_pairs | 13799 | 72.47 |
| pip_4v | 13273899 | 0.08 |
| pip_10v | 10136616 | 0.10 |
| pip_50v | 3907170 | 0.26 |
| pip_100v | 2077390 | 0.48 |
| pip_500v | 419039 | 2.39 |
| geofence_eval_10_circular | 632710 | 1.58 |
| geofence_eval_100_circular | 69133 | 14.46 |
| geofence_eval_500_circular | 13355 | 74.88 |
| geofence_eval_10_polygon_6v | 413757 | 2.42 |
| geofence_eval_50_polygon_6v | 83555 | 11.97 |
| processor_1k_fixes | 8975 | 111.42 |
| processor_1k_adaptive | 8526 | 117.29 |
| trip_manager_5k_waypoints | 72 | 13887.85 |
| schedule_parse | 2853332 | 0.35 |
| schedule_matches | 128523 | 7.78 |
| schedule_isWithin_5_entries | 122442 | 8.17 |
| adaptive_compute | 12934725 | 0.08 |
| location_fromMap | 1696426 | 0.59 |
| location_toMap | 669800 | 1.49 |
| location_fromMap_toMap_roundtrip | 482473 | 2.07 |
| location_copyWithCoords | 12049607 | 0.08 |
| geofence_fromMap_circular | 4450076 | 0.22 |
| geofence_fromMap_polygon | 1474881 | 0.68 |
| delta_encode_10 | 28912 | 34.59 |
| delta_decode_10 | 95442 | 10.48 |
| delta_encode_100 | 4004 | 249.75 |
| delta_decode_100 | 10802 | 92.57 |
| delta_encode_500 | 845 | 1183.02 |
| delta_decode_500 | 2042 | 489.71 |
| delta_roundtrip_100 | 2895 | 345.47 |
| battery_budget_single_sample | 8973049 | 0.11 |
| battery_budget_60_samples | 288629 | 3.46 |
| battery_budget_heavy_drain | 147087 | 6.80 |
| carbon_trip_100_locations | 90907 | 11.00 |
| carbon_onLocation | 4232173 | 0.24 |
| carbon_setActivity | 9792519 | 0.10 |
| carbon_cumulative_report | 2767787 | 0.36 |
| persist_decider_location | 19717200 | 0.05 |
| persist_decider_geofence | 20054913 | 0.05 |
| config_fromMap | 424551 | 2.36 |
| config_toMap | 157867 | 6.33 |
| config_roundtrip | 114149 | 8.76 |
| state_fromMap | 406389 | 2.46 |
| state_toMap | 148539 | 6.73 |
| route_context_toMap | 3087824 | 0.32 |
| route_context_fromMap | 2357001 | 0.42 |
| route_context_roundtrip | 1435371 | 0.70 |
| sync_body_context_toMap_50 | 8506584 | 0.12 |
| sync_body_context_fromMap_50 | 23077 | 43.33 |
| http_config_ssl_toMap | 778354 | 1.28 |
| http_config_ssl_fromMap | 1389440 | 0.72 |
| http_config_ssl_roundtrip | 502175 | 1.99 |


### 2026-03-26 — Commit e02708f

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7394998 | 0.14 |
| kalman_process_100_fixes | 96517 | 10.36 |
| kalman_process_1k_fixes | 9477 | 105.51 |
| kalman_reset | 7023301 | 0.14 |
| haversine_single | 9406591 | 0.11 |
| haversine_1k_pairs | 18775 | 53.26 |
| pip_4v | 13561316 | 0.07 |
| pip_10v | 10054612 | 0.10 |
| pip_50v | 4012469 | 0.25 |
| pip_100v | 2188070 | 0.46 |
| pip_500v | 440962 | 2.27 |
| geofence_eval_10_circular | 668116 | 1.50 |
| geofence_eval_100_circular | 76084 | 13.14 |
| geofence_eval_500_circular | 14572 | 68.63 |
| geofence_eval_10_polygon_6v | 437652 | 2.28 |
| geofence_eval_50_polygon_6v | 88556 | 11.29 |
| processor_1k_fixes | 10800 | 92.59 |
| processor_1k_adaptive | 10152 | 98.50 |
| trip_manager_5k_waypoints | 132 | 7576.31 |
| schedule_parse | 3077067 | 0.32 |
| schedule_matches | 257068 | 3.89 |
| schedule_isWithin_5_entries | 229092 | 4.37 |
| adaptive_compute | 14148999 | 0.07 |
| location_fromMap | 1646614 | 0.61 |
| location_toMap | 600651 | 1.66 |
| location_fromMap_toMap_roundtrip | 448797 | 2.23 |
| location_copyWithCoords | 11223203 | 0.09 |
| geofence_fromMap_circular | 4183732 | 0.24 |
| geofence_fromMap_polygon | 1480363 | 0.68 |
| delta_encode_10 | 31681 | 31.56 |
| delta_decode_10 | 87598 | 11.42 |
| delta_encode_100 | 4123 | 242.56 |
| delta_decode_100 | 10420 | 95.97 |
| delta_encode_500 | 769 | 1300.76 |
| delta_decode_500 | 1811 | 552.32 |
| delta_roundtrip_100 | 2973 | 336.33 |
| battery_budget_single_sample | 8470371 | 0.12 |
| battery_budget_60_samples | 293517 | 3.41 |
| battery_budget_heavy_drain | 148548 | 6.73 |
| carbon_trip_100_locations | 104326 | 9.59 |
| carbon_onLocation | 4368888 | 0.23 |
| carbon_setActivity | 10146125 | 0.10 |
| carbon_cumulative_report | 2592922 | 0.39 |
| persist_decider_location | 22285763 | 0.04 |
| persist_decider_geofence | 22120580 | 0.05 |
| config_fromMap | 400011 | 2.50 |
| config_toMap | 157093 | 6.37 |
| config_roundtrip | 111085 | 9.00 |
| state_fromMap | 381122 | 2.62 |
| state_toMap | 145883 | 6.85 |
| route_context_toMap | 2927426 | 0.34 |
| route_context_fromMap | 2248473 | 0.44 |
| route_context_roundtrip | 1303083 | 0.77 |
| sync_body_context_toMap_50 | 8855376 | 0.11 |
| sync_body_context_fromMap_50 | 21939 | 45.58 |
| http_config_ssl_toMap | 754401 | 1.33 |
| http_config_ssl_fromMap | 1316365 | 0.76 |
| http_config_ssl_roundtrip | 478404 | 2.09 |


### 2026-03-26 — Commit 7412007

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7040022 | 0.14 |
| kalman_process_100_fixes | 96308 | 10.38 |
| kalman_process_1k_fixes | 9682 | 103.28 |
| kalman_reset | 6808439 | 0.15 |
| haversine_single | 7716926 | 0.13 |
| haversine_1k_pairs | 13960 | 71.63 |
| pip_4v | 13565812 | 0.07 |
| pip_10v | 10261067 | 0.10 |
| pip_50v | 3872003 | 0.26 |
| pip_100v | 2148775 | 0.47 |
| pip_500v | 420591 | 2.38 |
| geofence_eval_10_circular | 631922 | 1.58 |
| geofence_eval_100_circular | 69063 | 14.48 |
| geofence_eval_500_circular | 13356 | 74.87 |
| geofence_eval_10_polygon_6v | 421297 | 2.37 |
| geofence_eval_50_polygon_6v | 84399 | 11.85 |
| processor_1k_fixes | 8950 | 111.73 |
| processor_1k_adaptive | 8592 | 116.39 |
| trip_manager_5k_waypoints | 66 | 15154.26 |
| schedule_parse | 2919654 | 0.34 |
| schedule_matches | 119299 | 8.38 |
| schedule_isWithin_5_entries | 113468 | 8.81 |
| adaptive_compute | 13683634 | 0.07 |
| location_fromMap | 1706667 | 0.59 |
| location_toMap | 688099 | 1.45 |
| location_fromMap_toMap_roundtrip | 491483 | 2.03 |
| location_copyWithCoords | 12467188 | 0.08 |
| geofence_fromMap_circular | 4538418 | 0.22 |
| geofence_fromMap_polygon | 1574741 | 0.64 |
| delta_encode_10 | 30305 | 33.00 |
| delta_decode_10 | 98205 | 10.18 |
| delta_encode_100 | 4131 | 242.10 |
| delta_decode_100 | 11018 | 90.76 |
| delta_encode_500 | 855 | 1169.18 |
| delta_decode_500 | 2329 | 429.31 |
| delta_roundtrip_100 | 2994 | 333.99 |
| battery_budget_single_sample | 9109179 | 0.11 |
| battery_budget_60_samples | 292075 | 3.42 |
| battery_budget_heavy_drain | 147432 | 6.78 |
| carbon_trip_100_locations | 89678 | 11.15 |
| carbon_onLocation | 4115854 | 0.24 |
| carbon_setActivity | 9950658 | 0.10 |
| carbon_cumulative_report | 2796910 | 0.36 |
| persist_decider_location | 20106087 | 0.05 |
| persist_decider_geofence | 20204779 | 0.05 |
| config_fromMap | 443912 | 2.25 |
| config_toMap | 159740 | 6.26 |
| config_roundtrip | 116457 | 8.59 |
| state_fromMap | 417878 | 2.39 |
| state_toMap | 149785 | 6.68 |
| route_context_toMap | 3113093 | 0.32 |
| route_context_fromMap | 2348722 | 0.43 |
| route_context_roundtrip | 1394174 | 0.72 |
| sync_body_context_toMap_50 | 8553522 | 0.12 |
| sync_body_context_fromMap_50 | 23304 | 42.91 |
| http_config_ssl_toMap | 780842 | 1.28 |
| http_config_ssl_fromMap | 1438372 | 0.70 |
| http_config_ssl_roundtrip | 503766 | 1.99 |


### 2026-03-26 — Commit b488d93

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7364948 | 0.14 |
| kalman_process_100_fixes | 96198 | 10.40 |
| kalman_process_1k_fixes | 9722 | 102.86 |
| kalman_reset | 6841652 | 0.15 |
| haversine_single | 7943032 | 0.13 |
| haversine_1k_pairs | 13945 | 71.71 |
| pip_4v | 13545589 | 0.07 |
| pip_10v | 10223479 | 0.10 |
| pip_50v | 3923402 | 0.25 |
| pip_100v | 2078839 | 0.48 |
| pip_500v | 410933 | 2.43 |
| geofence_eval_10_circular | 641532 | 1.56 |
| geofence_eval_100_circular | 69464 | 14.40 |
| geofence_eval_500_circular | 13479 | 74.19 |
| geofence_eval_10_polygon_6v | 418307 | 2.39 |
| geofence_eval_50_polygon_6v | 82998 | 12.05 |
| processor_1k_fixes | 9008 | 111.01 |
| processor_1k_adaptive | 8581 | 116.54 |
| trip_manager_5k_waypoints | 66 | 15105.14 |
| schedule_parse | 2841582 | 0.35 |
| schedule_matches | 118514 | 8.44 |
| schedule_isWithin_5_entries | 110452 | 9.05 |
| adaptive_compute | 13339164 | 0.07 |
| location_fromMap | 1727598 | 0.58 |
| location_toMap | 664724 | 1.50 |
| location_fromMap_toMap_roundtrip | 484701 | 2.06 |
| location_copyWithCoords | 11902858 | 0.08 |
| geofence_fromMap_circular | 4561772 | 0.22 |
| geofence_fromMap_polygon | 1573528 | 0.64 |
| delta_encode_10 | 29341 | 34.08 |
| delta_decode_10 | 97428 | 10.26 |
| delta_encode_100 | 4019 | 248.83 |
| delta_decode_100 | 10762 | 92.92 |
| delta_encode_500 | 820 | 1219.20 |
| delta_decode_500 | 2279 | 438.72 |
| delta_roundtrip_100 | 2932 | 341.10 |
| battery_budget_single_sample | 9041990 | 0.11 |
| battery_budget_60_samples | 289367 | 3.46 |
| battery_budget_heavy_drain | 148473 | 6.74 |
| carbon_trip_100_locations | 90846 | 11.01 |
| carbon_onLocation | 4189348 | 0.24 |
| carbon_setActivity | 9859488 | 0.10 |
| carbon_cumulative_report | 2703339 | 0.37 |
| persist_decider_location | 20080699 | 0.05 |
| persist_decider_geofence | 20028798 | 0.05 |
| config_fromMap | 410800 | 2.43 |
| config_toMap | 156698 | 6.38 |
| config_roundtrip | 113695 | 8.80 |
| state_fromMap | 390969 | 2.56 |
| state_toMap | 148582 | 6.73 |
| route_context_toMap | 3062031 | 0.33 |
| route_context_fromMap | 2430127 | 0.41 |
| route_context_roundtrip | 1384560 | 0.72 |
| sync_body_context_toMap_50 | 8399579 | 0.12 |
| sync_body_context_fromMap_50 | 22924 | 43.62 |
| http_config_ssl_toMap | 760909 | 1.31 |
| http_config_ssl_fromMap | 1437885 | 0.70 |
| http_config_ssl_roundtrip | 500551 | 2.00 |


### 2026-03-26 — Commit 259bb3a

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7354805 | 0.14 |
| kalman_process_100_fixes | 96379 | 10.38 |
| kalman_process_1k_fixes | 9626 | 103.89 |
| kalman_reset | 6839347 | 0.15 |
| haversine_single | 8123594 | 0.12 |
| haversine_1k_pairs | 13990 | 71.48 |
| pip_4v | 12556303 | 0.08 |
| pip_10v | 10099640 | 0.10 |
| pip_50v | 3929518 | 0.25 |
| pip_100v | 2072321 | 0.48 |
| pip_500v | 419438 | 2.38 |
| geofence_eval_10_circular | 642251 | 1.56 |
| geofence_eval_100_circular | 69934 | 14.30 |
| geofence_eval_500_circular | 13466 | 74.26 |
| geofence_eval_10_polygon_6v | 415604 | 2.41 |
| geofence_eval_50_polygon_6v | 85218 | 11.73 |
| processor_1k_fixes | 8945 | 111.79 |
| processor_1k_adaptive | 8490 | 117.78 |
| trip_manager_5k_waypoints | 66 | 15096.17 |
| schedule_parse | 2856648 | 0.35 |
| schedule_matches | 118494 | 8.44 |
| schedule_isWithin_5_entries | 112257 | 8.91 |
| adaptive_compute | 13268741 | 0.08 |
| location_fromMap | 1691611 | 0.59 |
| location_toMap | 677061 | 1.48 |
| location_fromMap_toMap_roundtrip | 488543 | 2.05 |
| location_copyWithCoords | 12331951 | 0.08 |
| geofence_fromMap_circular | 4529392 | 0.22 |
| geofence_fromMap_polygon | 1579275 | 0.63 |
| delta_encode_10 | 29569 | 33.82 |
| delta_decode_10 | 98653 | 10.14 |
| delta_encode_100 | 4116 | 242.96 |
| delta_decode_100 | 11268 | 88.74 |
| delta_encode_500 | 845 | 1183.81 |
| delta_decode_500 | 2123 | 471.00 |
| delta_roundtrip_100 | 2988 | 334.64 |
| battery_budget_single_sample | 9170088 | 0.11 |
| battery_budget_60_samples | 278546 | 3.59 |
| battery_budget_heavy_drain | 137236 | 7.29 |
| carbon_trip_100_locations | 90520 | 11.05 |
| carbon_onLocation | 4056588 | 0.25 |
| carbon_setActivity | 9760817 | 0.10 |
| carbon_cumulative_report | 2701873 | 0.37 |
| persist_decider_location | 20126442 | 0.05 |
| persist_decider_geofence | 20007173 | 0.05 |
| config_fromMap | 423816 | 2.36 |
| config_toMap | 157779 | 6.34 |
| config_roundtrip | 114186 | 8.76 |
| state_fromMap | 408954 | 2.45 |
| state_toMap | 150749 | 6.63 |
| route_context_toMap | 3027798 | 0.33 |
| route_context_fromMap | 2385239 | 0.42 |
| route_context_roundtrip | 1432152 | 0.70 |
| sync_body_context_toMap_50 | 8117679 | 0.12 |
| sync_body_context_fromMap_50 | 22865 | 43.74 |
| http_config_ssl_toMap | 770656 | 1.30 |
| http_config_ssl_fromMap | 1428198 | 0.70 |
| http_config_ssl_roundtrip | 506010 | 1.98 |


### 2026-03-26 — Commit 279d12f

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7154664 | 0.14 |
| kalman_process_100_fixes | 94789 | 10.55 |
| kalman_process_1k_fixes | 9334 | 107.13 |
| kalman_reset | 6659571 | 0.15 |
| haversine_single | 7947911 | 0.13 |
| haversine_1k_pairs | 13911 | 71.89 |
| pip_4v | 13210104 | 0.08 |
| pip_10v | 9816246 | 0.10 |
| pip_50v | 3781001 | 0.26 |
| pip_100v | 2063427 | 0.48 |
| pip_500v | 425361 | 2.35 |
| geofence_eval_10_circular | 639385 | 1.56 |
| geofence_eval_100_circular | 69261 | 14.44 |
| geofence_eval_500_circular | 13488 | 74.14 |
| geofence_eval_10_polygon_6v | 412232 | 2.43 |
| geofence_eval_50_polygon_6v | 82653 | 12.10 |
| processor_1k_fixes | 8789 | 113.78 |
| processor_1k_adaptive | 8361 | 119.60 |
| trip_manager_5k_waypoints | 72 | 13803.19 |
| schedule_parse | 2827409 | 0.35 |
| schedule_matches | 130074 | 7.69 |
| schedule_isWithin_5_entries | 125463 | 7.97 |
| adaptive_compute | 13194046 | 0.08 |
| location_fromMap | 1682535 | 0.59 |
| location_toMap | 668667 | 1.50 |
| location_fromMap_toMap_roundtrip | 486936 | 2.05 |
| location_copyWithCoords | 12268947 | 0.08 |
| geofence_fromMap_circular | 4428655 | 0.23 |
| geofence_fromMap_polygon | 1581299 | 0.63 |
| delta_encode_10 | 28898 | 34.60 |
| delta_decode_10 | 96121 | 10.40 |
| delta_encode_100 | 3894 | 256.82 |
| delta_decode_100 | 10705 | 93.42 |
| delta_encode_500 | 851 | 1175.41 |
| delta_decode_500 | 2048 | 488.37 |
| delta_roundtrip_100 | 2862 | 349.40 |
| battery_budget_single_sample | 9015606 | 0.11 |
| battery_budget_60_samples | 290258 | 3.45 |
| battery_budget_heavy_drain | 145575 | 6.87 |
| carbon_trip_100_locations | 88513 | 11.30 |
| carbon_onLocation | 3792150 | 0.26 |
| carbon_setActivity | 8292168 | 0.12 |
| carbon_cumulative_report | 2618538 | 0.38 |
| persist_decider_location | 19876304 | 0.05 |
| persist_decider_geofence | 19901179 | 0.05 |
| config_fromMap | 417351 | 2.40 |
| config_toMap | 154076 | 6.49 |
| config_roundtrip | 111390 | 8.98 |
| state_fromMap | 385687 | 2.59 |
| state_toMap | 147205 | 6.79 |
| route_context_toMap | 2962167 | 0.34 |
| route_context_fromMap | 2292238 | 0.44 |
| route_context_roundtrip | 1408452 | 0.71 |
| sync_body_context_toMap_50 | 7859296 | 0.13 |
| sync_body_context_fromMap_50 | 22699 | 44.05 |
| http_config_ssl_toMap | 758882 | 1.32 |
| http_config_ssl_fromMap | 1406723 | 0.71 |
| http_config_ssl_roundtrip | 487229 | 2.05 |


### 2026-03-26 — Commit 3d3324e

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7390515 | 0.14 |
| kalman_process_100_fixes | 94654 | 10.56 |
| kalman_process_1k_fixes | 9528 | 104.95 |
| kalman_reset | 6804395 | 0.15 |
| haversine_single | 8020725 | 0.12 |
| haversine_1k_pairs | 13932 | 71.78 |
| pip_4v | 13015930 | 0.08 |
| pip_10v | 10115192 | 0.10 |
| pip_50v | 3755347 | 0.27 |
| pip_100v | 1924032 | 0.52 |
| pip_500v | 418860 | 2.39 |
| geofence_eval_10_circular | 634042 | 1.58 |
| geofence_eval_100_circular | 70704 | 14.14 |
| geofence_eval_500_circular | 13557 | 73.76 |
| geofence_eval_10_polygon_6v | 415258 | 2.41 |
| geofence_eval_50_polygon_6v | 83245 | 12.01 |
| processor_1k_fixes | 8997 | 111.14 |
| processor_1k_adaptive | 8542 | 117.07 |
| trip_manager_5k_waypoints | 66 | 15050.69 |
| schedule_parse | 2882657 | 0.35 |
| schedule_matches | 119348 | 8.38 |
| schedule_isWithin_5_entries | 111180 | 8.99 |
| adaptive_compute | 12347261 | 0.08 |
| location_fromMap | 1700585 | 0.59 |
| location_toMap | 668642 | 1.50 |
| location_fromMap_toMap_roundtrip | 482869 | 2.07 |
| location_copyWithCoords | 12161271 | 0.08 |
| geofence_fromMap_circular | 4407009 | 0.23 |
| geofence_fromMap_polygon | 1605337 | 0.62 |
| delta_encode_10 | 29124 | 34.34 |
| delta_decode_10 | 96227 | 10.39 |
| delta_encode_100 | 4046 | 247.18 |
| delta_decode_100 | 10698 | 93.48 |
| delta_encode_500 | 841 | 1188.83 |
| delta_decode_500 | 2112 | 473.41 |
| delta_roundtrip_100 | 3023 | 330.83 |
| battery_budget_single_sample | 9180253 | 0.11 |
| battery_budget_60_samples | 291377 | 3.43 |
| battery_budget_heavy_drain | 147992 | 6.76 |
| carbon_trip_100_locations | 88097 | 11.35 |
| carbon_onLocation | 3603962 | 0.28 |
| carbon_setActivity | 8168467 | 0.12 |
| carbon_cumulative_report | 2591469 | 0.39 |
| persist_decider_location | 20048667 | 0.05 |
| persist_decider_geofence | 19902491 | 0.05 |
| config_fromMap | 423282 | 2.36 |
| config_toMap | 155931 | 6.41 |
| config_roundtrip | 113740 | 8.79 |
| state_fromMap | 401507 | 2.49 |
| state_toMap | 148806 | 6.72 |
| route_context_toMap | 3069987 | 0.33 |
| route_context_fromMap | 2355000 | 0.42 |
| route_context_roundtrip | 1428988 | 0.70 |
| sync_body_context_toMap_50 | 8035169 | 0.12 |
| sync_body_context_fromMap_50 | 22992 | 43.49 |
| http_config_ssl_toMap | 755486 | 1.32 |
| http_config_ssl_fromMap | 1462187 | 0.68 |
| http_config_ssl_roundtrip | 506306 | 1.98 |


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


### 2026-03-22 — Commit 0741aae

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7193974 | 0.14 |
| kalman_process_100_fixes | 95196 | 10.50 |
| kalman_process_1k_fixes | 9656 | 103.56 |
| kalman_reset | 6685727 | 0.15 |
| haversine_single | 8120798 | 0.12 |
| haversine_1k_pairs | 13821 | 72.35 |
| pip_4v | 12689382 | 0.08 |
| pip_10v | 9891689 | 0.10 |
| pip_50v | 3677994 | 0.27 |
| pip_100v | 2061908 | 0.48 |
| pip_500v | 422908 | 2.36 |
| geofence_eval_10_circular | 645312 | 1.55 |
| geofence_eval_100_circular | 70553 | 14.17 |
| geofence_eval_500_circular | 13537 | 73.87 |
| geofence_eval_10_polygon_6v | 412449 | 2.42 |
| geofence_eval_50_polygon_6v | 82537 | 12.12 |
| processor_1k_fixes | 9036 | 110.67 |
| processor_1k_adaptive | 7659 | 130.57 |
| trip_manager_5k_waypoints | 65 | 15306.52 |
| schedule_parse | 2786502 | 0.36 |
| schedule_matches | 119073 | 8.40 |
| schedule_isWithin_5_entries | 113314 | 8.83 |
| adaptive_compute | 9832614 | 0.10 |
| location_fromMap | 1725148 | 0.58 |
| location_toMap | 661848 | 1.51 |
| location_fromMap_toMap_roundtrip | 481504 | 2.08 |
| location_copyWithCoords | 12035188 | 0.08 |
| geofence_fromMap_circular | 4459512 | 0.22 |
| geofence_fromMap_polygon | 1603232 | 0.62 |
| delta_encode_10 | 29366 | 34.05 |
| delta_decode_10 | 96247 | 10.39 |
| delta_encode_100 | 4012 | 249.25 |
| delta_decode_100 | 10870 | 92.00 |
| delta_encode_500 | 861 | 1161.28 |
| delta_decode_500 | 2079 | 481.09 |
| delta_roundtrip_100 | 2923 | 342.06 |
| battery_budget_single_sample | 9365455 | 0.11 |
| battery_budget_60_samples | 255591 | 3.91 |
| battery_budget_heavy_drain | 128837 | 7.76 |
| carbon_trip_100_locations | 88805 | 11.26 |
| carbon_onLocation | 4127463 | 0.24 |
| carbon_setActivity | 9837600 | 0.10 |
| carbon_cumulative_report | 2738773 | 0.37 |
| persist_decider_location | 20094793 | 0.05 |
| persist_decider_geofence | 19889905 | 0.05 |
| config_fromMap | 423852 | 2.36 |
| config_toMap | 156879 | 6.37 |
| config_roundtrip | 112569 | 8.88 |
| state_fromMap | 395159 | 2.53 |
| state_toMap | 148550 | 6.73 |
| route_context_toMap | 3031934 | 0.33 |
| route_context_fromMap | 2330134 | 0.43 |
| route_context_roundtrip | 1410076 | 0.71 |
| sync_body_context_toMap_50 | 8084545 | 0.12 |
| sync_body_context_fromMap_50 | 23161 | 43.18 |
| http_config_ssl_toMap | 764668 | 1.31 |
| http_config_ssl_fromMap | 1418647 | 0.70 |
| http_config_ssl_roundtrip | 499684 | 2.00 |


### 2026-03-22 — Commit 601af87

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7185966 | 0.14 |
| kalman_process_100_fixes | 95998 | 10.42 |
| kalman_process_1k_fixes | 9559 | 104.62 |
| kalman_reset | 6905662 | 0.14 |
| haversine_single | 8071586 | 0.12 |
| haversine_1k_pairs | 13838 | 72.26 |
| pip_4v | 13363458 | 0.07 |
| pip_10v | 10135470 | 0.10 |
| pip_50v | 3719232 | 0.27 |
| pip_100v | 2079155 | 0.48 |
| pip_500v | 427699 | 2.34 |
| geofence_eval_10_circular | 651614 | 1.53 |
| geofence_eval_100_circular | 70877 | 14.11 |
| geofence_eval_500_circular | 13535 | 73.88 |
| geofence_eval_10_polygon_6v | 417348 | 2.40 |
| geofence_eval_50_polygon_6v | 84493 | 11.84 |
| processor_1k_fixes | 9038 | 110.64 |
| processor_1k_adaptive | 8505 | 117.58 |
| trip_manager_5k_waypoints | 66 | 15244.30 |
| schedule_parse | 2929925 | 0.34 |
| schedule_matches | 118614 | 8.43 |
| schedule_isWithin_5_entries | 113198 | 8.83 |
| adaptive_compute | 13406719 | 0.07 |
| location_fromMap | 1710517 | 0.58 |
| location_toMap | 644143 | 1.55 |
| location_fromMap_toMap_roundtrip | 465851 | 2.15 |
| location_copyWithCoords | 12224450 | 0.08 |
| geofence_fromMap_circular | 4509273 | 0.22 |
| geofence_fromMap_polygon | 1576089 | 0.63 |
| delta_encode_10 | 30048 | 33.28 |
| delta_decode_10 | 95697 | 10.45 |
| delta_encode_100 | 4050 | 246.91 |
| delta_decode_100 | 10840 | 92.25 |
| delta_encode_500 | 878 | 1138.60 |
| delta_decode_500 | 2083 | 480.08 |
| delta_roundtrip_100 | 2996 | 333.78 |
| battery_budget_single_sample | 9582739 | 0.10 |
| battery_budget_60_samples | 258071 | 3.87 |
| battery_budget_heavy_drain | 129316 | 7.73 |
| carbon_trip_100_locations | 89411 | 11.18 |
| carbon_onLocation | 4218273 | 0.24 |
| carbon_setActivity | 9936718 | 0.10 |
| carbon_cumulative_report | 2782890 | 0.36 |
| persist_decider_location | 20111022 | 0.05 |
| persist_decider_geofence | 20304729 | 0.05 |
| config_fromMap | 441077 | 2.27 |
| config_toMap | 141960 | 7.04 |
| config_roundtrip | 103758 | 9.64 |
| state_fromMap | 412579 | 2.42 |
| state_toMap | 133390 | 7.50 |
| route_context_toMap | 3138827 | 0.32 |
| route_context_fromMap | 2430498 | 0.41 |
| route_context_roundtrip | 1484099 | 0.67 |
| sync_body_context_toMap_50 | 8234192 | 0.12 |
| sync_body_context_fromMap_50 | 22974 | 43.53 |
| http_config_ssl_toMap | 617074 | 1.62 |
| http_config_ssl_fromMap | 1462629 | 0.68 |
| http_config_ssl_roundtrip | 441191 | 2.27 |


### 2026-03-21 — Commit b9458d9

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7140093 | 0.14 |
| kalman_process_100_fixes | 97422 | 10.26 |
| kalman_process_1k_fixes | 9865 | 101.37 |
| kalman_reset | 6805260 | 0.15 |
| haversine_single | 8097547 | 0.12 |
| haversine_1k_pairs | 14018 | 71.34 |
| pip_4v | 13444526 | 0.07 |
| pip_10v | 10043190 | 0.10 |
| pip_50v | 3730224 | 0.27 |
| pip_100v | 2096484 | 0.48 |
| pip_500v | 420858 | 2.38 |
| geofence_eval_10_circular | 625847 | 1.60 |
| geofence_eval_100_circular | 67975 | 14.71 |
| geofence_eval_500_circular | 13059 | 76.58 |
| geofence_eval_10_polygon_6v | 412387 | 2.42 |
| geofence_eval_50_polygon_6v | 84270 | 11.87 |
| processor_1k_fixes | 8980 | 111.35 |
| processor_1k_adaptive | 8504 | 117.59 |
| trip_manager_5k_waypoints | 66 | 15138.07 |
| schedule_parse | 2940134 | 0.34 |
| schedule_matches | 119622 | 8.36 |
| schedule_isWithin_5_entries | 113053 | 8.85 |
| adaptive_compute | 14187560 | 0.07 |
| location_fromMap | 1706945 | 0.59 |
| location_toMap | 678756 | 1.47 |
| location_fromMap_toMap_roundtrip | 485729 | 2.06 |
| location_copyWithCoords | 11921585 | 0.08 |
| geofence_fromMap_circular | 4519719 | 0.22 |
| geofence_fromMap_polygon | 1584218 | 0.63 |
| delta_encode_10 | 29058 | 34.41 |
| delta_decode_10 | 96151 | 10.40 |
| delta_encode_100 | 4014 | 249.12 |
| delta_decode_100 | 10753 | 93.00 |
| delta_encode_500 | 859 | 1164.46 |
| delta_decode_500 | 2295 | 435.73 |
| delta_roundtrip_100 | 2888 | 346.28 |
| battery_budget_single_sample | 9507987 | 0.11 |
| battery_budget_60_samples | 251514 | 3.98 |
| battery_budget_heavy_drain | 127409 | 7.85 |
| carbon_trip_100_locations | 89119 | 11.22 |
| carbon_onLocation | 4064985 | 0.25 |
| carbon_setActivity | 9749235 | 0.10 |
| carbon_cumulative_report | 2666519 | 0.38 |
| persist_decider_location | 20078560 | 0.05 |
| persist_decider_geofence | 20159185 | 0.05 |
| config_fromMap | 428808 | 2.33 |
| config_toMap | 157933 | 6.33 |
| config_roundtrip | 114506 | 8.73 |
| state_fromMap | 397392 | 2.52 |
| state_toMap | 147537 | 6.78 |
| route_context_toMap | 3114663 | 0.32 |
| route_context_fromMap | 2337675 | 0.43 |
| route_context_roundtrip | 1436040 | 0.70 |
| sync_body_context_toMap_50 | 8130689 | 0.12 |
| sync_body_context_fromMap_50 | 22918 | 43.63 |
| http_config_ssl_toMap | 772426 | 1.29 |
| http_config_ssl_fromMap | 1406127 | 0.71 |
| http_config_ssl_roundtrip | 495401 | 2.02 |


### 2026-03-20 — Commit 6d16805

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7374468 | 0.14 |
| kalman_process_100_fixes | 97268 | 10.28 |
| kalman_process_1k_fixes | 9368 | 106.75 |
| kalman_reset | 6858103 | 0.15 |
| haversine_single | 8206816 | 0.12 |
| haversine_1k_pairs | 13725 | 72.86 |
| pip_4v | 13410082 | 0.07 |
| pip_10v | 10147503 | 0.10 |
| pip_50v | 3722762 | 0.27 |
| pip_100v | 2056121 | 0.49 |
| pip_500v | 420971 | 2.38 |
| geofence_eval_10_circular | 651391 | 1.54 |
| geofence_eval_100_circular | 70922 | 14.10 |
| geofence_eval_500_circular | 13506 | 74.04 |
| geofence_eval_10_polygon_6v | 414030 | 2.42 |
| geofence_eval_50_polygon_6v | 85275 | 11.73 |
| processor_1k_fixes | 9062 | 110.35 |
| processor_1k_adaptive | 8532 | 117.20 |
| trip_manager_5k_waypoints | 66 | 15149.60 |
| schedule_parse | 2893689 | 0.35 |
| schedule_matches | 119077 | 8.40 |
| schedule_isWithin_5_entries | 110167 | 9.08 |
| adaptive_compute | 13702424 | 0.07 |
| location_fromMap | 1722778 | 0.58 |
| location_toMap | 683877 | 1.46 |
| location_fromMap_toMap_roundtrip | 495439 | 2.02 |
| location_copyWithCoords | 11877532 | 0.08 |
| geofence_fromMap_circular | 4523375 | 0.22 |
| geofence_fromMap_polygon | 1592413 | 0.63 |
| delta_encode_10 | 29586 | 33.80 |
| delta_decode_10 | 96377 | 10.38 |
| delta_encode_100 | 4085 | 244.81 |
| delta_decode_100 | 10871 | 91.99 |
| delta_encode_500 | 812 | 1231.71 |
| delta_decode_500 | 2101 | 475.98 |
| delta_roundtrip_100 | 3009 | 332.35 |
| battery_budget_single_sample | 9377547 | 0.11 |
| battery_budget_60_samples | 252850 | 3.95 |
| battery_budget_heavy_drain | 127437 | 7.85 |
| carbon_trip_100_locations | 90959 | 10.99 |
| carbon_onLocation | 4222924 | 0.24 |
| carbon_setActivity | 9970291 | 0.10 |
| carbon_cumulative_report | 2752379 | 0.36 |
| persist_decider_location | 20066831 | 0.05 |
| persist_decider_geofence | 20212288 | 0.05 |
| config_fromMap | 463181 | 2.16 |
| config_toMap | 161223 | 6.20 |
| config_roundtrip | 118837 | 8.41 |
| state_fromMap | 437923 | 2.28 |
| state_toMap | 150469 | 6.65 |


### 2026-03-20 — Commit 5bafff4

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 6607244 | 0.15 |
| kalman_process_100_fixes | 95887 | 10.43 |
| kalman_process_1k_fixes | 9632 | 103.82 |
| kalman_reset | 6580477 | 0.15 |
| haversine_single | 7775317 | 0.13 |
| haversine_1k_pairs | 13658 | 73.22 |
| pip_4v | 11537819 | 0.09 |
| pip_10v | 8941798 | 0.11 |
| pip_50v | 3745146 | 0.27 |
| pip_100v | 2011480 | 0.50 |
| pip_500v | 424589 | 2.36 |
| geofence_eval_10_circular | 628831 | 1.59 |
| geofence_eval_100_circular | 69168 | 14.46 |
| geofence_eval_500_circular | 13188 | 75.82 |
| geofence_eval_10_polygon_6v | 405355 | 2.47 |
| geofence_eval_50_polygon_6v | 82391 | 12.14 |
| processor_1k_fixes | 8794 | 113.71 |
| processor_1k_adaptive | 8384 | 119.28 |
| trip_manager_5k_waypoints | 65 | 15420.82 |
| schedule_parse | 2861087 | 0.35 |
| schedule_matches | 118666 | 8.43 |
| schedule_isWithin_5_entries | 109664 | 9.12 |
| adaptive_compute | 13456204 | 0.07 |
| location_fromMap | 1653913 | 0.60 |
| location_toMap | 675076 | 1.48 |
| location_fromMap_toMap_roundtrip | 480549 | 2.08 |
| location_copyWithCoords | 12114273 | 0.08 |
| geofence_fromMap_circular | 4236450 | 0.24 |
| geofence_fromMap_polygon | 1555504 | 0.64 |
| delta_encode_10 | 29993 | 33.34 |
| delta_decode_10 | 90941 | 11.00 |
| delta_encode_100 | 4059 | 246.36 |
| delta_decode_100 | 10397 | 96.18 |
| delta_encode_500 | 823 | 1214.51 |
| delta_decode_500 | 1929 | 518.45 |
| delta_roundtrip_100 | 2863 | 349.26 |
| battery_budget_single_sample | 9333387 | 0.11 |
| battery_budget_60_samples | 253029 | 3.95 |
| battery_budget_heavy_drain | 127117 | 7.87 |
| carbon_trip_100_locations | 88570 | 11.29 |
| carbon_onLocation | 4156276 | 0.24 |
| carbon_setActivity | 9735905 | 0.10 |
| carbon_cumulative_report | 2713693 | 0.37 |
| persist_decider_location | 19609393 | 0.05 |
| persist_decider_geofence | 19597373 | 0.05 |
| config_fromMap | 425489 | 2.35 |
| config_toMap | 159829 | 6.26 |
| config_roundtrip | 116710 | 8.57 |
| state_fromMap | 406768 | 2.46 |
| state_toMap | 147234 | 6.79 |


### 2026-03-20 — Commit 1ac9b87

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7268201 | 0.14 |
| kalman_process_100_fixes | 96090 | 10.41 |
| kalman_process_1k_fixes | 9555 | 104.66 |
| kalman_reset | 6679384 | 0.15 |
| haversine_single | 8076864 | 0.12 |
| haversine_1k_pairs | 13715 | 72.91 |
| pip_4v | 13226668 | 0.08 |
| pip_10v | 10037720 | 0.10 |
| pip_50v | 3919674 | 0.26 |
| pip_100v | 2132006 | 0.47 |
| pip_500v | 424338 | 2.36 |
| geofence_eval_10_circular | 643368 | 1.55 |
| geofence_eval_100_circular | 70186 | 14.25 |
| geofence_eval_500_circular | 13373 | 74.78 |
| geofence_eval_10_polygon_6v | 408234 | 2.45 |
| geofence_eval_50_polygon_6v | 82284 | 12.15 |
| processor_1k_fixes | 8908 | 112.26 |
| processor_1k_adaptive | 8448 | 118.37 |
| trip_manager_5k_waypoints | 66 | 15076.63 |
| schedule_parse | 2874222 | 0.35 |
| schedule_matches | 119562 | 8.36 |
| schedule_isWithin_5_entries | 112366 | 8.90 |
| adaptive_compute | 14130563 | 0.07 |
| location_fromMap | 1700256 | 0.59 |
| location_toMap | 670554 | 1.49 |
| location_fromMap_toMap_roundtrip | 481805 | 2.08 |
| location_copyWithCoords | 12407423 | 0.08 |
| geofence_fromMap_circular | 4453343 | 0.22 |
| geofence_fromMap_polygon | 1605091 | 0.62 |
| delta_encode_10 | 30040 | 33.29 |
| delta_decode_10 | 97998 | 10.20 |
| delta_encode_100 | 4072 | 245.55 |
| delta_decode_100 | 10904 | 91.71 |
| delta_encode_500 | 851 | 1174.63 |
| delta_decode_500 | 2093 | 477.69 |
| delta_roundtrip_100 | 2993 | 334.11 |
| battery_budget_single_sample | 9431000 | 0.11 |
| battery_budget_60_samples | 257991 | 3.88 |
| battery_budget_heavy_drain | 129777 | 7.71 |
| carbon_trip_100_locations | 90192 | 11.09 |
| carbon_onLocation | 4127031 | 0.24 |
| carbon_setActivity | 9936903 | 0.10 |
| carbon_cumulative_report | 2753725 | 0.36 |
| persist_decider_location | 20085217 | 0.05 |
| persist_decider_geofence | 20294945 | 0.05 |
| config_fromMap | 471409 | 2.12 |
| config_toMap | 157257 | 6.36 |
| config_roundtrip | 117907 | 8.48 |
| state_fromMap | 444477 | 2.25 |
| state_toMap | 147408 | 6.78 |


### 2026-03-20 — Commit eef4cd0

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 6931860 | 0.14 |
| kalman_process_100_fixes | 101951 | 9.81 |
| kalman_process_1k_fixes | 10338 | 96.73 |
| kalman_reset | 6486969 | 0.15 |
| haversine_single | 7818017 | 0.13 |
| haversine_1k_pairs | 13833 | 72.29 |
| pip_4v | 12778317 | 0.08 |
| pip_10v | 9638121 | 0.10 |
| pip_50v | 3623121 | 0.28 |
| pip_100v | 1948805 | 0.51 |
| pip_500v | 378120 | 2.64 |
| geofence_eval_10_circular | 658666 | 1.52 |
| geofence_eval_100_circular | 69729 | 14.34 |
| geofence_eval_500_circular | 13825 | 72.33 |
| geofence_eval_10_polygon_6v | 422565 | 2.37 |
| geofence_eval_50_polygon_6v | 84922 | 11.78 |
| processor_1k_fixes | 9248 | 108.13 |
| processor_1k_adaptive | 8500 | 117.65 |
| trip_manager_5k_waypoints | 58 | 17388.51 |
| schedule_parse | 2900183 | 0.34 |
| schedule_matches | 103152 | 9.69 |
| schedule_isWithin_5_entries | 98732 | 10.13 |
| adaptive_compute | 13194487 | 0.08 |
| location_fromMap | 1685001 | 0.59 |
| location_toMap | 677515 | 1.48 |
| location_fromMap_toMap_roundtrip | 485215 | 2.06 |
| location_copyWithCoords | 11384619 | 0.09 |
| geofence_fromMap_circular | 4293751 | 0.23 |
| geofence_fromMap_polygon | 1565030 | 0.64 |
| delta_encode_10 | 30758 | 32.51 |
| delta_decode_10 | 97371 | 10.27 |
| delta_encode_100 | 4414 | 226.57 |
| delta_decode_100 | 11259 | 88.82 |
| delta_encode_500 | 870 | 1149.83 |
| delta_decode_500 | 2112 | 473.53 |
| delta_roundtrip_100 | 3141 | 318.39 |
| battery_budget_single_sample | 8927310 | 0.11 |
| battery_budget_60_samples | 254059 | 3.94 |
| battery_budget_heavy_drain | 129403 | 7.73 |
| carbon_trip_100_locations | 86725 | 11.53 |
| carbon_onLocation | 4152842 | 0.24 |
| carbon_setActivity | 9652701 | 0.10 |
| carbon_cumulative_report | 2673877 | 0.37 |
| persist_decider_location | 19241886 | 0.05 |
| persist_decider_geofence | 19311125 | 0.05 |
| config_fromMap | 442700 | 2.26 |
| config_toMap | 157682 | 6.34 |
| config_roundtrip | 116383 | 8.59 |
| state_fromMap | 415892 | 2.40 |
| state_toMap | 148185 | 6.75 |


### 2026-03-20 — Commit 9b323f0

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7255165 | 0.14 |
| kalman_process_100_fixes | 96891 | 10.32 |
| kalman_process_1k_fixes | 9691 | 103.19 |
| kalman_reset | 6812833 | 0.15 |
| haversine_single | 9214808 | 0.11 |
| haversine_1k_pairs | 18728 | 53.40 |
| pip_4v | 13303644 | 0.08 |
| pip_10v | 10209728 | 0.10 |
| pip_50v | 4051475 | 0.25 |
| pip_100v | 2194295 | 0.46 |
| pip_500v | 447570 | 2.23 |
| geofence_eval_10_circular | 695357 | 1.44 |
| geofence_eval_100_circular | 76369 | 13.09 |
| geofence_eval_500_circular | 14554 | 68.71 |
| geofence_eval_10_polygon_6v | 438327 | 2.28 |
| geofence_eval_50_polygon_6v | 88522 | 11.30 |
| processor_1k_fixes | 10503 | 95.21 |
| processor_1k_adaptive | 10208 | 97.97 |
| trip_manager_5k_waypoints | 139 | 7204.78 |
| schedule_parse | 3087015 | 0.32 |
| schedule_matches | 257427 | 3.88 |
| schedule_isWithin_5_entries | 227808 | 4.39 |
| adaptive_compute | 13632086 | 0.07 |
| location_fromMap | 1663120 | 0.60 |
| location_toMap | 572170 | 1.75 |
| location_fromMap_toMap_roundtrip | 442610 | 2.26 |
| location_copyWithCoords | 10686114 | 0.09 |
| geofence_fromMap_circular | 4343972 | 0.23 |
| geofence_fromMap_polygon | 1520136 | 0.66 |
| delta_encode_10 | 32089 | 31.16 |
| delta_decode_10 | 88430 | 11.31 |
| delta_encode_100 | 4169 | 239.89 |
| delta_decode_100 | 10515 | 95.10 |
| delta_encode_500 | 778 | 1285.17 |
| delta_decode_500 | 1763 | 567.32 |
| delta_roundtrip_100 | 2972 | 336.51 |
| battery_budget_single_sample | 9531715 | 0.10 |
| battery_budget_60_samples | 273379 | 3.66 |
| battery_budget_heavy_drain | 139447 | 7.17 |
| carbon_trip_100_locations | 102547 | 9.75 |
| carbon_onLocation | 4277817 | 0.23 |
| carbon_setActivity | 10025888 | 0.10 |
| carbon_cumulative_report | 2586573 | 0.39 |
| persist_decider_location | 22166632 | 0.05 |
| persist_decider_geofence | 22037239 | 0.05 |
| config_fromMap | 435741 | 2.29 |
| config_toMap | 155360 | 6.44 |
| config_roundtrip | 111947 | 8.93 |
| state_fromMap | 408855 | 2.45 |
| state_toMap | 143701 | 6.96 |


### 2026-03-19 — Commit 261c951

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7161222 | 0.14 |
| kalman_process_100_fixes | 96302 | 10.38 |
| kalman_process_1k_fixes | 9633 | 103.81 |
| kalman_reset | 6878834 | 0.15 |
| haversine_single | 8022686 | 0.12 |
| haversine_1k_pairs | 13876 | 72.07 |
| pip_4v | 12971923 | 0.08 |
| pip_10v | 10065632 | 0.10 |
| pip_50v | 3764798 | 0.27 |
| pip_100v | 2059341 | 0.49 |
| pip_500v | 419665 | 2.38 |
| geofence_eval_10_circular | 640735 | 1.56 |
| geofence_eval_100_circular | 69847 | 14.32 |
| geofence_eval_500_circular | 13506 | 74.04 |
| geofence_eval_10_polygon_6v | 411121 | 2.43 |
| geofence_eval_50_polygon_6v | 83346 | 12.00 |
| processor_1k_fixes | 8933 | 111.94 |
| processor_1k_adaptive | 8522 | 117.34 |
| trip_manager_5k_waypoints | 66 | 15093.02 |
| schedule_parse | 2904586 | 0.34 |
| schedule_matches | 117940 | 8.48 |
| schedule_isWithin_5_entries | 113306 | 8.83 |
| adaptive_compute | 13552871 | 0.07 |
| location_fromMap | 1729036 | 0.58 |
| location_toMap | 675787 | 1.48 |
| location_fromMap_toMap_roundtrip | 489506 | 2.04 |
| location_copyWithCoords | 12460363 | 0.08 |
| geofence_fromMap_circular | 4417694 | 0.23 |
| geofence_fromMap_polygon | 1606454 | 0.62 |
| delta_encode_10 | 28733 | 34.80 |
| delta_decode_10 | 98139 | 10.19 |
| delta_encode_100 | 3999 | 250.04 |
| delta_decode_100 | 11109 | 90.02 |
| delta_encode_500 | 805 | 1242.50 |
| delta_decode_500 | 2179 | 459.02 |
| delta_roundtrip_100 | 2978 | 335.81 |
| battery_budget_single_sample | 9472299 | 0.11 |
| battery_budget_60_samples | 243363 | 4.11 |
| battery_budget_heavy_drain | 130383 | 7.67 |
| carbon_trip_100_locations | 90260 | 11.08 |
| carbon_onLocation | 4046950 | 0.25 |
| carbon_setActivity | 9911147 | 0.10 |
| carbon_cumulative_report | 2768448 | 0.36 |
| persist_decider_location | 20136479 | 0.05 |
| persist_decider_geofence | 20109513 | 0.05 |
| config_fromMap | 441177 | 2.27 |
| config_toMap | 162220 | 6.16 |
| config_roundtrip | 117654 | 8.50 |
| state_fromMap | 431918 | 2.32 |
| state_toMap | 149851 | 6.67 |


### 2026-03-19 — Commit 934e35b

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7389711 | 0.14 |
| kalman_process_100_fixes | 93919 | 10.65 |
| kalman_process_1k_fixes | 9457 | 105.74 |
| kalman_reset | 6902063 | 0.14 |
| haversine_single | 9189134 | 0.11 |
| haversine_1k_pairs | 18727 | 53.40 |
| pip_4v | 13453156 | 0.07 |
| pip_10v | 10199519 | 0.10 |
| pip_50v | 4075423 | 0.25 |
| pip_100v | 2198121 | 0.45 |
| pip_500v | 448148 | 2.23 |
| geofence_eval_10_circular | 687974 | 1.45 |
| geofence_eval_100_circular | 75958 | 13.17 |
| geofence_eval_500_circular | 14405 | 69.42 |
| geofence_eval_10_polygon_6v | 439637 | 2.27 |
| geofence_eval_50_polygon_6v | 88712 | 11.27 |
| processor_1k_fixes | 10781 | 92.75 |
| processor_1k_adaptive | 10157 | 98.46 |
| trip_manager_5k_waypoints | 136 | 7370.29 |
| schedule_parse | 3208053 | 0.31 |
| schedule_matches | 255824 | 3.91 |
| schedule_isWithin_5_entries | 230427 | 4.34 |
| adaptive_compute | 14160726 | 0.07 |
| location_fromMap | 1721371 | 0.58 |
| location_toMap | 625680 | 1.60 |
| location_fromMap_toMap_roundtrip | 471897 | 2.12 |
| location_copyWithCoords | 11642770 | 0.09 |
| geofence_fromMap_circular | 4463422 | 0.22 |
| geofence_fromMap_polygon | 1626159 | 0.61 |
| delta_encode_10 | 32185 | 31.07 |
| delta_decode_10 | 88126 | 11.35 |
| delta_encode_100 | 4117 | 242.89 |
| delta_decode_100 | 10364 | 96.49 |
| delta_encode_500 | 780 | 1282.64 |
| delta_decode_500 | 1775 | 563.53 |
| delta_roundtrip_100 | 2955 | 338.43 |
| battery_budget_single_sample | 9483841 | 0.11 |
| battery_budget_60_samples | 274146 | 3.65 |
| battery_budget_heavy_drain | 139844 | 7.15 |
| carbon_trip_100_locations | 101661 | 9.84 |
| carbon_onLocation | 4430172 | 0.23 |
| carbon_setActivity | 10547005 | 0.09 |
| carbon_cumulative_report | 2759567 | 0.36 |
| persist_decider_location | 22300245 | 0.04 |
| persist_decider_geofence | 22243973 | 0.04 |
| config_fromMap | 455092 | 2.20 |
| config_toMap | 160300 | 6.24 |
| config_roundtrip | 118087 | 8.47 |
| state_fromMap | 416191 | 2.40 |
| state_toMap | 148730 | 6.72 |


### 2026-03-19 — Commit b80704f

**Environment:** Dart 3.11.3, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7051108 | 0.14 |
| kalman_process_100_fixes | 96455 | 10.37 |
| kalman_process_1k_fixes | 9798 | 102.07 |
| kalman_reset | 6700032 | 0.15 |
| haversine_single | 8067144 | 0.12 |
| haversine_1k_pairs | 13937 | 71.75 |
| pip_4v | 13573394 | 0.07 |
| pip_10v | 10052322 | 0.10 |
| pip_50v | 4036942 | 0.25 |
| pip_100v | 2177749 | 0.46 |
| pip_500v | 417466 | 2.40 |
| geofence_eval_10_circular | 629676 | 1.59 |
| geofence_eval_100_circular | 70671 | 14.15 |
| geofence_eval_500_circular | 13583 | 73.62 |
| geofence_eval_10_polygon_6v | 418177 | 2.39 |
| geofence_eval_50_polygon_6v | 82804 | 12.08 |
| processor_1k_fixes | 8991 | 111.22 |
| processor_1k_adaptive | 8469 | 118.08 |
| trip_manager_5k_waypoints | 66 | 15078.83 |
| schedule_parse | 2857594 | 0.35 |
| schedule_matches | 118339 | 8.45 |
| schedule_isWithin_5_entries | 111786 | 8.95 |
| adaptive_compute | 13863122 | 0.07 |
| location_fromMap | 1750530 | 0.57 |
| location_toMap | 688231 | 1.45 |
| location_fromMap_toMap_roundtrip | 491529 | 2.03 |
| location_copyWithCoords | 12356123 | 0.08 |
| geofence_fromMap_circular | 4434877 | 0.23 |
| geofence_fromMap_polygon | 1564264 | 0.64 |
| delta_encode_10 | 29413 | 34.00 |
| delta_decode_10 | 99341 | 10.07 |
| delta_encode_100 | 3994 | 250.37 |
| delta_decode_100 | 11152 | 89.67 |
| delta_encode_500 | 823 | 1215.08 |
| delta_decode_500 | 2104 | 475.20 |
| delta_roundtrip_100 | 2980 | 335.62 |
| battery_budget_single_sample | 9465944 | 0.11 |
| battery_budget_60_samples | 254783 | 3.92 |
| battery_budget_heavy_drain | 129659 | 7.71 |
| carbon_trip_100_locations | 90434 | 11.06 |
| carbon_onLocation | 4202253 | 0.24 |
| carbon_setActivity | 9660556 | 0.10 |
| carbon_cumulative_report | 2691539 | 0.37 |
| persist_decider_location | 20063981 | 0.05 |
| persist_decider_geofence | 19950063 | 0.05 |
| config_fromMap | 467972 | 2.14 |
| config_toMap | 160373 | 6.24 |
| config_roundtrip | 118292 | 8.45 |
| state_fromMap | 435552 | 2.30 |
| state_toMap | 150602 | 6.64 |


### 2026-03-18 — Commit b8ad82c

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7275423 | 0.14 |
| kalman_process_100_fixes | 94892 | 10.54 |
| kalman_process_1k_fixes | 9499 | 105.28 |
| kalman_reset | 6837177 | 0.15 |
| haversine_single | 7993329 | 0.13 |
| haversine_1k_pairs | 13968 | 71.59 |
| pip_4v | 13456138 | 0.07 |
| pip_10v | 10047189 | 0.10 |
| pip_50v | 3833996 | 0.26 |
| pip_100v | 2082911 | 0.48 |
| pip_500v | 419629 | 2.38 |
| geofence_eval_10_circular | 648683 | 1.54 |
| geofence_eval_100_circular | 71079 | 14.07 |
| geofence_eval_500_circular | 13619 | 73.43 |
| geofence_eval_10_polygon_6v | 391864 | 2.55 |
| geofence_eval_50_polygon_6v | 82983 | 12.05 |
| processor_1k_fixes | 8991 | 111.22 |
| processor_1k_adaptive | 8436 | 118.54 |
| trip_manager_5k_waypoints | 66 | 15210.80 |
| schedule_parse | 2856403 | 0.35 |
| schedule_matches | 117960 | 8.48 |
| schedule_isWithin_5_entries | 110104 | 9.08 |
| adaptive_compute | 14061158 | 0.07 |
| location_fromMap | 1778516 | 0.56 |
| location_toMap | 657413 | 1.52 |
| location_fromMap_toMap_roundtrip | 446879 | 2.24 |
| location_copyWithCoords | 12478790 | 0.08 |
| geofence_fromMap_circular | 4537611 | 0.22 |
| geofence_fromMap_polygon | 1601644 | 0.62 |
| delta_encode_10 | 30045 | 33.28 |
| delta_decode_10 | 97403 | 10.27 |
| delta_encode_100 | 3949 | 253.21 |
| delta_decode_100 | 10678 | 93.65 |
| delta_encode_500 | 804 | 1244.16 |
| delta_decode_500 | 2065 | 484.24 |
| delta_roundtrip_100 | 2960 | 337.83 |
| battery_budget_single_sample | 9442124 | 0.11 |
| battery_budget_60_samples | 255196 | 3.92 |
| battery_budget_heavy_drain | 129612 | 7.72 |
| carbon_trip_100_locations | 90802 | 11.01 |
| carbon_onLocation | 4106390 | 0.24 |
| carbon_setActivity | 9603590 | 0.10 |
| carbon_cumulative_report | 2681291 | 0.37 |
| persist_decider_location | 19875873 | 0.05 |
| persist_decider_geofence | 20070843 | 0.05 |
| config_fromMap | 460309 | 2.17 |
| config_toMap | 157596 | 6.35 |
| config_roundtrip | 113329 | 8.82 |
| state_fromMap | 431229 | 2.32 |
| state_toMap | 146592 | 6.82 |


### 2026-03-18 — Commit b15a4c6

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7262488 | 0.14 |
| kalman_process_100_fixes | 95543 | 10.47 |
| kalman_process_1k_fixes | 9407 | 106.30 |
| kalman_reset | 6816374 | 0.15 |
| haversine_single | 9532448 | 0.10 |
| haversine_1k_pairs | 18610 | 53.73 |
| pip_4v | 13443209 | 0.07 |
| pip_10v | 10320501 | 0.10 |
| pip_50v | 3959159 | 0.25 |
| pip_100v | 2244842 | 0.45 |
| pip_500v | 444209 | 2.25 |
| geofence_eval_10_circular | 696724 | 1.44 |
| geofence_eval_100_circular | 78043 | 12.81 |
| geofence_eval_500_circular | 14735 | 67.87 |
| geofence_eval_10_polygon_6v | 444695 | 2.25 |
| geofence_eval_50_polygon_6v | 88858 | 11.25 |
| processor_1k_fixes | 10872 | 91.98 |
| processor_1k_adaptive | 10125 | 98.77 |
| trip_manager_5k_waypoints | 141 | 7106.78 |
| schedule_parse | 3219705 | 0.31 |
| schedule_matches | 259868 | 3.85 |
| schedule_isWithin_5_entries | 236078 | 4.24 |
| adaptive_compute | 14110880 | 0.07 |
| location_fromMap | 1839059 | 0.54 |
| location_toMap | 690044 | 1.45 |
| location_fromMap_toMap_roundtrip | 507000 | 1.97 |
| location_copyWithCoords | 11767905 | 0.08 |
| geofence_fromMap_circular | 4464662 | 0.22 |
| geofence_fromMap_polygon | 1647743 | 0.61 |
| delta_encode_10 | 32590 | 30.68 |
| delta_decode_10 | 97052 | 10.30 |
| delta_encode_100 | 4433 | 225.57 |
| delta_decode_100 | 11267 | 88.75 |
| delta_encode_500 | 816 | 1224.82 |
| delta_decode_500 | 2067 | 483.89 |
| delta_roundtrip_100 | 3176 | 314.90 |
| battery_budget_single_sample | 9641815 | 0.10 |
| battery_budget_60_samples | 295946 | 3.38 |
| battery_budget_heavy_drain | 149944 | 6.67 |
| carbon_trip_100_locations | 107905 | 9.27 |
| carbon_onLocation | 4383456 | 0.23 |
| carbon_setActivity | 10312182 | 0.10 |
| carbon_cumulative_report | 2766342 | 0.36 |
| persist_decider_location | 21885200 | 0.05 |
| persist_decider_geofence | 21995492 | 0.05 |
| config_fromMap | 494089 | 2.02 |
| config_toMap | 163962 | 6.10 |
| config_roundtrip | 120852 | 8.27 |
| state_fromMap | 459640 | 2.18 |
| state_toMap | 157036 | 6.37 |


### 2026-03-18 — Commit 646c7ba

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7390493 | 0.14 |
| kalman_process_100_fixes | 95244 | 10.50 |
| kalman_process_1k_fixes | 9541 | 104.81 |
| kalman_reset | 6882010 | 0.15 |
| haversine_single | 8145666 | 0.12 |
| haversine_1k_pairs | 14003 | 71.42 |
| pip_4v | 12868261 | 0.08 |
| pip_10v | 9690557 | 0.10 |
| pip_50v | 3884685 | 0.26 |
| pip_100v | 2041469 | 0.49 |
| pip_500v | 414208 | 2.41 |
| geofence_eval_10_circular | 638767 | 1.57 |
| geofence_eval_100_circular | 70610 | 14.16 |
| geofence_eval_500_circular | 13644 | 73.29 |
| geofence_eval_10_polygon_6v | 422613 | 2.37 |
| geofence_eval_50_polygon_6v | 84095 | 11.89 |
| processor_1k_fixes | 9040 | 110.61 |
| processor_1k_adaptive | 8595 | 116.35 |
| trip_manager_5k_waypoints | 66 | 15142.02 |
| schedule_parse | 2893086 | 0.35 |
| schedule_matches | 119572 | 8.36 |
| schedule_isWithin_5_entries | 111814 | 8.94 |
| adaptive_compute | 12620813 | 0.08 |
| location_fromMap | 1861358 | 0.54 |
| location_toMap | 689520 | 1.45 |
| location_fromMap_toMap_roundtrip | 506942 | 1.97 |
| location_copyWithCoords | 12572906 | 0.08 |
| geofence_fromMap_circular | 4537876 | 0.22 |
| geofence_fromMap_polygon | 1587949 | 0.63 |
| delta_encode_10 | 29588 | 33.80 |
| delta_decode_10 | 98852 | 10.12 |
| delta_encode_100 | 4041 | 247.44 |
| delta_decode_100 | 11131 | 89.84 |
| delta_encode_500 | 813 | 1230.75 |
| delta_decode_500 | 2106 | 474.77 |
| delta_roundtrip_100 | 2955 | 338.38 |
| battery_budget_single_sample | 9347201 | 0.11 |
| battery_budget_60_samples | 256029 | 3.91 |
| battery_budget_heavy_drain | 128681 | 7.77 |
| carbon_trip_100_locations | 90812 | 11.01 |
| carbon_onLocation | 4131996 | 0.24 |
| carbon_setActivity | 9774532 | 0.10 |
| carbon_cumulative_report | 2730732 | 0.37 |
| persist_decider_location | 19717948 | 0.05 |
| persist_decider_geofence | 19842423 | 0.05 |
| config_fromMap | 470692 | 2.12 |
| config_toMap | 159561 | 6.27 |
| config_roundtrip | 116365 | 8.59 |
| state_fromMap | 444665 | 2.25 |
| state_toMap | 149117 | 6.71 |


### 2026-03-18 — Commit f55a0bf

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7407183 | 0.14 |
| kalman_process_100_fixes | 98030 | 10.20 |
| kalman_process_1k_fixes | 9669 | 103.42 |
| kalman_reset | 6897195 | 0.14 |
| haversine_single | 7874722 | 0.13 |
| haversine_1k_pairs | 13905 | 71.92 |
| pip_4v | 12743243 | 0.08 |
| pip_10v | 9836761 | 0.10 |
| pip_50v | 3927904 | 0.25 |
| pip_100v | 2109519 | 0.47 |
| pip_500v | 418189 | 2.39 |
| geofence_eval_10_circular | 648083 | 1.54 |
| geofence_eval_100_circular | 70524 | 14.18 |
| geofence_eval_500_circular | 13605 | 73.50 |
| geofence_eval_10_polygon_6v | 423168 | 2.36 |
| geofence_eval_50_polygon_6v | 85870 | 11.65 |
| processor_1k_fixes | 9055 | 110.43 |
| processor_1k_adaptive | 8538 | 117.13 |
| trip_manager_5k_waypoints | 64 | 15619.84 |
| schedule_parse | 2887656 | 0.35 |
| schedule_matches | 117561 | 8.51 |
| schedule_isWithin_5_entries | 112007 | 8.93 |
| adaptive_compute | 13955511 | 0.07 |
| location_fromMap | 1781988 | 0.56 |
| location_toMap | 681341 | 1.47 |
| location_fromMap_toMap_roundtrip | 493910 | 2.02 |
| location_copyWithCoords | 12696138 | 0.08 |
| geofence_fromMap_circular | 4532064 | 0.22 |
| geofence_fromMap_polygon | 1567687 | 0.64 |
| delta_encode_10 | 29196 | 34.25 |
| delta_decode_10 | 97426 | 10.26 |
| delta_encode_100 | 4031 | 248.06 |
| delta_decode_100 | 11108 | 90.02 |
| delta_encode_500 | 838 | 1193.83 |
| delta_decode_500 | 2347 | 426.16 |
| delta_roundtrip_100 | 2881 | 347.11 |
| battery_budget_single_sample | 9417182 | 0.11 |
| battery_budget_60_samples | 254399 | 3.93 |
| battery_budget_heavy_drain | 128472 | 7.78 |
| carbon_trip_100_locations | 88871 | 11.25 |
| carbon_onLocation | 4184118 | 0.24 |
| carbon_setActivity | 9747584 | 0.10 |
| carbon_cumulative_report | 2728016 | 0.37 |
| persist_decider_location | 20058677 | 0.05 |
| persist_decider_geofence | 19969621 | 0.05 |
| config_fromMap | 443852 | 2.25 |
| config_toMap | 156690 | 6.38 |
| config_roundtrip | 109157 | 9.16 |
| state_fromMap | 423170 | 2.36 |
| state_toMap | 148530 | 6.73 |


### 2026-03-18 — Commit 8ca7036

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7362912 | 0.14 |
| kalman_process_100_fixes | 94004 | 10.64 |
| kalman_process_1k_fixes | 9581 | 104.38 |
| kalman_reset | 6642279 | 0.15 |
| haversine_single | 8083339 | 0.12 |
| haversine_1k_pairs | 13763 | 72.66 |
| pip_4v | 13031316 | 0.08 |
| pip_10v | 9952656 | 0.10 |
| pip_50v | 3749374 | 0.27 |
| pip_100v | 2043620 | 0.49 |
| pip_500v | 416037 | 2.40 |
| geofence_eval_10_circular | 645780 | 1.55 |
| geofence_eval_100_circular | 69518 | 14.38 |
| geofence_eval_500_circular | 13569 | 73.70 |
| geofence_eval_10_polygon_6v | 410136 | 2.44 |
| geofence_eval_50_polygon_6v | 83181 | 12.02 |
| processor_1k_fixes | 8987 | 111.27 |
| processor_1k_adaptive | 8251 | 121.20 |
| trip_manager_5k_waypoints | 65 | 15354.61 |
| schedule_parse | 2884922 | 0.35 |
| schedule_matches | 117562 | 8.51 |
| schedule_isWithin_5_entries | 112425 | 8.89 |
| adaptive_compute | 13967890 | 0.07 |
| location_fromMap | 1823634 | 0.55 |
| location_toMap | 693794 | 1.44 |
| location_fromMap_toMap_roundtrip | 510921 | 1.96 |
| location_copyWithCoords | 12725818 | 0.08 |
| geofence_fromMap_circular | 4525068 | 0.22 |
| geofence_fromMap_polygon | 1600550 | 0.62 |
| delta_encode_10 | 29350 | 34.07 |
| delta_decode_10 | 97769 | 10.23 |
| delta_encode_100 | 3980 | 251.28 |
| delta_decode_100 | 10969 | 91.16 |
| delta_encode_500 | 839 | 1192.06 |
| delta_decode_500 | 2102 | 475.66 |
| delta_roundtrip_100 | 2972 | 336.51 |
| battery_budget_single_sample | 9556261 | 0.10 |
| battery_budget_60_samples | 256743 | 3.89 |
| battery_budget_heavy_drain | 128730 | 7.77 |
| carbon_trip_100_locations | 89478 | 11.18 |
| carbon_onLocation | 4218089 | 0.24 |
| carbon_setActivity | 9864230 | 0.10 |
| carbon_cumulative_report | 2719915 | 0.37 |
| persist_decider_location | 20130562 | 0.05 |
| persist_decider_geofence | 20318707 | 0.05 |
| config_fromMap | 458221 | 2.18 |
| config_toMap | 159966 | 6.25 |
| config_roundtrip | 118627 | 8.43 |
| state_fromMap | 444566 | 2.25 |
| state_toMap | 151260 | 6.61 |


### 2026-03-18 — Commit 2b2d467

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7354674 | 0.14 |
| kalman_process_100_fixes | 94934 | 10.53 |
| kalman_process_1k_fixes | 9591 | 104.27 |
| kalman_reset | 6899918 | 0.14 |
| haversine_single | 8052135 | 0.12 |
| haversine_1k_pairs | 13918 | 71.85 |
| pip_4v | 13041244 | 0.08 |
| pip_10v | 10026387 | 0.10 |
| pip_50v | 3806590 | 0.26 |
| pip_100v | 2045042 | 0.49 |
| pip_500v | 415584 | 2.41 |
| geofence_eval_10_circular | 637167 | 1.57 |
| geofence_eval_100_circular | 69313 | 14.43 |
| geofence_eval_500_circular | 13370 | 74.79 |
| geofence_eval_10_polygon_6v | 421990 | 2.37 |
| geofence_eval_50_polygon_6v | 84295 | 11.86 |
| processor_1k_fixes | 8872 | 112.71 |
| processor_1k_adaptive | 8368 | 119.51 |
| trip_manager_5k_waypoints | 66 | 15130.79 |
| schedule_parse | 2916231 | 0.34 |
| schedule_matches | 118606 | 8.43 |
| schedule_isWithin_5_entries | 113231 | 8.83 |
| adaptive_compute | 13210429 | 0.08 |
| location_fromMap | 1800307 | 0.56 |
| location_toMap | 675163 | 1.48 |
| location_fromMap_toMap_roundtrip | 496693 | 2.01 |
| location_copyWithCoords | 12287050 | 0.08 |
| geofence_fromMap_circular | 4482270 | 0.22 |
| geofence_fromMap_polygon | 1579942 | 0.63 |
| delta_encode_10 | 29083 | 34.38 |
| delta_decode_10 | 96373 | 10.38 |
| delta_encode_100 | 3963 | 252.35 |
| delta_decode_100 | 10823 | 92.40 |
| delta_encode_500 | 799 | 1251.12 |
| delta_decode_500 | 2043 | 489.48 |
| delta_roundtrip_100 | 2934 | 340.78 |
| battery_budget_single_sample | 9311539 | 0.11 |
| battery_budget_60_samples | 254470 | 3.93 |
| battery_budget_heavy_drain | 128969 | 7.75 |
| carbon_trip_100_locations | 89968 | 11.12 |
| carbon_onLocation | 4054035 | 0.25 |
| carbon_setActivity | 9773467 | 0.10 |
| carbon_cumulative_report | 2593154 | 0.39 |
| persist_decider_location | 19869097 | 0.05 |
| persist_decider_geofence | 19912952 | 0.05 |
| config_fromMap | 462965 | 2.16 |
| config_toMap | 157939 | 6.33 |
| config_roundtrip | 115865 | 8.63 |
| state_fromMap | 437914 | 2.28 |
| state_toMap | 149474 | 6.69 |


### 2026-03-18 — Commit 008e9f3

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7297071 | 0.14 |
| kalman_process_100_fixes | 94077 | 10.63 |
| kalman_process_1k_fixes | 9414 | 106.22 |
| kalman_reset | 6681432 | 0.15 |
| haversine_single | 7940394 | 0.13 |
| haversine_1k_pairs | 13439 | 74.41 |
| pip_4v | 12825960 | 0.08 |
| pip_10v | 9992933 | 0.10 |
| pip_50v | 3870695 | 0.26 |
| pip_100v | 2187088 | 0.46 |
| pip_500v | 428588 | 2.33 |
| geofence_eval_10_circular | 615147 | 1.63 |
| geofence_eval_100_circular | 67789 | 14.75 |
| geofence_eval_500_circular | 13162 | 75.97 |
| geofence_eval_10_polygon_6v | 406365 | 2.46 |
| geofence_eval_50_polygon_6v | 80058 | 12.49 |
| processor_1k_fixes | 8659 | 115.49 |
| processor_1k_adaptive | 8240 | 121.36 |
| trip_manager_5k_waypoints | 63 | 15787.91 |
| schedule_parse | 2877525 | 0.35 |
| schedule_matches | 117073 | 8.54 |
| schedule_isWithin_5_entries | 109015 | 9.17 |
| adaptive_compute | 13882628 | 0.07 |
| location_fromMap | 1776079 | 0.56 |
| location_toMap | 683179 | 1.46 |
| location_fromMap_toMap_roundtrip | 502307 | 1.99 |
| location_copyWithCoords | 12629967 | 0.08 |
| geofence_fromMap_circular | 4497970 | 0.22 |
| geofence_fromMap_polygon | 1555812 | 0.64 |
| delta_encode_10 | 27768 | 36.01 |
| delta_decode_10 | 95016 | 10.52 |
| delta_encode_100 | 3983 | 251.08 |
| delta_decode_100 | 10542 | 94.86 |
| delta_encode_500 | 825 | 1211.97 |
| delta_decode_500 | 2042 | 489.69 |
| delta_roundtrip_100 | 2941 | 340.03 |
| battery_budget_single_sample | 9358492 | 0.11 |
| battery_budget_60_samples | 255046 | 3.92 |
| battery_budget_heavy_drain | 128765 | 7.77 |
| carbon_trip_100_locations | 92966 | 10.76 |
| carbon_onLocation | 4136121 | 0.24 |
| carbon_setActivity | 9681258 | 0.10 |
| carbon_cumulative_report | 2669296 | 0.37 |
| persist_decider_location | 20247780 | 0.05 |
| persist_decider_geofence | 19998320 | 0.05 |
| config_fromMap | 427833 | 2.34 |
| config_toMap | 156475 | 6.39 |
| config_roundtrip | 114605 | 8.73 |
| state_fromMap | 415493 | 2.41 |
| state_toMap | 148088 | 6.75 |


### 2026-03-18 — Commit 0d381ed

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7546784 | 0.13 |
| kalman_process_100_fixes | 98296 | 10.17 |
| kalman_process_1k_fixes | 9918 | 100.82 |
| kalman_reset | 6914542 | 0.14 |
| haversine_single | 8075620 | 0.12 |
| haversine_1k_pairs | 13689 | 73.05 |
| pip_4v | 13412643 | 0.07 |
| pip_10v | 9693627 | 0.10 |
| pip_50v | 3797254 | 0.26 |
| pip_100v | 2078016 | 0.48 |
| pip_500v | 428694 | 2.33 |
| geofence_eval_10_circular | 636375 | 1.57 |
| geofence_eval_100_circular | 70185 | 14.25 |
| geofence_eval_500_circular | 13340 | 74.97 |
| geofence_eval_10_polygon_6v | 418167 | 2.39 |
| geofence_eval_50_polygon_6v | 84154 | 11.88 |
| processor_1k_fixes | 8994 | 111.19 |
| processor_1k_adaptive | 8526 | 117.28 |
| trip_manager_5k_waypoints | 66 | 15095.95 |
| schedule_parse | 2910738 | 0.34 |
| schedule_matches | 118991 | 8.40 |
| schedule_isWithin_5_entries | 114367 | 8.74 |
| adaptive_compute | 13916181 | 0.07 |
| location_fromMap | 1743987 | 0.57 |
| location_toMap | 705299 | 1.42 |
| location_fromMap_toMap_roundtrip | 509867 | 1.96 |
| location_copyWithCoords | 12822095 | 0.08 |
| geofence_fromMap_circular | 4432153 | 0.23 |
| geofence_fromMap_polygon | 1599185 | 0.63 |
| delta_encode_10 | 29918 | 33.42 |
| delta_decode_10 | 96815 | 10.33 |
| delta_encode_100 | 4046 | 247.16 |
| delta_decode_100 | 11245 | 88.93 |
| delta_encode_500 | 869 | 1150.72 |
| delta_decode_500 | 2150 | 465.19 |
| delta_roundtrip_100 | 3005 | 332.82 |
| battery_budget_single_sample | 9365127 | 0.11 |
| battery_budget_60_samples | 256601 | 3.90 |
| battery_budget_heavy_drain | 130508 | 7.66 |
| carbon_trip_100_locations | 88302 | 11.32 |
| carbon_onLocation | 4211012 | 0.24 |
| carbon_setActivity | 9939031 | 0.10 |
| carbon_cumulative_report | 2792325 | 0.36 |
| persist_decider_location | 20065789 | 0.05 |
| persist_decider_geofence | 20185919 | 0.05 |
| config_fromMap | 466826 | 2.14 |
| config_toMap | 161764 | 6.18 |
| config_roundtrip | 120068 | 8.33 |
| state_fromMap | 434595 | 2.30 |
| state_toMap | 152567 | 6.55 |


### 2026-03-17 — Commit dc0d232

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7324468 | 0.14 |
| kalman_process_100_fixes | 94606 | 10.57 |
| kalman_process_1k_fixes | 9481 | 105.48 |
| kalman_reset | 6143723 | 0.16 |
| haversine_single | 7202461 | 0.14 |
| haversine_1k_pairs | 13720 | 72.89 |
| pip_4v | 13230463 | 0.08 |
| pip_10v | 9763495 | 0.10 |
| pip_50v | 3814191 | 0.26 |
| pip_100v | 1984973 | 0.50 |
| pip_500v | 421505 | 2.37 |
| geofence_eval_10_circular | 635978 | 1.57 |
| geofence_eval_100_circular | 68857 | 14.52 |
| geofence_eval_500_circular | 13370 | 74.79 |
| geofence_eval_10_polygon_6v | 416095 | 2.40 |
| geofence_eval_50_polygon_6v | 84457 | 11.84 |
| processor_1k_fixes | 8956 | 111.65 |
| processor_1k_adaptive | 8401 | 119.03 |
| trip_manager_5k_waypoints | 65 | 15429.44 |
| schedule_parse | 2783160 | 0.36 |
| schedule_matches | 116783 | 8.56 |
| schedule_isWithin_5_entries | 111992 | 8.93 |
| adaptive_compute | 11241238 | 0.09 |
| location_fromMap | 1707027 | 0.59 |
| location_toMap | 674415 | 1.48 |
| location_fromMap_toMap_roundtrip | 498898 | 2.00 |
| location_copyWithCoords | 10801107 | 0.09 |
| geofence_fromMap_circular | 4115463 | 0.24 |
| geofence_fromMap_polygon | 1558900 | 0.64 |
| delta_encode_10 | 30301 | 33.00 |
| delta_decode_10 | 96668 | 10.34 |
| delta_encode_100 | 4284 | 233.42 |
| delta_decode_100 | 11001 | 90.90 |
| delta_encode_500 | 860 | 1162.61 |
| delta_decode_500 | 2280 | 438.53 |
| delta_roundtrip_100 | 2972 | 336.52 |
| battery_budget_single_sample | 8203359 | 0.12 |
| battery_budget_60_samples | 255595 | 3.91 |
| battery_budget_heavy_drain | 129455 | 7.72 |
| carbon_trip_100_locations | 92391 | 10.82 |
| carbon_onLocation | 4187991 | 0.24 |
| carbon_setActivity | 9912083 | 0.10 |
| carbon_cumulative_report | 2776314 | 0.36 |
| persist_decider_location | 15808524 | 0.06 |
| persist_decider_geofence | 15803035 | 0.06 |
| config_fromMap | 494388 | 2.02 |
| config_toMap | 163535 | 6.11 |
| config_roundtrip | 121320 | 8.24 |
| state_fromMap | 460005 | 2.17 |
| state_toMap | 154159 | 6.49 |


### 2026-03-16 — Commit 2136b9a

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7396734 | 0.14 |
| kalman_process_100_fixes | 94240 | 10.61 |
| kalman_process_1k_fixes | 9622 | 103.93 |
| kalman_reset | 6890857 | 0.15 |
| haversine_single | 8044940 | 0.12 |
| haversine_1k_pairs | 13864 | 72.13 |
| pip_4v | 13142478 | 0.08 |
| pip_10v | 9957155 | 0.10 |
| pip_50v | 3779722 | 0.26 |
| pip_100v | 2044375 | 0.49 |
| pip_500v | 420364 | 2.38 |
| geofence_eval_10_circular | 640231 | 1.56 |
| geofence_eval_100_circular | 69887 | 14.31 |
| geofence_eval_500_circular | 13413 | 74.56 |
| geofence_eval_10_polygon_6v | 415499 | 2.41 |
| geofence_eval_50_polygon_6v | 82540 | 12.12 |
| processor_1k_fixes | 8812 | 113.48 |
| processor_1k_adaptive | 8407 | 118.95 |
| trip_manager_5k_waypoints | 66 | 15117.69 |
| schedule_parse | 2889543 | 0.35 |
| schedule_matches | 118460 | 8.44 |
| schedule_isWithin_5_entries | 110747 | 9.03 |
| adaptive_compute | 13886051 | 0.07 |
| location_fromMap | 1815676 | 0.55 |
| location_toMap | 690122 | 1.45 |
| location_fromMap_toMap_roundtrip | 511291 | 1.96 |
| location_copyWithCoords | 12005498 | 0.08 |
| geofence_fromMap_circular | 4506028 | 0.22 |
| geofence_fromMap_polygon | 1577770 | 0.63 |
| delta_encode_10 | 30346 | 32.95 |
| delta_decode_10 | 96782 | 10.33 |
| delta_encode_100 | 4082 | 244.98 |
| delta_decode_100 | 11014 | 90.79 |
| delta_encode_500 | 860 | 1163.18 |
| delta_decode_500 | 2138 | 467.82 |
| delta_roundtrip_100 | 2997 | 333.68 |
| battery_budget_single_sample | 9188686 | 0.11 |
| battery_budget_60_samples | 245645 | 4.07 |
| battery_budget_heavy_drain | 124541 | 8.03 |
| carbon_trip_100_locations | 91488 | 10.93 |
| carbon_onLocation | 4229949 | 0.24 |
| carbon_setActivity | 9883241 | 0.10 |
| carbon_cumulative_report | 2726171 | 0.37 |
| persist_decider_location | 19884446 | 0.05 |
| persist_decider_geofence | 20025361 | 0.05 |
| config_fromMap | 490434 | 2.04 |
| config_toMap | 167547 | 5.97 |
| config_roundtrip | 123414 | 8.10 |
| state_fromMap | 460497 | 2.17 |
| state_toMap | 159391 | 6.27 |


### 2026-03-16 — Commit 4fd5db5

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7461408 | 0.13 |
| kalman_process_100_fixes | 97232 | 10.28 |
| kalman_process_1k_fixes | 9742 | 102.64 |
| kalman_reset | 6787042 | 0.15 |
| haversine_single | 8037711 | 0.12 |
| haversine_1k_pairs | 13708 | 72.95 |
| pip_4v | 13067784 | 0.08 |
| pip_10v | 10028293 | 0.10 |
| pip_50v | 3860199 | 0.26 |
| pip_100v | 2194697 | 0.46 |
| pip_500v | 423344 | 2.36 |
| geofence_eval_10_circular | 641021 | 1.56 |
| geofence_eval_100_circular | 70400 | 14.20 |
| geofence_eval_500_circular | 13411 | 74.57 |
| geofence_eval_10_polygon_6v | 418465 | 2.39 |
| geofence_eval_50_polygon_6v | 83155 | 12.03 |
| processor_1k_fixes | 8881 | 112.60 |
| processor_1k_adaptive | 8584 | 116.49 |
| trip_manager_5k_waypoints | 66 | 15118.63 |
| schedule_parse | 2780952 | 0.36 |
| schedule_matches | 118077 | 8.47 |
| schedule_isWithin_5_entries | 112787 | 8.87 |
| adaptive_compute | 13957651 | 0.07 |
| location_fromMap | 1838041 | 0.54 |
| location_toMap | 697733 | 1.43 |
| location_fromMap_toMap_roundtrip | 502808 | 1.99 |
| location_copyWithCoords | 12641622 | 0.08 |
| geofence_fromMap_circular | 4497366 | 0.22 |
| geofence_fromMap_polygon | 1574154 | 0.64 |
| delta_encode_10 | 29612 | 33.77 |
| delta_decode_10 | 97525 | 10.25 |
| delta_encode_100 | 4153 | 240.79 |
| delta_decode_100 | 11051 | 90.49 |
| delta_encode_500 | 856 | 1167.87 |
| delta_decode_500 | 2287 | 437.19 |
| delta_roundtrip_100 | 2989 | 334.54 |
| battery_budget_single_sample | 9271191 | 0.11 |
| battery_budget_60_samples | 250565 | 3.99 |
| battery_budget_heavy_drain | 125579 | 7.96 |
| carbon_trip_100_locations | 90267 | 11.08 |
| carbon_onLocation | 4221744 | 0.24 |
| carbon_setActivity | 9909392 | 0.10 |
| carbon_cumulative_report | 2757651 | 0.36 |
| persist_decider_location | 20160696 | 0.05 |
| persist_decider_geofence | 20367980 | 0.05 |
| config_fromMap | 505402 | 1.98 |
| config_toMap | 168006 | 5.95 |
| config_roundtrip | 124682 | 8.02 |
| state_fromMap | 467320 | 2.14 |
| state_toMap | 158238 | 6.32 |


### 2026-03-16 — Commit cde0788

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7393963 | 0.14 |
| kalman_process_100_fixes | 97666 | 10.24 |
| kalman_process_1k_fixes | 9811 | 101.93 |
| kalman_reset | 6936819 | 0.14 |
| haversine_single | 9677681 | 0.10 |
| haversine_1k_pairs | 19023 | 52.57 |
| pip_4v | 12456286 | 0.08 |
| pip_10v | 10459393 | 0.10 |
| pip_50v | 4020707 | 0.25 |
| pip_100v | 2142152 | 0.47 |
| pip_500v | 441798 | 2.26 |
| geofence_eval_10_circular | 688530 | 1.45 |
| geofence_eval_100_circular | 75853 | 13.18 |
| geofence_eval_500_circular | 14304 | 69.91 |
| geofence_eval_10_polygon_6v | 439266 | 2.28 |
| geofence_eval_50_polygon_6v | 87613 | 11.41 |
| processor_1k_fixes | 10844 | 92.22 |
| processor_1k_adaptive | 10094 | 99.07 |
| trip_manager_5k_waypoints | 138 | 7246.73 |
| schedule_parse | 3185321 | 0.31 |
| schedule_matches | 255743 | 3.91 |
| schedule_isWithin_5_entries | 229960 | 4.35 |
| adaptive_compute | 14308576 | 0.07 |
| location_fromMap | 1843089 | 0.54 |
| location_toMap | 701179 | 1.43 |
| location_fromMap_toMap_roundtrip | 504763 | 1.98 |
| location_copyWithCoords | 12860120 | 0.08 |
| geofence_fromMap_circular | 4428222 | 0.23 |
| geofence_fromMap_polygon | 1636894 | 0.61 |
| delta_encode_10 | 32615 | 30.66 |
| delta_decode_10 | 95310 | 10.49 |
| delta_encode_100 | 4407 | 226.92 |
| delta_decode_100 | 10940 | 91.41 |
| delta_encode_500 | 786 | 1272.69 |
| delta_decode_500 | 2027 | 493.40 |
| delta_roundtrip_100 | 3141 | 318.33 |
| battery_budget_single_sample | 10067014 | 0.10 |
| battery_budget_60_samples | 294201 | 3.40 |
| battery_budget_heavy_drain | 148664 | 6.73 |
| carbon_trip_100_locations | 105990 | 9.43 |
| carbon_onLocation | 4415213 | 0.23 |
| carbon_setActivity | 10603782 | 0.09 |
| carbon_cumulative_report | 2793238 | 0.36 |
| persist_decider_location | 22286042 | 0.04 |
| persist_decider_geofence | 22307549 | 0.04 |
| config_fromMap | 488534 | 2.05 |
| config_toMap | 172575 | 5.79 |
| config_roundtrip | 127994 | 7.81 |
| state_fromMap | 474324 | 2.11 |
| state_toMap | 167593 | 5.97 |


### 2026-03-16 — Commit a00e88f

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7367371 | 0.14 |
| kalman_process_100_fixes | 94638 | 10.57 |
| kalman_process_1k_fixes | 9569 | 104.50 |
| kalman_reset | 6736581 | 0.15 |
| haversine_single | 9058464 | 0.11 |
| haversine_1k_pairs | 16275 | 61.45 |
| pip_4v | 13384723 | 0.07 |
| pip_10v | 10135259 | 0.10 |
| pip_50v | 3775327 | 0.26 |
| pip_100v | 1965668 | 0.51 |
| pip_500v | 426633 | 2.34 |
| geofence_eval_10_circular | 679648 | 1.47 |
| geofence_eval_100_circular | 74598 | 13.41 |
| geofence_eval_500_circular | 14243 | 70.21 |
| geofence_eval_10_polygon_6v | 418753 | 2.39 |
| geofence_eval_50_polygon_6v | 83991 | 11.91 |
| processor_1k_fixes | 9893 | 101.08 |
| processor_1k_adaptive | 9337 | 107.10 |
| trip_manager_5k_waypoints | 66 | 15260.87 |
| schedule_parse | 2883627 | 0.35 |
| schedule_matches | 118969 | 8.41 |
| schedule_isWithin_5_entries | 110312 | 9.07 |
| adaptive_compute | 13648009 | 0.07 |
| location_fromMap | 1764997 | 0.57 |
| location_toMap | 685808 | 1.46 |
| location_fromMap_toMap_roundtrip | 504428 | 1.98 |
| location_copyWithCoords | 12383801 | 0.08 |
| geofence_fromMap_circular | 4514324 | 0.22 |
| geofence_fromMap_polygon | 1527488 | 0.65 |
| delta_encode_10 | 29417 | 33.99 |
| delta_decode_10 | 98017 | 10.20 |
| delta_encode_100 | 3966 | 252.15 |
| delta_decode_100 | 11053 | 90.48 |
| delta_encode_500 | 849 | 1178.27 |
| delta_decode_500 | 2407 | 415.46 |
| delta_roundtrip_100 | 2901 | 344.67 |
| battery_budget_single_sample | 9419853 | 0.11 |
| battery_budget_60_samples | 252512 | 3.96 |
| battery_budget_heavy_drain | 125782 | 7.95 |
| carbon_trip_100_locations | 97064 | 10.30 |
| carbon_onLocation | 4386739 | 0.23 |
| carbon_setActivity | 9812423 | 0.10 |
| carbon_cumulative_report | 2641983 | 0.38 |
| persist_decider_location | 20151400 | 0.05 |
| persist_decider_geofence | 20212244 | 0.05 |
| config_fromMap | 496088 | 2.02 |
| config_toMap | 166776 | 6.00 |
| config_roundtrip | 123035 | 8.13 |
| state_fromMap | 458643 | 2.18 |
| state_toMap | 156797 | 6.38 |


### 2026-03-16 — Commit 8e269d9

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7412848 | 0.13 |
| kalman_process_100_fixes | 96852 | 10.33 |
| kalman_process_1k_fixes | 9659 | 103.53 |
| kalman_reset | 6935178 | 0.14 |
| haversine_single | 8926508 | 0.11 |
| haversine_1k_pairs | 17124 | 58.40 |
| pip_4v | 12574770 | 0.08 |
| pip_10v | 9577520 | 0.10 |
| pip_50v | 3758039 | 0.27 |
| pip_100v | 2075653 | 0.48 |
| pip_500v | 423918 | 2.36 |
| geofence_eval_10_circular | 682088 | 1.47 |
| geofence_eval_100_circular | 75086 | 13.32 |
| geofence_eval_500_circular | 14434 | 69.28 |
| geofence_eval_10_polygon_6v | 420080 | 2.38 |
| geofence_eval_50_polygon_6v | 83521 | 11.97 |
| processor_1k_fixes | 10039 | 99.61 |
| processor_1k_adaptive | 9524 | 105.00 |
| trip_manager_5k_waypoints | 67 | 15004.11 |
| schedule_parse | 2912888 | 0.34 |
| schedule_matches | 118620 | 8.43 |
| schedule_isWithin_5_entries | 112625 | 8.88 |
| adaptive_compute | 13533265 | 0.07 |
| location_fromMap | 1815259 | 0.55 |
| location_toMap | 695209 | 1.44 |
| location_fromMap_toMap_roundtrip | 504707 | 1.98 |
| location_copyWithCoords | 12571830 | 0.08 |
| geofence_fromMap_circular | 4578055 | 0.22 |
| geofence_fromMap_polygon | 1616747 | 0.62 |
| delta_encode_10 | 17279 | 57.88 |
| delta_decode_10 | 76362 | 13.10 |
| delta_encode_100 | 2537 | 394.20 |
| delta_decode_100 | 10532 | 94.95 |
| delta_encode_500 | 515 | 1939.88 |
| delta_decode_500 | 2118 | 472.19 |
| delta_roundtrip_100 | 2061 | 485.26 |
| battery_budget_single_sample | 9507011 | 0.11 |
| battery_budget_60_samples | 257537 | 3.88 |
| battery_budget_heavy_drain | 130769 | 7.65 |
| carbon_trip_100_locations | 100086 | 9.99 |
| carbon_onLocation | 4087584 | 0.24 |
| carbon_setActivity | 9964930 | 0.10 |
| carbon_cumulative_report | 2667784 | 0.37 |
| persist_decider_location | 20173429 | 0.05 |
| persist_decider_geofence | 20188853 | 0.05 |
| config_fromMap | 512225 | 1.95 |
| config_toMap | 168187 | 5.95 |
| config_roundtrip | 125362 | 7.98 |
| state_fromMap | 481314 | 2.08 |
| state_toMap | 160145 | 6.24 |


### 2026-03-16 — Commit 687fd18

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7398699 | 0.14 |
| kalman_process_100_fixes | 96187 | 10.40 |
| kalman_process_1k_fixes | 9716 | 102.92 |
| kalman_reset | 6848223 | 0.15 |
| haversine_single | 9073566 | 0.11 |
| haversine_1k_pairs | 17256 | 57.95 |
| pip_4v | 13052755 | 0.08 |
| pip_10v | 9743077 | 0.10 |
| pip_50v | 3819879 | 0.26 |
| pip_100v | 2017845 | 0.50 |
| pip_500v | 419067 | 2.39 |
| geofence_eval_10_circular | 684738 | 1.46 |
| geofence_eval_100_circular | 74757 | 13.38 |
| geofence_eval_500_circular | 14377 | 69.55 |
| geofence_eval_10_polygon_6v | 419007 | 2.39 |
| geofence_eval_50_polygon_6v | 83867 | 11.92 |
| processor_1k_fixes | 9992 | 100.08 |
| processor_1k_adaptive | 9396 | 106.43 |
| trip_manager_5k_waypoints | 66 | 15174.21 |
| schedule_parse | 2859955 | 0.35 |
| schedule_matches | 118837 | 8.41 |
| schedule_isWithin_5_entries | 113270 | 8.83 |
| adaptive_compute | 13635796 | 0.07 |
| location_fromMap | 1799341 | 0.56 |
| location_toMap | 696336 | 1.44 |
| location_fromMap_toMap_roundtrip | 510469 | 1.96 |
| location_copyWithCoords | 12602437 | 0.08 |
| geofence_fromMap_circular | 4538888 | 0.22 |
| geofence_fromMap_polygon | 1584477 | 0.63 |
| delta_encode_10 | 18694 | 53.49 |
| delta_decode_10 | 77597 | 12.89 |
| delta_encode_100 | 2645 | 378.14 |
| delta_decode_100 | 10834 | 92.30 |
| delta_encode_500 | 562 | 1780.58 |
| delta_decode_500 | 2331 | 428.98 |
| delta_roundtrip_100 | 2121 | 471.48 |
| battery_budget_single_sample | 9297958 | 0.11 |
| battery_budget_60_samples | 256067 | 3.91 |
| battery_budget_heavy_drain | 129465 | 7.72 |
| carbon_trip_100_locations | 96932 | 10.32 |
| carbon_onLocation | 4371642 | 0.23 |
| carbon_setActivity | 9987967 | 0.10 |
| carbon_cumulative_report | 2715792 | 0.37 |
| persist_decider_location | 19710936 | 0.05 |
| persist_decider_geofence | 19217153 | 0.05 |
| config_fromMap | 499513 | 2.00 |
| config_toMap | 168847 | 5.92 |
| config_roundtrip | 125217 | 7.99 |
| state_fromMap | 470431 | 2.13 |
| state_toMap | 158557 | 6.31 |


