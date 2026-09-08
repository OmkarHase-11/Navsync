# IMU Data Preprocessing Pipeline

## Purpose

Issue #2 turns a selected IO-VNBD smartphone/vehicle pair into deterministic numeric records for Issue #3. Issue #1 only explores schema and quality; this pipeline validates required fields, matches timestamps, drops unusable samples, and attaches a vehicle-speed label. It uses Python 3.10+ and the standard library, reusing Issue #1's CSV loader. No model is trained.

## Inputs and loading

Supply one S-file and its corresponding V-file. `load_sensor_csv(path)` returns the resolved file path, decoder, original headers, dictionary rows, selected time header, detected signals, and loader warnings. Decoder attempts are utf-8-sig, utf-8, cp1252, latin-1. First-success decoding is not proof that every unit glyph is correct.

Nonexistent files, directories, empty/header-only CSVs, duplicate headers, malformed quoting, and ragged rows fail clearly. Unlike exploration, preprocessing rejects both short and extra-field rows rather than training on truncation. Empty physical records are skipped by the shared loader with warnings; explicit blank cells remain blank. Inputs are never modified.

## Required smartphone signals

`detect_smartphone_columns(headers)` selects time, accelerometer X/Y/Z, gyroscope X/Y/Z, optional gravity X/Y/Z, magnetic field X/Y/Z, GPS speed, latitude, and longitude. Detection is case-insensitive and tolerates whitespace/axis separators. It matches signal names before unit glyphs, including headers with mangled degree/micro symbols. Ambiguous matches fail instead of silently selecting a column. Missing required time or acceleration/gyroscope axes fail.

These features remain in the dataset phone frame. Gravity is retained; there is no filtering, gravity subtraction, integration, orientation estimation, or magnitude-feature generation. Source headers are retained in metadata to expose header-reported m/s², rad/s, gravity units, and magnetic units. Physical unit/frame correctness still requires dataset verification; uncertain optional units are never converted.

## Reference vehicle-speed selection

`detect_vehicle_columns(headers)` identifies time, reference velocity, indicated vehicle speed, position, yaw rate, longitudinal acceleration, and lateral acceleration. Wheel angular speeds, engine RPM, and vertical velocity are excluded from label candidates.

Selection prefers `Velocity (km/hr)` (also GPS Velocity) over `Indicated Vehicle Speed (km/hr)`, provided the unit is explicitly recognized. Recognized linear units are km/h equivalents (km/hr, kmh, kph) and m/s equivalents. If the preferred candidate's unit is unknown, a recognized indicated-speed candidate may be used. If no recognized candidate exists, preprocessing fails. The exact selected header, source unit, and output unit are recorded. Selection is fixed for the pair: a missing label drops that sample, with no per-row fallback to another signal. Negative labels are rejected because the target is nonnegative speed.

Header/type validation does not establish ground-truth quality. Vehicle velocity is a candidate reference subject to external validation. Wheel angular speed is not a linear speed label, and smartphone GPS speed is not trusted as the main training label.

## Timestamp normalization

`parse_timestamps(rows, column_name)` returns relative seconds, original origin, scale, header, and sampling diagnostics. Explicit ms/milliseconds or seconds/sec/(s)/[s] headers are required. For example, 914616 ms and 914716 ms become 0 and 0.1 seconds. Units are not guessed from magnitude.

All rows must have finite numeric timestamps. Missing/nonnumeric/nonfinite times fail with offending row indices. Repeated/decreasing times fail with diagnostics; no sorting, clock reset repair, midnight rollover correction, or timestamp interpolation occurs. Thus the first valid timestamp is the first row in an accepted stream.

`validate_sampling(timestamps)` reports count, first-to-last duration, median positive interval, estimated Hz, min/max interval, nonpositive count, and gap count. Gaps greater than five times the median positive interval are heuristic flags. Frequency is unavailable for nonpositive sequences. One-sample streams have duration zero and no cadence estimate. Irregularity and gaps are retained in metadata, not represented as perfect sampling.

## Synchronization strategy

`synchronize_streams(smartphone_timestamps, vehicle_timestamps, tolerance_s=0.055)` consumes already normalized seconds. It processes smartphone samples chronologically, choosing the nearest unused vehicle sample at or after the previous match, breaking ties toward the earlier vehicle sample. Every match must satisfy the inclusive tolerance. A vehicle sample is used at most once; skipped/unmatched samples are counted. The result contains index pairs plus sample counts, mean/max absolute offsets, and tolerance.

This is a deterministic greedy nearest-neighbor MVP, not a globally optimal assignment. It may sacrifice possible later matches and is asymmetric between streams. Equal row counts are never used to establish matches. The 0.055 s default is configurable and is not a validated timing threshold.

**Relative timestamps do not prove external absolute synchronization.** Subtracting each first timestamp assumes the streams begin at the same physical instant. Run identity and that assumption must be verified externally, even for files in the synchronized collection. Initial offsets cannot be recovered by this pipeline. No resampling or interpolation is implemented, including across large gaps. `time_s` retains gaps rather than pretending output rows are regularly spaced.

## Missing-value policy

For each matched pair:

- Blank required acceleration or gyroscope values drop the pair.
- Blank reference labels drop the pair.
- Nonnumeric or nonfinite required values drop the pair.
- Negative reference speed drops the pair.
- Blank optional fields become None (empty CSV cells); malformed/nonfinite optional fields also become None and are counted.

