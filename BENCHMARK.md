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


### 2026-03-15 — Commit efceec9

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7361758 | 0.14 |
| kalman_process_100_fixes | 95518 | 10.47 |
| kalman_process_1k_fixes | 9489 | 105.38 |
| kalman_reset | 6810679 | 0.15 |
| haversine_single | 8965091 | 0.11 |
| haversine_1k_pairs | 17157 | 58.28 |
| pip_4v | 13521141 | 0.07 |
| pip_10v | 10022236 | 0.10 |
| pip_50v | 3840505 | 0.26 |
| pip_100v | 2131113 | 0.47 |
| pip_500v | 424299 | 2.36 |
| geofence_eval_10_circular | 672523 | 1.49 |
| geofence_eval_100_circular | 74329 | 13.45 |
| geofence_eval_500_circular | 14354 | 69.67 |
| geofence_eval_10_polygon_6v | 417944 | 2.39 |
| geofence_eval_50_polygon_6v | 85039 | 11.76 |
| processor_1k_fixes | 9897 | 101.04 |
| processor_1k_adaptive | 9269 | 107.89 |
| trip_manager_5k_waypoints | 65 | 15339.73 |
| schedule_parse | 2929673 | 0.34 |
| schedule_matches | 118545 | 8.44 |
| schedule_isWithin_5_entries | 112732 | 8.87 |
| adaptive_compute | 13835972 | 0.07 |
| location_fromMap | 1828186 | 0.55 |
| location_toMap | 704708 | 1.42 |
| location_fromMap_toMap_roundtrip | 511115 | 1.96 |
| location_copyWithCoords | 12496814 | 0.08 |
| geofence_fromMap_circular | 4537862 | 0.22 |
| geofence_fromMap_polygon | 1586620 | 0.63 |
| delta_encode_10 | 17585 | 56.87 |
| delta_decode_10 | 77356 | 12.93 |
| delta_encode_100 | 2568 | 389.47 |
| delta_decode_100 | 10782 | 92.75 |
| delta_encode_500 | 530 | 1886.46 |
| delta_decode_500 | 2097 | 476.94 |
| delta_roundtrip_100 | 2073 | 482.44 |
| battery_budget_single_sample | 9488990 | 0.11 |
| battery_budget_60_samples | 254299 | 3.93 |
| battery_budget_heavy_drain | 130004 | 7.69 |
| carbon_trip_100_locations | 97695 | 10.24 |
| carbon_onLocation | 4384223 | 0.23 |
| carbon_setActivity | 9902543 | 0.10 |
| carbon_cumulative_report | 2749673 | 0.36 |
| persist_decider_location | 20161498 | 0.05 |
| persist_decider_geofence | 20244834 | 0.05 |
| config_fromMap | 503182 | 1.99 |
| config_toMap | 170636 | 5.86 |
| config_roundtrip | 124827 | 8.01 |
| state_fromMap | 444943 | 2.25 |
| state_toMap | 159923 | 6.25 |


### 2026-03-15 — Commit 0906cd7

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7329603 | 0.14 |
| kalman_process_100_fixes | 95909 | 10.43 |
| kalman_process_1k_fixes | 9491 | 105.36 |
| kalman_reset | 6693203 | 0.15 |
| haversine_single | 9076929 | 0.11 |
| haversine_1k_pairs | 17077 | 58.56 |
| pip_4v | 13042209 | 0.08 |
| pip_10v | 10204450 | 0.10 |
| pip_50v | 3980584 | 0.25 |
| pip_100v | 2158342 | 0.46 |
| pip_500v | 341036 | 2.93 |
| geofence_eval_10_circular | 679514 | 1.47 |
| geofence_eval_100_circular | 74345 | 13.45 |
| geofence_eval_500_circular | 14271 | 70.07 |
| geofence_eval_10_polygon_6v | 411926 | 2.43 |
| geofence_eval_50_polygon_6v | 83986 | 11.91 |
| processor_1k_fixes | 9871 | 101.30 |
| processor_1k_adaptive | 9301 | 107.51 |
| trip_manager_5k_waypoints | 66 | 15111.82 |
| schedule_parse | 2844093 | 0.35 |
| schedule_matches | 118728 | 8.42 |
| schedule_isWithin_5_entries | 112207 | 8.91 |
| adaptive_compute | 13422947 | 0.07 |
| location_fromMap | 1835506 | 0.54 |
| location_toMap | 690978 | 1.45 |
| location_fromMap_toMap_roundtrip | 499108 | 2.00 |
| location_copyWithCoords | 12827579 | 0.08 |
| geofence_fromMap_circular | 4505738 | 0.22 |
| geofence_fromMap_polygon | 1527181 | 0.65 |
| delta_encode_10 | 17510 | 57.11 |
| delta_decode_10 | 76367 | 13.09 |
| delta_encode_100 | 2554 | 391.61 |
| delta_decode_100 | 10598 | 94.36 |
| delta_encode_500 | 532 | 1878.29 |
| delta_decode_500 | 2077 | 481.47 |
| delta_roundtrip_100 | 2070 | 483.18 |
| battery_budget_single_sample | 9450853 | 0.11 |
| battery_budget_60_samples | 258447 | 3.87 |
| battery_budget_heavy_drain | 129722 | 7.71 |
| carbon_trip_100_locations | 101076 | 9.89 |
| carbon_onLocation | 4241246 | 0.24 |
| carbon_setActivity | 10030175 | 0.10 |
| carbon_cumulative_report | 2767624 | 0.36 |
| persist_decider_location | 20124485 | 0.05 |
| persist_decider_geofence | 20157468 | 0.05 |
| config_fromMap | 498463 | 2.01 |
| config_toMap | 166389 | 6.01 |
| config_roundtrip | 123783 | 8.08 |
| state_fromMap | 470432 | 2.13 |
| state_toMap | 157556 | 6.35 |


