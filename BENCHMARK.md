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