No sensor value is replaced with zero or invented. `quality` reports dropped_missing_accel, dropped_missing_gyro, dropped_missing_label, dropped_invalid_numeric, dropped_negative_label, dropped_rows, optional_invalid_values, and final_record_count. Reason counts count affected pairs once per reason and can overlap; dropped_rows counts each pair once. Synchronization counts describe matching before feature-quality drops. Matching is not retried after a pair is dropped. Zero clean records is an explicit valid diagnostic outcome, not proof of training readiness.

## Unit policy

Default `speed_unit="original"` preserves recognized vehicle-speed units. Explicit `speed_unit="mps"` divides km/h labels by 3.6; m/s labels remain unchanged. Unknown source units are never converted. Smartphone GPS speed remains raw under either option; the Vta25 scale discrepancy is unresolved and is not corrected by multiplying by 3.6.

Optional gravity, magnetometer, GPS, yaw rate, and vehicle accelerations remain raw with source headers in metadata. Optional numeric values are not otherwise physically range-validated. No unit conversion, gravity subtraction, or phone-to-vehicle transform is implicit.

## Output schema and API

`preprocess_pair(smartphone_path, vehicle_path, tolerance_s=0.055, speed_unit="original")` returns:

- `metadata`: source paths/encodings, selected column maps, label units, timestamp origins/normalized arrays/sampling diagnostics, and assumptions.
- `synchronization`: matching diagnostics.
- `quality`: drop and optional-value diagnostics.
- `feature_names`: stable ordered column names, excluding time and label.
- `label_name`: reference_speed.
- `records`: clean aligned rows.

Every row has time_s, accel_x/y/z, gyro_x/y/z, and reference_speed. Detected optional columns add gravity_x/y/z, magnetometer_x/y/z, gps_latitude, gps_longitude, smartphone_gps_speed, vehicle_yaw_rate, vehicle_longitudinal_acceleration, and vehicle_lateral_acceleration. Missing optional columns are omitted from the schema; present columns with missing cells produce None. Partial optional axis groups are permitted.

`export_preprocessed_csv(result, output_path)` writes UTF-8 with stable order: time, feature_names, label. It creates parents and uses exclusive creation: existing files, directories, and existing links are not overwritten. Resolved raw input paths are explicitly rejected. Only numeric records are exported; retain the returned metadata alongside the CSV in the downstream workflow because CSV alone does not preserve units/origins. No full raw file is copied.

Other public APIs are `load_sensor_csv`, both detection functions, `parse_timestamps`, `validate_sampling`, `synchronize_streams`, and CLI entry point `main(argv=None)`.

## CLI

PowerShell example, substituting your external dataset/output paths:

```powershell
python -B preprocessing/imu_preprocessing.py `
  --smartphone "C:\data\S-Vta25.csv" `
  --vehicle "C:\data\V-vta25.csv" `
  --tolerance 0.055 `
  --speed-unit original `
  --output "C:\data\processed\vta25.csv"
```

Omit --output for a read-only smoke run. Use --speed-unit mps only for explicit reference-label conversion. The CLI prints concise JSON containing sampling, synchronization, quality, selected label/unit, and the relative-start assumption. Invalid paths/data/options or existing export targets fail with useful errors and exit code 2.

## Issue #3 and limitations

The result supplies numeric raw axes and a candidate reference label to Issue #3. Before training, verify external synchronization and label quality, choose input features, handle any remaining optional None values, split by run/driver to avoid leakage, and retain unit metadata. Optional smartphone GPS and vehicle-derived fields are provided for inspection, not automatically suitable model inputs: using them can leak targets or undermine operation during GNSS outages. An IMU-only model should explicitly select accel/gyro axes and other justified phone sensors.

No learned filtering or AI model is implemented. Issue #3 owns speed model training. Issue #5 handles phone-to-vehicle alignment; this pipeline neither estimates nor applies it. Navigation modules are unchanged. No production synchronization guarantees are made. Processing is in memory and intended for one pair at a time. All source units, initial time association, optional feature selection, and tolerance should be reviewed before training.

## Raw dataset storage and real smoke test

Raw IO-VNBD remains outside Navsync. Commit code, documentation, and synthetic tests only; keep raw and exported real records external. The prescribed local synchronized Vta25 pair was processed without export:

| Observation | Result |
| --- | --- |
| Smartphone / vehicle rows | 646 / 646 |
| Duration | 64.498 s / 64.500 s |
| Median cadence | Approximately 10 Hz for both |
| Matched / unmatched S / unmatched V | 646 / 0 / 0 |
| Mean absolute relative offset | Approximately 0.0017012384 s |
| Max absolute relative offset | Approximately 0.0020000000 s |
| Selected label | Velocity (km/hr), retained as km/h |
| Dropped / final records | 0 / 646 |
| Raw source SHA-256 hashes | Unchanged before/after |

These are observed preprocessing counts and relative timing diagnostics, not proof of physical synchronization or model performance. Smartphone GPS speed units remain unresolved.

## Tests

Tests use temporary synthetic CSVs; no local real dataset dependency. Run from the repository root:

```text
python -B -m unittest discover -s preprocessing/tests -v
python -B -m unittest discover -s dataset/tests -v
python -B -m unittest discover -s navigation_engine/dead_reckoning/tests -v
python -B -m unittest discover -s navigation_engine/alignment/tests -v
python -B -m unittest discover -s navigation_engine/gnss/tests -v
python -B -m unittest discover -s navigation_engine/mode_switching/tests -v
```