### 2026-03-15 — Commit 81a6f46

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7267558 | 0.14 |
| kalman_process_100_fixes | 93672 | 10.68 |
| kalman_process_1k_fixes | 9484 | 105.44 |
| kalman_reset | 6698932 | 0.15 |
| haversine_single | 8855338 | 0.11 |
| haversine_1k_pairs | 16686 | 59.93 |
| pip_4v | 13269896 | 0.08 |
| pip_10v | 9696478 | 0.10 |
| pip_50v | 3893075 | 0.26 |
| pip_100v | 2061853 | 0.49 |
| pip_500v | 414835 | 2.41 |
| geofence_eval_10_circular | 652361 | 1.53 |
| geofence_eval_100_circular | 71484 | 13.99 |
| geofence_eval_500_circular | 13993 | 71.46 |
| geofence_eval_10_polygon_6v | 407936 | 2.45 |
| geofence_eval_50_polygon_6v | 82943 | 12.06 |
| processor_1k_fixes | 9872 | 101.29 |
| processor_1k_adaptive | 9274 | 107.83 |
| trip_manager_5k_waypoints | 66 | 15196.32 |
| schedule_parse | 2855201 | 0.35 |
| schedule_matches | 118885 | 8.41 |
| schedule_isWithin_5_entries | 112323 | 8.90 |
| adaptive_compute | 13330909 | 0.08 |
| location_fromMap | 1782642 | 0.56 |
| location_toMap | 689740 | 1.45 |
| location_fromMap_toMap_roundtrip | 499827 | 2.00 |
| location_copyWithCoords | 12481087 | 0.08 |
| geofence_fromMap_circular | 4534087 | 0.22 |
| geofence_fromMap_polygon | 1563563 | 0.64 |
| delta_encode_10 | 18029 | 55.47 |
| delta_decode_10 | 76258 | 13.11 |
| delta_encode_100 | 2579 | 387.68 |
| delta_decode_100 | 10534 | 94.93 |
| delta_encode_500 | 544 | 1837.25 |
| delta_decode_500 | 2056 | 486.44 |
| delta_roundtrip_100 | 2097 | 476.97 |
| battery_budget_single_sample | 9329966 | 0.11 |
| battery_budget_60_samples | 254233 | 3.93 |
| battery_budget_heavy_drain | 120911 | 8.27 |
| carbon_trip_100_locations | 97433 | 10.26 |
| carbon_onLocation | 4297169 | 0.23 |
| carbon_setActivity | 9847657 | 0.10 |
| carbon_cumulative_report | 2670896 | 0.37 |
| persist_decider_location | 20176900 | 0.05 |
| persist_decider_geofence | 20117933 | 0.05 |
| config_fromMap | 476885 | 2.10 |
| config_toMap | 166361 | 6.01 |
| config_roundtrip | 123234 | 8.11 |
| state_fromMap | 455909 | 2.19 |
| state_toMap | 155988 | 6.41 |


### 2026-03-15 — Commit 3685765

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7397079 | 0.14 |
| kalman_process_100_fixes | 96371 | 10.38 |
| kalman_process_1k_fixes | 9593 | 104.24 |
| kalman_reset | 6742668 | 0.15 |
| haversine_single | 9180806 | 0.11 |
| haversine_1k_pairs | 17131 | 58.37 |
| pip_4v | 13414624 | 0.07 |
| pip_10v | 10191375 | 0.10 |
| pip_50v | 3612134 | 0.28 |
| pip_100v | 2048414 | 0.49 |
| pip_500v | 416117 | 2.40 |
| geofence_eval_10_circular | 666311 | 1.50 |
| geofence_eval_100_circular | 73852 | 13.54 |
| geofence_eval_500_circular | 14314 | 69.86 |
| geofence_eval_10_polygon_6v | 412121 | 2.43 |
| geofence_eval_50_polygon_6v | 84036 | 11.90 |
| processor_1k_fixes | 9904 | 100.97 |
| processor_1k_adaptive | 9354 | 106.90 |
| trip_manager_5k_waypoints | 66 | 15101.86 |
| schedule_parse | 2896956 | 0.35 |
| schedule_matches | 119456 | 8.37 |
| schedule_isWithin_5_entries | 114389 | 8.74 |
| adaptive_compute | 13358972 | 0.07 |
| location_fromMap | 1813001 | 0.55 |
| location_toMap | 700508 | 1.43 |
| location_fromMap_toMap_roundtrip | 504253 | 1.98 |
| location_copyWithCoords | 12708676 | 0.08 |
| geofence_fromMap_circular | 4512377 | 0.22 |
| geofence_fromMap_polygon | 1613988 | 0.62 |
| delta_encode_10 | 18055 | 55.38 |
| delta_decode_10 | 78088 | 12.81 |
| delta_encode_100 | 2597 | 385.10 |
| delta_decode_100 | 10884 | 91.88 |
| delta_encode_500 | 543 | 1841.59 |
| delta_decode_500 | 2111 | 473.63 |
| delta_roundtrip_100 | 2107 | 474.60 |
| battery_budget_single_sample | 9506974 | 0.11 |
| battery_budget_60_samples | 256165 | 3.90 |
| battery_budget_heavy_drain | 130199 | 7.68 |
| carbon_trip_100_locations | 97902 | 10.21 |
| carbon_onLocation | 4371367 | 0.23 |
| carbon_setActivity | 10019248 | 0.10 |
| carbon_cumulative_report | 2735552 | 0.37 |
| persist_decider_location | 20126892 | 0.05 |
| persist_decider_geofence | 20019284 | 0.05 |
| config_fromMap | 486473 | 2.06 |
| config_toMap | 166672 | 6.00 |
| config_roundtrip | 124064 | 8.06 |
| state_fromMap | 463292 | 2.16 |
| state_toMap | 157418 | 6.35 |


### 2026-03-15 — Commit 3b52ecc

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7262332 | 0.14 |
| kalman_process_100_fixes | 96202 | 10.39 |
| kalman_process_1k_fixes | 9759 | 102.47 |
| kalman_reset | 6802569 | 0.15 |
| haversine_single | 8946449 | 0.11 |
| haversine_1k_pairs | 17180 | 58.21 |
| pip_4v | 13241673 | 0.08 |
| pip_10v | 10348595 | 0.10 |
| pip_50v | 4017517 | 0.25 |
| pip_100v | 2058950 | 0.49 |
| pip_500v | 426109 | 2.35 |
| geofence_eval_10_circular | 676645 | 1.48 |
| geofence_eval_100_circular | 74591 | 13.41 |
| geofence_eval_500_circular | 14474 | 69.09 |
| geofence_eval_10_polygon_6v | 414859 | 2.41 |
| geofence_eval_50_polygon_6v | 85121 | 11.75 |
| processor_1k_fixes | 9931 | 100.70 |
| processor_1k_adaptive | 9248 | 108.14 |
| trip_manager_5k_waypoints | 68 | 14631.08 |
| schedule_parse | 2901428 | 0.34 |
| schedule_matches | 121569 | 8.23 |
| schedule_isWithin_5_entries | 116305 | 8.60 |
| adaptive_compute | 13568675 | 0.07 |
| location_fromMap | 1793679 | 0.56 |
| location_toMap | 692932 | 1.44 |
| location_fromMap_toMap_roundtrip | 506516 | 1.97 |
| location_copyWithCoords | 12710902 | 0.08 |
| geofence_fromMap_circular | 4495317 | 0.22 |
| geofence_fromMap_polygon | 1593577 | 0.63 |
| delta_encode_10 | 18006 | 55.54 |
| delta_decode_10 | 77305 | 12.94 |
| delta_encode_100 | 2549 | 392.25 |
| delta_decode_100 | 10795 | 92.63 |
| delta_encode_500 | 547 | 1827.40 |
| delta_decode_500 | 2043 | 489.49 |
| delta_roundtrip_100 | 2105 | 475.08 |
| battery_budget_single_sample | 9350539 | 0.11 |
| battery_budget_60_samples | 258737 | 3.86 |
| battery_budget_heavy_drain | 129768 | 7.71 |
| carbon_trip_100_locations | 95234 | 10.50 |
| carbon_onLocation | 4402485 | 0.23 |
| carbon_setActivity | 9780706 | 0.10 |
| carbon_cumulative_report | 2681170 | 0.37 |
| persist_decider_location | 20130840 | 0.05 |
| persist_decider_geofence | 20300809 | 0.05 |
| config_fromMap | 480084 | 2.08 |
| config_toMap | 167994 | 5.95 |
| config_roundtrip | 124261 | 8.05 |
| state_fromMap | 460162 | 2.17 |
| state_toMap | 159125 | 6.28 |


