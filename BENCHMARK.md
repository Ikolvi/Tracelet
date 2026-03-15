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


### 2026-03-06 — Commit 3e5475e

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7156222 | 0.14 |
| kalman_process_100_fixes | 92063 | 10.86 |
| kalman_process_1k_fixes | 9467 | 105.64 |
| kalman_reset | 7078289 | 0.14 |
| haversine_single | 9204863 | 0.11 |
| haversine_1k_pairs | 17982 | 55.61 |
| pip_4v | 13672099 | 0.07 |
| pip_10v | 10147926 | 0.10 |
| pip_50v | 4047215 | 0.25 |
| pip_100v | 2197106 | 0.46 |
| pip_500v | 445005 | 2.25 |
| geofence_eval_10_circular | 687620 | 1.45 |
| geofence_eval_100_circular | 76802 | 13.02 |
| geofence_eval_500_circular | 14660 | 68.21 |
| geofence_eval_10_polygon_6v | 430844 | 2.32 |
| geofence_eval_50_polygon_6v | 83694 | 11.95 |
| processor_1k_fixes | 10447 | 95.72 |
| processor_1k_adaptive | 9995 | 100.05 |
| trip_manager_5k_waypoints | 140 | 7159.81 |
| schedule_parse | 3081321 | 0.32 |
| schedule_matches | 255197 | 3.92 |
| schedule_isWithin_5_entries | 225628 | 4.43 |
| adaptive_compute | 14143432 | 0.07 |
| location_fromMap | 1691847 | 0.59 |
| location_toMap | 601360 | 1.66 |
| location_fromMap_toMap_roundtrip | 461695 | 2.17 |
| location_copyWithCoords | 11229878 | 0.09 |
| geofence_fromMap_circular | 4331668 | 0.23 |
| geofence_fromMap_polygon | 1489153 | 0.67 |


### 2026-03-06 — Commit 1c7f2b4

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 6712134 | 0.15 |
| kalman_process_100_fixes | 96026 | 10.41 |
| kalman_process_1k_fixes | 9565 | 104.55 |
| kalman_reset | 6837575 | 0.15 |
| haversine_single | 9019371 | 0.11 |
| haversine_1k_pairs | 17203 | 58.13 |
| pip_4v | 11663183 | 0.09 |
| pip_10v | 9033861 | 0.11 |
| pip_50v | 3654852 | 0.27 |
| pip_100v | 1995377 | 0.50 |
| pip_500v | 422987 | 2.36 |
| geofence_eval_10_circular | 682863 | 1.46 |
| geofence_eval_100_circular | 75166 | 13.30 |
| geofence_eval_500_circular | 14425 | 69.33 |
| geofence_eval_10_polygon_6v | 410322 | 2.44 |
| geofence_eval_50_polygon_6v | 83244 | 12.01 |
| processor_1k_fixes | 9936 | 100.65 |
| processor_1k_adaptive | 9461 | 105.69 |
| trip_manager_5k_waypoints | 66 | 15265.58 |
| schedule_parse | 2885946 | 0.35 |
| schedule_matches | 118711 | 8.42 |
| schedule_isWithin_5_entries | 112780 | 8.87 |
| adaptive_compute | 13516757 | 0.07 |
| location_fromMap | 1736191 | 0.58 |
| location_toMap | 683369 | 1.46 |
| location_fromMap_toMap_roundtrip | 502018 | 1.99 |
| location_copyWithCoords | 12425751 | 0.08 |
| geofence_fromMap_circular | 3978113 | 0.25 |
| geofence_fromMap_polygon | 1462480 | 0.68 |


### 2026-03-06 — Commit 8f8301c

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7493027 | 0.13 |
| kalman_process_100_fixes | 96581 | 10.35 |
| kalman_process_1k_fixes | 9664 | 103.47 |
| kalman_reset | 6915534 | 0.14 |
| haversine_single | 9029698 | 0.11 |
| haversine_1k_pairs | 16825 | 59.44 |
| pip_4v | 13575583 | 0.07 |
| pip_10v | 10369429 | 0.10 |
| pip_50v | 3934026 | 0.25 |
| pip_100v | 2158041 | 0.46 |
| pip_500v | 421166 | 2.37 |
| geofence_eval_10_circular | 671553 | 1.49 |
| geofence_eval_100_circular | 74254 | 13.47 |
| geofence_eval_500_circular | 14368 | 69.60 |
| geofence_eval_10_polygon_6v | 416882 | 2.40 |
| geofence_eval_50_polygon_6v | 84940 | 11.77 |
| processor_1k_fixes | 9803 | 102.01 |
| processor_1k_adaptive | 9370 | 106.72 |
| trip_manager_5k_waypoints | 66 | 15153.16 |
| schedule_parse | 2935527 | 0.34 |
| schedule_matches | 117593 | 8.50 |
| schedule_isWithin_5_entries | 112466 | 8.89 |
| adaptive_compute | 13208413 | 0.08 |
| location_fromMap | 1813117 | 0.55 |
| location_toMap | 683913 | 1.46 |
| location_fromMap_toMap_roundtrip | 502511 | 1.99 |
| location_copyWithCoords | 12532098 | 0.08 |
| geofence_fromMap_circular | 4470617 | 0.22 |
| geofence_fromMap_polygon | 1597065 | 0.63 |