### 2026-03-15 — Commit 039be99

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7236393 | 0.14 |
| kalman_process_100_fixes | 95652 | 10.45 |
| kalman_process_1k_fixes | 9460 | 105.71 |
| kalman_reset | 6720138 | 0.15 |
| haversine_single | 8935163 | 0.11 |
| haversine_1k_pairs | 17030 | 58.72 |
| pip_4v | 13543552 | 0.07 |
| pip_10v | 10240317 | 0.10 |
| pip_50v | 3828968 | 0.26 |
| pip_100v | 2102515 | 0.48 |
| pip_500v | 422457 | 2.37 |
| geofence_eval_10_circular | 661223 | 1.51 |
| geofence_eval_100_circular | 73695 | 13.57 |
| geofence_eval_500_circular | 14122 | 70.81 |
| geofence_eval_10_polygon_6v | 414208 | 2.41 |
| geofence_eval_50_polygon_6v | 84363 | 11.85 |
| processor_1k_fixes | 9492 | 105.35 |
| processor_1k_adaptive | 9243 | 108.19 |
| trip_manager_5k_waypoints | 66 | 15077.91 |
| schedule_parse | 2884878 | 0.35 |
| schedule_matches | 117677 | 8.50 |
| schedule_isWithin_5_entries | 112988 | 8.85 |
| adaptive_compute | 13279333 | 0.08 |
| location_fromMap | 1839097 | 0.54 |
| location_toMap | 695897 | 1.44 |
| location_fromMap_toMap_roundtrip | 507856 | 1.97 |
| location_copyWithCoords | 12545499 | 0.08 |
| geofence_fromMap_circular | 4528906 | 0.22 |
| geofence_fromMap_polygon | 1623307 | 0.62 |
| delta_encode_10 | 18115 | 55.20 |
| delta_decode_10 | 78049 | 12.81 |
| delta_encode_100 | 2621 | 381.51 |
| delta_decode_100 | 10639 | 93.99 |
| delta_encode_500 | 547 | 1826.68 |
| delta_decode_500 | 2269 | 440.79 |
| delta_roundtrip_100 | 2093 | 477.84 |
| battery_budget_single_sample | 9434619 | 0.11 |
| battery_budget_60_samples | 256684 | 3.90 |
| battery_budget_heavy_drain | 130055 | 7.69 |
| carbon_trip_100_locations | 98621 | 10.14 |
| carbon_onLocation | 4402189 | 0.23 |
| carbon_setActivity | 9827277 | 0.10 |
| carbon_cumulative_report | 2736212 | 0.37 |
| persist_decider_location | 20012705 | 0.05 |
| persist_decider_geofence | 20032180 | 0.05 |
| config_fromMap | 486097 | 2.06 |
| config_toMap | 169089 | 5.91 |
| config_roundtrip | 123956 | 8.07 |
| state_fromMap | 462346 | 2.16 |
| state_toMap | 160000 | 6.25 |


### 2026-03-15 — Commit 5008e61

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7202326 | 0.14 |
| kalman_process_100_fixes | 94495 | 10.58 |
| kalman_process_1k_fixes | 9529 | 104.95 |
| kalman_reset | 6790776 | 0.15 |
| haversine_single | 8992616 | 0.11 |
| haversine_1k_pairs | 17175 | 58.23 |
| pip_4v | 13236304 | 0.08 |
| pip_10v | 10145222 | 0.10 |
| pip_50v | 3932974 | 0.25 |
| pip_100v | 2064596 | 0.48 |
| pip_500v | 417880 | 2.39 |
| geofence_eval_10_circular | 683225 | 1.46 |
| geofence_eval_100_circular | 75551 | 13.24 |
| geofence_eval_500_circular | 14441 | 69.25 |
| geofence_eval_10_polygon_6v | 417370 | 2.40 |
| geofence_eval_50_polygon_6v | 85540 | 11.69 |
| processor_1k_fixes | 9830 | 101.73 |
| processor_1k_adaptive | 9426 | 106.09 |
| trip_manager_5k_waypoints | 66 | 15103.63 |
| schedule_parse | 2793594 | 0.36 |
| schedule_matches | 118136 | 8.46 |
| schedule_isWithin_5_entries | 113069 | 8.84 |
| adaptive_compute | 13761745 | 0.07 |
| location_fromMap | 1792248 | 0.56 |
| location_toMap | 700225 | 1.43 |
| location_fromMap_toMap_roundtrip | 510130 | 1.96 |
| location_copyWithCoords | 12723961 | 0.08 |
| geofence_fromMap_circular | 4421987 | 0.23 |
| geofence_fromMap_polygon | 1570617 | 0.64 |


### 2026-03-15 — Commit 93528c8

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7357242 | 0.14 |
| kalman_process_100_fixes | 93367 | 10.71 |
| kalman_process_1k_fixes | 9263 | 107.96 |
| kalman_reset | 6784095 | 0.15 |
| haversine_single | 8971407 | 0.11 |
| haversine_1k_pairs | 16818 | 59.46 |
| pip_4v | 13577627 | 0.07 |
| pip_10v | 9858340 | 0.10 |
| pip_50v | 3822053 | 0.26 |
| pip_100v | 2033862 | 0.49 |
| pip_500v | 416373 | 2.40 |
| geofence_eval_10_circular | 654889 | 1.53 |
| geofence_eval_100_circular | 72165 | 13.86 |
| geofence_eval_500_circular | 14000 | 71.43 |
| geofence_eval_10_polygon_6v | 413862 | 2.42 |
| geofence_eval_50_polygon_6v | 83581 | 11.96 |
| processor_1k_fixes | 9742 | 102.65 |
| processor_1k_adaptive | 9302 | 107.51 |
| trip_manager_5k_waypoints | 66 | 15240.20 |
| schedule_parse | 2824196 | 0.35 |
| schedule_matches | 118770 | 8.42 |
| schedule_isWithin_5_entries | 112215 | 8.91 |
| adaptive_compute | 13697609 | 0.07 |
| location_fromMap | 1791329 | 0.56 |
| location_toMap | 693475 | 1.44 |
| location_fromMap_toMap_roundtrip | 508520 | 1.97 |
| location_copyWithCoords | 11963810 | 0.08 |
| geofence_fromMap_circular | 4403004 | 0.23 |
| geofence_fromMap_polygon | 1562084 | 0.64 |


### 2026-03-14 — Commit 669b228

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7181911 | 0.14 |
| kalman_process_100_fixes | 92337 | 10.83 |
| kalman_process_1k_fixes | 9301 | 107.51 |
| kalman_reset | 6518829 | 0.15 |
| haversine_single | 9118850 | 0.11 |
| haversine_1k_pairs | 18241 | 54.82 |
| pip_4v | 13131111 | 0.08 |
| pip_10v | 10196045 | 0.10 |
| pip_50v | 3979673 | 0.25 |
| pip_100v | 2210704 | 0.45 |
| pip_500v | 443942 | 2.25 |
| geofence_eval_10_circular | 681350 | 1.47 |
| geofence_eval_100_circular | 76035 | 13.15 |
| geofence_eval_500_circular | 14480 | 69.06 |
| geofence_eval_10_polygon_6v | 439361 | 2.28 |
| geofence_eval_50_polygon_6v | 87253 | 11.46 |
| processor_1k_fixes | 10415 | 96.01 |
| processor_1k_adaptive | 9981 | 100.19 |
| trip_manager_5k_waypoints | 140 | 7147.51 |
| schedule_parse | 3031096 | 0.33 |
| schedule_matches | 255243 | 3.92 |
| schedule_isWithin_5_entries | 228896 | 4.37 |
| adaptive_compute | 13148659 | 0.08 |
| location_fromMap | 1707544 | 0.59 |
| location_toMap | 582612 | 1.72 |
| location_fromMap_toMap_roundtrip | 447268 | 2.24 |
| location_copyWithCoords | 11766684 | 0.08 |
| geofence_fromMap_circular | 4125494 | 0.24 |
| geofence_fromMap_polygon | 1509932 | 0.66 |


### 2026-03-14 — Commit d13fa1b

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 4989620 | 0.20 |
| kalman_process_100_fixes | 85197 | 11.74 |
| kalman_process_1k_fixes | 9209 | 108.59 |
| kalman_reset | 5504272 | 0.18 |
| haversine_single | 8620635 | 0.12 |
| haversine_1k_pairs | 17534 | 57.03 |
| pip_4v | 13594179 | 0.07 |
| pip_10v | 10287184 | 0.10 |
| pip_50v | 4054128 | 0.25 |
| pip_100v | 2202634 | 0.45 |
| pip_500v | 441035 | 2.27 |
| geofence_eval_10_circular | 647384 | 1.54 |
| geofence_eval_100_circular | 73795 | 13.55 |
| geofence_eval_500_circular | 13896 | 71.96 |
| geofence_eval_10_polygon_6v | 381775 | 2.62 |
| geofence_eval_50_polygon_6v | 77999 | 12.82 |
| processor_1k_fixes | 9829 | 101.74 |
| processor_1k_adaptive | 9767 | 102.39 |
| trip_manager_5k_waypoints | 136 | 7355.33 |
| schedule_parse | 2962725 | 0.34 |
| schedule_matches | 257324 | 3.89 |
| schedule_isWithin_5_entries | 227161 | 4.40 |
| adaptive_compute | 12861022 | 0.08 |
| location_fromMap | 1640100 | 0.61 |
| location_toMap | 491820 | 2.03 |
| location_fromMap_toMap_roundtrip | 405139 | 2.47 |
| location_copyWithCoords | 11588754 | 0.09 |
| geofence_fromMap_circular | 4024551 | 0.25 |
| geofence_fromMap_polygon | 1415267 | 0.71 |


### 2026-03-14 — Commit 42a4aa1

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7214408 | 0.14 |
| kalman_process_100_fixes | 94659 | 10.56 |
| kalman_process_1k_fixes | 9343 | 107.03 |
| kalman_reset | 6623655 | 0.15 |
| haversine_single | 9064548 | 0.11 |
| haversine_1k_pairs | 17178 | 58.22 |
| pip_4v | 13495996 | 0.07 |
| pip_10v | 10244742 | 0.10 |
| pip_50v | 3979604 | 0.25 |
| pip_100v | 2148513 | 0.47 |
| pip_500v | 417308 | 2.40 |
| geofence_eval_10_circular | 666596 | 1.50 |
| geofence_eval_100_circular | 72693 | 13.76 |
| geofence_eval_500_circular | 14252 | 70.16 |
| geofence_eval_10_polygon_6v | 417156 | 2.40 |
| geofence_eval_50_polygon_6v | 84111 | 11.89 |
| processor_1k_fixes | 9648 | 103.65 |
| processor_1k_adaptive | 9261 | 107.98 |
| trip_manager_5k_waypoints | 65 | 15355.79 |
| schedule_parse | 2823871 | 0.35 |
| schedule_matches | 118341 | 8.45 |
| schedule_isWithin_5_entries | 113819 | 8.79 |
| adaptive_compute | 13668106 | 0.07 |
| location_fromMap | 1823320 | 0.55 |
| location_toMap | 694621 | 1.44 |
| location_fromMap_toMap_roundtrip | 507774 | 1.97 |
| location_copyWithCoords | 12370636 | 0.08 |
| geofence_fromMap_circular | 4460309 | 0.22 |
| geofence_fromMap_polygon | 1586316 | 0.63 |