### 2026-03-04 — Commit 98d7a3e

**Environment:** Dart 3.11.1, ubuntu-latest (CI)

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 7143357 | 0.14 |
| kalman_process_100_fixes | 96553 | 10.36 |
| kalman_process_1k_fixes | 9301 | 107.51 |
| kalman_reset | 6770420 | 0.15 |
| haversine_single | 9173021 | 0.11 |
| haversine_1k_pairs | 17131 | 58.37 |
| pip_4v | 13577367 | 0.07 |
| pip_10v | 9695474 | 0.10 |
| pip_50v | 3799817 | 0.26 |
| pip_100v | 2029026 | 0.49 |
| pip_500v | 418050 | 2.39 |
| geofence_eval_10_circular | 678746 | 1.47 |
| geofence_eval_100_circular | 74390 | 13.44 |
| geofence_eval_500_circular | 14396 | 69.46 |
| geofence_eval_10_polygon_6v | 407217 | 2.46 |
| geofence_eval_50_polygon_6v | 81391 | 12.29 |
| processor_1k_fixes | 9915 | 100.85 |
| processor_1k_adaptive | 9401 | 106.37 |
| trip_manager_5k_waypoints | 66 | 15267.01 |
| schedule_parse | 2853421 | 0.35 |
| schedule_matches | 118324 | 8.45 |
| schedule_isWithin_5_entries | 110866 | 9.02 |
| adaptive_compute | 13546295 | 0.07 |
| location_fromMap | 1737975 | 0.58 |
| location_toMap | 667656 | 1.50 |
| location_fromMap_toMap_roundtrip | 491551 | 2.03 |
| location_copyWithCoords | 12662292 | 0.08 |
| geofence_fromMap_circular | 4145052 | 0.24 |
| geofence_fromMap_polygon | 1553494 | 0.64 |


### 2025-06-02 — Baseline (v0.12.0, post-performance-audit)

**Environment:** Dart 3.11.0, macOS arm64

| Benchmark | ops/sec | µs/op |
|---|---:|---:|
| kalman_process_single | 9,101,629 | 0.11 |
| kalman_process_100_fixes | 129,597 | 7.72 |
| kalman_process_1k_fixes | 13,503 | 74.06 |
| kalman_reset | 8,247,498 | 0.12 |
| haversine_single | 11,307,247 | 0.09 |
| haversine_1k_pairs | 31,066 | 32.19 |
| pip_4v | 17,288,752 | 0.06 |
| pip_10v | 13,799,457 | 0.07 |
| pip_50v | 5,670,817 | 0.18 |
| pip_100v | 2,926,690 | 0.34 |
| pip_500v | 720,601 | 1.39 |
| geofence_eval_10_circular | 840,408 | 1.19 |
| geofence_eval_100_circular | 94,396 | 10.59 |
| geofence_eval_500_circular | 18,161 | 55.06 |
| geofence_eval_10_polygon_6v | 529,724 | 1.89 |
| geofence_eval_50_polygon_6v | 105,278 | 9.50 |
| processor_1k_fixes | 11,991 | 83.39 |
| processor_1k_adaptive | 12,019 | 83.20 |
| trip_manager_5k_waypoints | 594 | 1,684.81 |
| schedule_parse | 3,908,346 | 0.26 |
| schedule_matches | 1,174,266 | 0.85 |
| schedule_isWithin_5_entries | 882,997 | 1.13 |
| adaptive_compute | 18,353,277 | 0.05 |
| location_fromMap | 1,905,601 | 0.52 |
| location_toMap | 655,167 | 1.53 |
| location_fromMap_toMap_roundtrip | 519,043 | 1.93 |
| location_copyWithCoords | 17,705,080 | 0.06 |
| geofence_fromMap_circular | 5,458,465 | 0.18 |
| geofence_fromMap_polygon | 1,734,853 | 0.58 |

**Key insights:**
- Kalman filter: **0.11 µs/fix** — 9.1M ops/sec, well within 1 µs budget
- Haversine: **0.09 µs** — 11.3M ops/sec
- Point-in-polygon scales linearly: 0.06 µs (4v) → 1.39 µs (500v)
- `copyWithCoords` is **32× faster** than full `fromMap→toMap` roundtrip (0.06 vs 1.93 µs)
- Full processor pipeline: **83 µs for 1000 fixes** = 0.083 µs per fix
- Adaptive mode adds **zero overhead** (83.20 vs 83.39 µs — within noise)
- All critical per-fix operations complete in **< 1 µs** individually