### 2026-03-14 — Commit 239894a

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 6960902 | 0.14 |
| kalman_process_100_fixes | 101975 | 9.81 |
| kalman_process_1k_fixes | 10343 | 96.68 |
| kalman_reset | 6627259 | 0.15 |
| haversine_single | 8288087 | 0.12 |
| haversine_1k_pairs | 15043 | 66.48 |
| pip_4v | 12858489 | 0.08 |
| pip_10v | 9211423 | 0.11 |
| pip_50v | 3728563 | 0.27 |
| pip_100v | 2072440 | 0.48 |
| pip_500v | 373797 | 2.68 |
| geofence_eval_10_circular | 677267 | 1.48 |
| geofence_eval_100_circular | 73136 | 13.67 |
| geofence_eval_500_circular | 14327 | 69.80 |
| geofence_eval_10_polygon_6v | 420454 | 2.38 |
| geofence_eval_50_polygon_6v | 84048 | 11.90 |
| processor_1k_fixes | 9200 | 108.70 |
| processor_1k_adaptive | 8626 | 115.93 |
| trip_manager_5k_waypoints | 58 | 17342.39 |
| schedule_parse | 2881374 | 0.35 |
| schedule_matches | 104545 | 9.57 |
| schedule_isWithin_5_entries | 100471 | 9.95 |
| adaptive_compute | 12648678 | 0.08 |
| location_fromMap | 1745819 | 0.57 |
| location_toMap | 690497 | 1.45 |
| location_fromMap_toMap_roundtrip | 497710 | 2.01 |
| location_copyWithCoords | 11674809 | 0.09 |
| geofence_fromMap_circular | 4348534 | 0.23 |
| geofence_fromMap_polygon | 1567574 | 0.64 |


### 2026-03-14 — Commit 2b7bbbb

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 6781868 | 0.15 |
| kalman_process_100_fixes | 96078 | 10.41 |
| kalman_process_1k_fixes | 9533 | 104.89 |
| kalman_reset | 6668683 | 0.15 |
| haversine_single | 8798238 | 0.11 |
| haversine_1k_pairs | 16666 | 60.00 |
| pip_4v | 13197594 | 0.08 |
| pip_10v | 9879532 | 0.10 |
| pip_50v | 3646932 | 0.27 |
| pip_100v | 2024905 | 0.49 |
| pip_500v | 421205 | 2.37 |
| geofence_eval_10_circular | 656260 | 1.52 |
| geofence_eval_100_circular | 72197 | 13.85 |
| geofence_eval_500_circular | 13939 | 71.74 |
| geofence_eval_10_polygon_6v | 407941 | 2.45 |
| geofence_eval_50_polygon_6v | 82824 | 12.07 |
| processor_1k_fixes | 9350 | 106.95 |
| processor_1k_adaptive | 8787 | 113.81 |
| trip_manager_5k_waypoints | 65 | 15361.14 |
| schedule_parse | 2776036 | 0.36 |
| schedule_matches | 116826 | 8.56 |
| schedule_isWithin_5_entries | 112386 | 8.90 |
| adaptive_compute | 13574915 | 0.07 |
| location_fromMap | 1799434 | 0.56 |
| location_toMap | 687697 | 1.45 |
| location_fromMap_toMap_roundtrip | 499125 | 2.00 |
| location_copyWithCoords | 12617994 | 0.08 |
| geofence_fromMap_circular | 4510486 | 0.22 |
| geofence_fromMap_polygon | 1588818 | 0.63 |


### 2026-03-13 — Commit 853bffc

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7366076 | 0.14 |
| kalman_process_100_fixes | 96665 | 10.35 |
| kalman_process_1k_fixes | 9650 | 103.63 |
| kalman_reset | 6754476 | 0.15 |
| haversine_single | 9098333 | 0.11 |
| haversine_1k_pairs | 17212 | 58.10 |
| pip_4v | 12796090 | 0.08 |
| pip_10v | 9974813 | 0.10 |
| pip_50v | 3734640 | 0.27 |
| pip_100v | 2010508 | 0.50 |
| pip_500v | 419194 | 2.39 |
| geofence_eval_10_circular | 699590 | 1.43 |
| geofence_eval_100_circular | 75822 | 13.19 |
| geofence_eval_500_circular | 14651 | 68.25 |
| geofence_eval_10_polygon_6v | 409548 | 2.44 |
| geofence_eval_50_polygon_6v | 82613 | 12.10 |
| processor_1k_fixes | 9991 | 100.09 |
| processor_1k_adaptive | 9439 | 105.94 |
| trip_manager_5k_waypoints | 66 | 15221.59 |
| schedule_parse | 2900697 | 0.34 |
| schedule_matches | 118144 | 8.46 |
| schedule_isWithin_5_entries | 113385 | 8.82 |
| adaptive_compute | 13454227 | 0.07 |
| location_fromMap | 1819444 | 0.55 |
| location_toMap | 698377 | 1.43 |
| location_fromMap_toMap_roundtrip | 511213 | 1.96 |
| location_copyWithCoords | 12781273 | 0.08 |
| geofence_fromMap_circular | 4292311 | 0.23 |
| geofence_fromMap_polygon | 1566522 | 0.64 |


### 2026-03-13 — Commit e8ce364

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7016574 | 0.14 |
| kalman_process_100_fixes | 97793 | 10.23 |
| kalman_process_1k_fixes | 9867 | 101.34 |
| kalman_reset | 6780286 | 0.15 |
| haversine_single | 8966683 | 0.11 |
| haversine_1k_pairs | 18379 | 54.41 |
| pip_4v | 13584325 | 0.07 |
| pip_10v | 10267811 | 0.10 |
| pip_50v | 3915805 | 0.26 |
| pip_100v | 2150026 | 0.47 |
| pip_500v | 441911 | 2.26 |
| geofence_eval_10_circular | 682716 | 1.46 |
| geofence_eval_100_circular | 75722 | 13.21 |
| geofence_eval_500_circular | 14433 | 69.28 |
| geofence_eval_10_polygon_6v | 440974 | 2.27 |
| geofence_eval_50_polygon_6v | 88639 | 11.28 |
| processor_1k_fixes | 10445 | 95.74 |
| processor_1k_adaptive | 9982 | 100.18 |
| trip_manager_5k_waypoints | 141 | 7116.10 |
| schedule_parse | 3088947 | 0.32 |
| schedule_matches | 258125 | 3.87 |
| schedule_isWithin_5_entries | 231561 | 4.32 |
| adaptive_compute | 13685496 | 0.07 |
| location_fromMap | 1763188 | 0.57 |
| location_toMap | 637774 | 1.57 |
| location_fromMap_toMap_roundtrip | 482641 | 2.07 |
| location_copyWithCoords | 12280186 | 0.08 |
| geofence_fromMap_circular | 4491496 | 0.22 |
| geofence_fromMap_polygon | 1632713 | 0.61 |


### 2026-03-13 — Commit dc871cd

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7313728 | 0.14 |
| kalman_process_100_fixes | 94356 | 10.60 |
| kalman_process_1k_fixes | 9834 | 101.69 |
| kalman_reset | 6820793 | 0.15 |
| haversine_single | 8992509 | 0.11 |
| haversine_1k_pairs | 17077 | 58.56 |
| pip_4v | 13037140 | 0.08 |
| pip_10v | 9271341 | 0.11 |
| pip_50v | 3855968 | 0.26 |
| pip_100v | 2052299 | 0.49 |
| pip_500v | 426797 | 2.34 |
| geofence_eval_10_circular | 669396 | 1.49 |
| geofence_eval_100_circular | 73674 | 13.57 |
| geofence_eval_500_circular | 14116 | 70.84 |
| geofence_eval_10_polygon_6v | 418701 | 2.39 |
| geofence_eval_50_polygon_6v | 84315 | 11.86 |
| processor_1k_fixes | 9529 | 104.94 |
| processor_1k_adaptive | 9303 | 107.50 |
| trip_manager_5k_waypoints | 66 | 15091.80 |
| schedule_parse | 2908122 | 0.34 |
| schedule_matches | 119247 | 8.39 |
| schedule_isWithin_5_entries | 113932 | 8.78 |
| adaptive_compute | 13930094 | 0.07 |
| location_fromMap | 1818358 | 0.55 |
| location_toMap | 696940 | 1.43 |
| location_fromMap_toMap_roundtrip | 511029 | 1.96 |
| location_copyWithCoords | 12772818 | 0.08 |
| geofence_fromMap_circular | 4528967 | 0.22 |
| geofence_fromMap_polygon | 1601184 | 0.62 |


### 2026-03-13 — Commit ae98328

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 6947704 | 0.14 |
| kalman_process_100_fixes | 95213 | 10.50 |
| kalman_process_1k_fixes | 9489 | 105.39 |
| kalman_reset | 6918146 | 0.14 |
| haversine_single | 8953152 | 0.11 |
| haversine_1k_pairs | 16927 | 59.08 |
| pip_4v | 13428438 | 0.07 |
| pip_10v | 9924773 | 0.10 |
| pip_50v | 3608312 | 0.28 |
| pip_100v | 2059287 | 0.49 |
| pip_500v | 427273 | 2.34 |
| geofence_eval_10_circular | 680272 | 1.47 |
| geofence_eval_100_circular | 75210 | 13.30 |
| geofence_eval_500_circular | 14491 | 69.01 |
| geofence_eval_10_polygon_6v | 421043 | 2.38 |
| geofence_eval_50_polygon_6v | 85041 | 11.76 |
| processor_1k_fixes | 9895 | 101.06 |
| processor_1k_adaptive | 9408 | 106.29 |
| trip_manager_5k_waypoints | 66 | 15193.11 |
| schedule_parse | 2907638 | 0.34 |
| schedule_matches | 119013 | 8.40 |
| schedule_isWithin_5_entries | 112749 | 8.87 |
| adaptive_compute | 13399623 | 0.07 |
| location_fromMap | 1792147 | 0.56 |
| location_toMap | 691148 | 1.45 |
| location_fromMap_toMap_roundtrip | 505435 | 1.98 |
| location_copyWithCoords | 12853872 | 0.08 |
| geofence_fromMap_circular | 4524323 | 0.22 |
| geofence_fromMap_polygon | 1523720 | 0.66 |


### 2026-03-13 — Commit fd96a55

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7240757 | 0.14 |
| kalman_process_100_fixes | 94504 | 10.58 |
| kalman_process_1k_fixes | 9492 | 105.35 |
| kalman_reset | 6843528 | 0.15 |
| haversine_single | 9041334 | 0.11 |
| haversine_1k_pairs | 18550 | 53.91 |
| pip_4v | 13421294 | 0.07 |
| pip_10v | 10169703 | 0.10 |
| pip_50v | 4034645 | 0.25 |
| pip_100v | 2219844 | 0.45 |
| pip_500v | 441161 | 2.27 |
| geofence_eval_10_circular | 685083 | 1.46 |
| geofence_eval_100_circular | 75846 | 13.18 |
| geofence_eval_500_circular | 14310 | 69.88 |
| geofence_eval_10_polygon_6v | 445451 | 2.24 |
| geofence_eval_50_polygon_6v | 89309 | 11.20 |
| processor_1k_fixes | 10501 | 95.23 |
| processor_1k_adaptive | 9910 | 100.90 |
| trip_manager_5k_waypoints | 140 | 7129.88 |
| schedule_parse | 3241389 | 0.31 |
| schedule_matches | 261968 | 3.82 |
| schedule_isWithin_5_entries | 235041 | 4.25 |
| adaptive_compute | 15148002 | 0.07 |
| location_fromMap | 1831538 | 0.55 |
| location_toMap | 690144 | 1.45 |
| location_fromMap_toMap_roundtrip | 486589 | 2.06 |
| location_copyWithCoords | 12685409 | 0.08 |
| geofence_fromMap_circular | 4311813 | 0.23 |
| geofence_fromMap_polygon | 1663054 | 0.60 |


### 2026-03-13 — Commit 2a11d6e

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7222472 | 0.14 |
| kalman_process_100_fixes | 97221 | 10.29 |
| kalman_process_1k_fixes | 9636 | 103.78 |
| kalman_reset | 6905122 | 0.14 |
| haversine_single | 9107759 | 0.11 |
| haversine_1k_pairs | 16937 | 59.04 |
| pip_4v | 13121625 | 0.08 |
| pip_10v | 10228605 | 0.10 |
| pip_50v | 3836001 | 0.26 |
| pip_100v | 2123670 | 0.47 |
| pip_500v | 424587 | 2.36 |
| geofence_eval_10_circular | 664743 | 1.50 |
| geofence_eval_100_circular | 75756 | 13.20 |
| geofence_eval_500_circular | 14528 | 68.83 |
| geofence_eval_10_polygon_6v | 413036 | 2.42 |
| geofence_eval_50_polygon_6v | 84315 | 11.86 |
| processor_1k_fixes | 9939 | 100.61 |
| processor_1k_adaptive | 9302 | 107.50 |
| trip_manager_5k_waypoints | 66 | 15041.76 |
| schedule_parse | 2946567 | 0.34 |
| schedule_matches | 118562 | 8.43 |
| schedule_isWithin_5_entries | 112713 | 8.87 |
| adaptive_compute | 13697106 | 0.07 |
| location_fromMap | 1826860 | 0.55 |
| location_toMap | 686290 | 1.46 |
| location_fromMap_toMap_roundtrip | 506617 | 1.97 |
| location_copyWithCoords | 12573133 | 0.08 |
| geofence_fromMap_circular | 4510859 | 0.22 |
| geofence_fromMap_polygon | 1579852 | 0.63 |


### 2026-03-13 — Commit 2cf3a74

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7455954 | 0.13 |
| kalman_process_100_fixes | 94292 | 10.61 |
| kalman_process_1k_fixes | 9484 | 105.44 |
| kalman_reset | 6717695 | 0.15 |
| haversine_single | 8873250 | 0.11 |
| haversine_1k_pairs | 16972 | 58.92 |
| pip_4v | 13406421 | 0.07 |
| pip_10v | 10131988 | 0.10 |
| pip_50v | 3891296 | 0.26 |
| pip_100v | 2022438 | 0.49 |
| pip_500v | 417443 | 2.40 |
| geofence_eval_10_circular | 636354 | 1.57 |
| geofence_eval_100_circular | 71513 | 13.98 |
| geofence_eval_500_circular | 13744 | 72.76 |
| geofence_eval_10_polygon_6v | 411609 | 2.43 |
| geofence_eval_50_polygon_6v | 83864 | 11.92 |
| processor_1k_fixes | 9724 | 102.84 |
| processor_1k_adaptive | 9430 | 106.04 |
| trip_manager_5k_waypoints | 65 | 15287.36 |
| schedule_parse | 2895918 | 0.35 |
| schedule_matches | 117348 | 8.52 |
| schedule_isWithin_5_entries | 113861 | 8.78 |
| adaptive_compute | 13583676 | 0.07 |
| location_fromMap | 1830592 | 0.55 |
| location_toMap | 693048 | 1.44 |
| location_fromMap_toMap_roundtrip | 511092 | 1.96 |
| location_copyWithCoords | 11726729 | 0.09 |
| geofence_fromMap_circular | 4437282 | 0.23 |
| geofence_fromMap_polygon | 1560269 | 0.64 |


### 2026-03-13 — Commit f17e8b4

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7421814 | 0.13 |
| kalman_process_100_fixes | 96911 | 10.32 |
| kalman_process_1k_fixes | 9728 | 102.79 |
| kalman_reset | 6846973 | 0.15 |
| haversine_single | 8993602 | 0.11 |
| haversine_1k_pairs | 16974 | 58.92 |
| pip_4v | 12673705 | 0.08 |
| pip_10v | 9795712 | 0.10 |
| pip_50v | 3783423 | 0.26 |
| pip_100v | 2052172 | 0.49 |
| pip_500v | 420536 | 2.38 |
| geofence_eval_10_circular | 693908 | 1.44 |
| geofence_eval_100_circular | 75912 | 13.17 |
| geofence_eval_500_circular | 14611 | 68.44 |
| geofence_eval_10_polygon_6v | 417774 | 2.39 |
| geofence_eval_50_polygon_6v | 85204 | 11.74 |
| processor_1k_fixes | 9771 | 102.34 |
| processor_1k_adaptive | 9520 | 105.04 |
| trip_manager_5k_waypoints | 67 | 15011.62 |
| schedule_parse | 2900296 | 0.34 |
| schedule_matches | 117643 | 8.50 |
| schedule_isWithin_5_entries | 110183 | 9.08 |
| adaptive_compute | 14047802 | 0.07 |
| location_fromMap | 1802886 | 0.55 |
| location_toMap | 696747 | 1.44 |
| location_fromMap_toMap_roundtrip | 497425 | 2.01 |
| location_copyWithCoords | 12677869 | 0.08 |
| geofence_fromMap_circular | 4463509 | 0.22 |
| geofence_fromMap_polygon | 1587077 | 0.63 |


### 2026-03-13 — Commit 48522e8

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7294386 | 0.14 |
| kalman_process_100_fixes | 95979 | 10.42 |
| kalman_process_1k_fixes | 9653 | 103.59 |
| kalman_reset | 6896903 | 0.14 |
| haversine_single | 9221804 | 0.11 |
| haversine_1k_pairs | 17133 | 58.37 |
| pip_4v | 13215194 | 0.08 |
| pip_10v | 9903533 | 0.10 |
| pip_50v | 3757121 | 0.27 |
| pip_100v | 2015194 | 0.50 |
| pip_500v | 427658 | 2.34 |
| geofence_eval_10_circular | 690095 | 1.45 |
| geofence_eval_100_circular | 75364 | 13.27 |
| geofence_eval_500_circular | 14597 | 68.51 |
| geofence_eval_10_polygon_6v | 425237 | 2.35 |
| geofence_eval_50_polygon_6v | 83935 | 11.91 |
| processor_1k_fixes | 9726 | 102.82 |
| processor_1k_adaptive | 9444 | 105.88 |
| trip_manager_5k_waypoints | 66 | 15265.10 |
| schedule_parse | 2874812 | 0.35 |
| schedule_matches | 119211 | 8.39 |
| schedule_isWithin_5_entries | 113640 | 8.80 |
| adaptive_compute | 13431232 | 0.07 |
| location_fromMap | 1774172 | 0.56 |
| location_toMap | 677678 | 1.48 |
| location_fromMap_toMap_roundtrip | 496804 | 2.01 |
| location_copyWithCoords | 12611301 | 0.08 |
| geofence_fromMap_circular | 4506482 | 0.22 |
| geofence_fromMap_polygon | 1557476 | 0.64 |


### 2026-03-12 — Commit d77027e

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7193400 | 0.14 |
| kalman_process_100_fixes | 97778 | 10.23 |
| kalman_process_1k_fixes | 9816 | 101.88 |
| kalman_reset | 6946434 | 0.14 |
| haversine_single | 8850791 | 0.11 |
| haversine_1k_pairs | 16943 | 59.02 |
| pip_4v | 13538405 | 0.07 |
| pip_10v | 10037909 | 0.10 |
| pip_50v | 3801761 | 0.26 |
| pip_100v | 2068599 | 0.48 |
| pip_500v | 411985 | 2.43 |
| geofence_eval_10_circular | 688296 | 1.45 |
| geofence_eval_100_circular | 74841 | 13.36 |
| geofence_eval_500_circular | 14396 | 69.46 |
| geofence_eval_10_polygon_6v | 421016 | 2.38 |
| geofence_eval_50_polygon_6v | 86360 | 11.58 |
| processor_1k_fixes | 9743 | 102.64 |
| processor_1k_adaptive | 9302 | 107.50 |
| trip_manager_5k_waypoints | 67 | 14911.44 |
| schedule_parse | 2931142 | 0.34 |
| schedule_matches | 119800 | 8.35 |
| schedule_isWithin_5_entries | 113255 | 8.83 |
| adaptive_compute | 13133993 | 0.08 |
| location_fromMap | 1870877 | 0.53 |
| location_toMap | 700758 | 1.43 |
| location_fromMap_toMap_roundtrip | 517687 | 1.93 |
| location_copyWithCoords | 12449837 | 0.08 |
| geofence_fromMap_circular | 4540581 | 0.22 |
| geofence_fromMap_polygon | 1606597 | 0.62 |


### 2026-03-12 — Commit ff82056

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7257375 | 0.14 |
| kalman_process_100_fixes | 96448 | 10.37 |
| kalman_process_1k_fixes | 9543 | 104.79 |
| kalman_reset | 6932943 | 0.14 |
| haversine_single | 9019606 | 0.11 |
| haversine_1k_pairs | 17994 | 55.58 |
| pip_4v | 13514335 | 0.07 |
| pip_10v | 10150725 | 0.10 |
| pip_50v | 3929605 | 0.25 |
| pip_100v | 2177386 | 0.46 |
| pip_500v | 437657 | 2.28 |
| geofence_eval_10_circular | 676948 | 1.48 |
| geofence_eval_100_circular | 76436 | 13.08 |
| geofence_eval_500_circular | 14230 | 70.27 |
| geofence_eval_10_polygon_6v | 429110 | 2.33 |
| geofence_eval_50_polygon_6v | 86094 | 11.62 |
| processor_1k_fixes | 10231 | 97.74 |
| processor_1k_adaptive | 9741 | 102.66 |
| trip_manager_5k_waypoints | 139 | 7213.38 |
| schedule_parse | 3024988 | 0.33 |
| schedule_matches | 256804 | 3.89 |
| schedule_isWithin_5_entries | 226082 | 4.42 |
| adaptive_compute | 13878905 | 0.07 |
| location_fromMap | 1665198 | 0.60 |
| location_toMap | 595019 | 1.68 |
| location_fromMap_toMap_roundtrip | 451083 | 2.22 |
| location_copyWithCoords | 11006660 | 0.09 |
| geofence_fromMap_circular | 4272423 | 0.23 |
| geofence_fromMap_polygon | 1455292 | 0.69 |


### 2026-03-12 — Commit d4dd2eb

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7454689 | 0.13 |
| kalman_process_100_fixes | 97170 | 10.29 |
| kalman_process_1k_fixes | 9722 | 102.85 |
| kalman_reset | 6808310 | 0.15 |
| haversine_single | 9098798 | 0.11 |
| haversine_1k_pairs | 17514 | 57.10 |
| pip_4v | 13398138 | 0.07 |
| pip_10v | 10107625 | 0.10 |
| pip_50v | 3866536 | 0.26 |
| pip_100v | 2129965 | 0.47 |
| pip_500v | 426085 | 2.35 |
| geofence_eval_10_circular | 684409 | 1.46 |
| geofence_eval_100_circular | 77081 | 12.97 |
| geofence_eval_500_circular | 14657 | 68.23 |
| geofence_eval_10_polygon_6v | 416659 | 2.40 |
| geofence_eval_50_polygon_6v | 86521 | 11.56 |
| processor_1k_fixes | 9872 | 101.29 |
| processor_1k_adaptive | 9277 | 107.79 |
| trip_manager_5k_waypoints | 68 | 14612.93 |
| schedule_parse | 2893921 | 0.35 |
| schedule_matches | 122087 | 8.19 |
| schedule_isWithin_5_entries | 116963 | 8.55 |
| adaptive_compute | 14371032 | 0.07 |
| location_fromMap | 1894006 | 0.53 |
| location_toMap | 730375 | 1.37 |
| location_fromMap_toMap_roundtrip | 527698 | 1.90 |
| location_copyWithCoords | 13282735 | 0.08 |
| geofence_fromMap_circular | 4673701 | 0.21 |
| geofence_fromMap_polygon | 1686843 | 0.59 |


### 2026-03-12 — Commit aba9490

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7144490 | 0.14 |
| kalman_process_100_fixes | 94935 | 10.53 |
| kalman_process_1k_fixes | 9507 | 105.18 |
| kalman_reset | 6860178 | 0.15 |
| haversine_single | 8922812 | 0.11 |
| haversine_1k_pairs | 17906 | 55.85 |
| pip_4v | 13365757 | 0.07 |
| pip_10v | 9997195 | 0.10 |
| pip_50v | 3872224 | 0.26 |
| pip_100v | 2148818 | 0.47 |
| pip_500v | 443117 | 2.26 |
| geofence_eval_10_circular | 674080 | 1.48 |
| geofence_eval_100_circular | 76272 | 13.11 |
| geofence_eval_500_circular | 14480 | 69.06 |
| geofence_eval_10_polygon_6v | 433068 | 2.31 |
| geofence_eval_50_polygon_6v | 88512 | 11.30 |
| processor_1k_fixes | 10006 | 99.94 |
| processor_1k_adaptive | 9613 | 104.03 |
| trip_manager_5k_waypoints | 139 | 7170.50 |
| schedule_parse | 3025952 | 0.33 |
| schedule_matches | 255381 | 3.92 |
| schedule_isWithin_5_entries | 229935 | 4.35 |
| adaptive_compute | 13344051 | 0.07 |
| location_fromMap | 1738526 | 0.58 |
| location_toMap | 590859 | 1.69 |
| location_fromMap_toMap_roundtrip | 455298 | 2.20 |
| location_copyWithCoords | 11108456 | 0.09 |
| geofence_fromMap_circular | 4254545 | 0.24 |
| geofence_fromMap_polygon | 1479498 | 0.68 |


### 2026-03-12 — Commit 0378fca

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 6648289 | 0.15 |
| kalman_process_100_fixes | 94121 | 10.62 |
| kalman_process_1k_fixes | 9646 | 103.67 |
| kalman_reset | 6827360 | 0.15 |
| haversine_single | 8937856 | 0.11 |
| haversine_1k_pairs | 17273 | 57.89 |
| pip_4v | 11331378 | 0.09 |
| pip_10v | 8687929 | 0.12 |
| pip_50v | 3516809 | 0.28 |
| pip_100v | 1976908 | 0.51 |
| pip_500v | 420472 | 2.38 |
| geofence_eval_10_circular | 683001 | 1.46 |
| geofence_eval_100_circular | 75211 | 13.30 |
| geofence_eval_500_circular | 14378 | 69.55 |
| geofence_eval_10_polygon_6v | 409423 | 2.44 |
| geofence_eval_50_polygon_6v | 83264 | 12.01 |
| processor_1k_fixes | 9955 | 100.45 |
| processor_1k_adaptive | 9297 | 107.56 |
| trip_manager_5k_waypoints | 66 | 15068.65 |
| schedule_parse | 2872580 | 0.35 |
| schedule_matches | 117293 | 8.53 |
| schedule_isWithin_5_entries | 110230 | 9.07 |
| adaptive_compute | 12736632 | 0.08 |
| location_fromMap | 1797230 | 0.56 |
| location_toMap | 690972 | 1.45 |
| location_fromMap_toMap_roundtrip | 510812 | 1.96 |
| location_copyWithCoords | 12689379 | 0.08 |
| geofence_fromMap_circular | 4187607 | 0.24 |
| geofence_fromMap_polygon | 1579452 | 0.63 |


