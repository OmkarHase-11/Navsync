# IO-VNBD Dataset Exploration

## Purpose

Issue #1 explores IO-VNBD's raw structure and data quality for Navsync. The standard-library Python 3.10+ tool reads an S/V pair independently and prints an indented JSON report with human-readable warnings. It does not train models, synchronize recordings, or implement preprocessing. All reported statistics are descriptive observations, not navigation performance metrics.

## Organization and evidence

IO-VNBD stores smartphone-side `S-*` and vehicle-side `V-*` recordings. Matching run names, such as `S-Vta25.csv` and `V-vta25.csv`, identify a candidate paired run. Case and folder organization can vary. The inspected local checkout contains both `Synchronised V abd S datasets` and `Unsynchronised V and S Dataset` collections; do not treat every pair as already synchronized.

Evidence for the observations below is the local checkout's `README.md` and these two files under `Synchronised V abd S datasets/Uncategorised IOVNB Dataset/`:

- `S-Dataset/S-Vta25.csv`
- `V-Dataset/V-vta25.csv`

The local source README describes smartphone sampling at 10 Hz. The measurements below independently describe only the inspected pair, not every run. No dataset-wide guarantees are inferred.

## Observed Vta25 exploration

The script was run against the above local pair without rewriting either file:

| Property | Smartphone S-Vta25 | Vehicle V-vta25 |
| --- | --- | --- |
| Data rows | 646 | 646 |
| Columns | 24 | 29 |
| First successful decoder | cp1252 | utf-8-sig |
| Selected time header | TIME SINCE START (ms) | Time Since Start of Day (seconds) |
| Duration from header units | 64.498 seconds | 64.500 seconds |
| Median positive-interval frequency | Approximately 10 Hz | Approximately 10 Hz |

The duration difference is about 0.002 seconds. **Equal row counts do not guarantee sample-by-sample timestamp alignment.** The time columns have different origins, so matching cadence and duration do not establish a common epoch. Issue #2 must verify alignment, offsets, resets, dropped samples, and timebase interpretation.

Observed raw speed ranges:

| Header (outer whitespace omitted here) | Minimum | Maximum |
| --- | --- | --- |
| Smartphone GPS SPEED (Kmh) | 0 | 11.54 |
| Vehicle Velocity (km/hr) | 0 | 48.586 |
| Indicated Vehicle Speed (km/hr) | 0 | 48.96 |

These numerical ranges differ substantially. The smartphone header reports Kmh, but its physical unit is **unresolved** pending authoritative documentation/reference verification. Do not assume m/s or automatically multiply by 3.6. Differences could involve units, signal definitions, or alignment; ranges alone cannot decide. The script performs no speed conversion. Other headers also require verification: for example the vehicle file labels Height in km, while observed initial values are around 216.8; this is a review flag, not a corrected unit claim. First-success encoding is a decoding result, not proof of original encoding or correctly rendered unit glyphs.

## Smartphone signals relevant to Navsync

The inspected smartphone header includes GPS latitude/longitude, altitude, speed, accuracy, orientation, satellite count, elapsed time, and a date string; accelerometer X/Y/Z; gravity X/Y/Z; gyroscope X/Y/Z; magnetic field X/Y/Z; and orientation azimuth/pitch/roll.

Header labels report accelerometer/gravity in m/s² and gyroscope in rad/s. Magnetic and angle unit glyphs may have encoding artifacts and need verification. These are raw dataset conventions: Issue #2 must establish units, sensor frames, gravity semantics, and mappings to the existing Navsync interface rather than assuming compatibility.

## Vehicle/reference signals relevant to Navsync

The inspected vehicle header includes GPS-associated latitude/longitude, velocity, heading, height and satellite information; indicated vehicle speed; four wheel speeds; yaw rate; longitudinal/lateral acceleration; steering angle; and engine, gear, brake, clutch and other vehicle-state signals.

Wheel-speed headers report rad/sec, engine speed reports rev/min, acceleration reports g, and yaw rate reports deg/sec. Wheel angular speed is not directly a linear-speed label without additional information. Engine speed is not vehicle speed. The report lists all speed-related columns but excludes wheel, engine, vertical velocity, and explicitly angular-rate names from its cross-file linear-speed candidate comparisons. Candidate detection does not certify a ground-truth label.

## Planned use

```text
Smartphone IMU -> preprocessing (#2) -> AI speed estimation (#3)
                                      -> dead reckoning integration (#14)
Vehicle/reference speed -> verified training/evaluation reference where appropriate
```

Issue #1 identifies candidate signals. The suitability section uses detected column names only and does not certify data completeness, calibration, accuracy, or readiness for training.

## Run the tool

Keep raw IO-VNBD outside Navsync. Supply both paths explicitly; no machine-specific path is embedded in Python code. Example PowerShell command (replace paths with the desired pair):

```powershell
py -B dataset/explore_io_vnbd.py `
  --smartphone "C:\Users\omkar\IO-VNBD\Synchronised V abd S datasets\Uncategorised IOVNB Dataset\S-Dataset\S-Vta25.csv" `
  --vehicle "C:\Users\omkar\IO-VNBD\Synchronised V abd S datasets\Uncategorised IOVNB Dataset\V-Dataset\V-vta25.csv"
```

`python` can replace `py` where appropriate. Output is JSON on stdout, suitable for reading or saving outside the raw dataset. Bad paths/CSV structure produce a CLI error and exit code 2. No dataset file is modified.

Public functions:

- `load_csv(path)`: returns original headers, stripped cell rows, decoder name, and structural warnings.
- `detect_columns(columns)`: case-insensitive keyword groups, allowing overlap.
- `explore_file(path)`: independent schema/statistics/missingness/sampling report.
- `explore_pair(smartphone_path, vehicle_path)`: dictionary with smartphone, vehicle, comparison, and suitability sections.
- `main(argv=None)`: CLI entry point using explore_pair.

## Reporting rules and uncertainties

- Comma-delimited CSV with a header is expected; quoted cells are supported. Files are decoded strictly in order utf-8-sig, utf-8, cp1252, latin-1. The first successful decoder is reported; utf-8-sig also handles ordinary UTF-8. Latin-1's broad acceptance does not establish semantic correctness.
- Missing paths/directories, missing/empty header names, duplicate names after trimming/case-folding, and malformed quoting fail clearly. Original header text is retained in the report. Empty physical records are skipped; explicit blank-cell records count as data. Short rows are padded with missing cells and extra fields are excluded from header-based statistics, with warnings and counts.
- A blank is an empty/whitespace cell, not a string such as NA or NaN. Missing counts/percentages cover every column. Header-only files have zero rows, zero blank percentages, and no numeric statistics.
- Only finite float-parsable values contribute to min/max/mean. A column is numeric-looking when at least half its nonblank cells are valid finite numbers and at least one number exists. Text-dominated columns are omitted from general numeric statistics. Speed candidates always receive a statistics entry, with null aggregates when no valid numeric values exist. Malformed/nonfinite nonblank cells are counted separately.
- Time candidates use keywords. Among numeric candidates with at least two values, elapsed/since/timestamp names are preferred, then explicit units; ties retain header order. Sample-period/interval fields are excluded as time coordinates. All eligible candidates are shown so selection can be reviewed. Date strings are not parsed.
- Explicit ms/milliseconds or s/sec/seconds in the selected header supplies the provisional time scale. Magnitudes alone do not resolve units: unknown units leave raw intervals/duration visible but seconds/Hz unavailable. No epoch inference is performed.
- Differences use adjacent valid rows only; no interpolation or bridging across missing times. Duration spans first/last valid samples. Median positive interval estimates cadence; minimum/maximum intervals and non-positive counts expose irregularity. Duplicate/backward times or interval overflow suppress duration in seconds and frequency. There is no reset or midnight-rollover repair.
- Gaps greater than five times median positive interval are flagged. Approximate frequency is reciprocal median cadence, not proof of uninterrupted sampling. Missing timestamp counts must be reviewed alongside cadence.
- Cross-file duration difference is absolute and only available when both time scales and sequences permit it. No row-index join, timestamp alignment, or synchronization claim is made.
- A peak absolute speed magnitude ratio of at least 2, or zero versus nonzero, triggers a discrepancy warning. This is an exploration heuristic, not a validated threshold or evidence that a unit is wrong. No warning does not prove agreement. Raw ranges are shown side by side without conversion.
- The tool loads each supplied CSV into memory. It is intended for individual recording pairs, not loading the full collection at once. It does not automatically discover matching files or verify their run identity.

## Storage and issue boundaries

Commit scripts, documentation, and synthetic tests only. Do not commit full raw archives or large CSV collections to Navsync. This task adds no raw dataset files or third-party dependencies and changes no navigation modules.

| Issue | Responsibility |
| --- | --- |
| #1 | Explore structure, document schema, inspect quality, identify candidate signals |
| #2 | Verify units/alignment; implement preprocessing, filtering, resampling, synchronization, feature preparation |
| #3 | Implement AI speed estimation |

## Tests

All automated tests use small deterministic CSVs in temporary directories, not the real dataset:

```text
py -B -m unittest discover -s dataset/tests -v
py -B -m unittest discover -s navigation_engine/dead_reckoning/tests -v
py -B -m unittest discover -s navigation_engine/alignment/tests -v
py -B -m unittest discover -s navigation_engine/gnss/tests -v
py -B -m unittest discover -s navigation_engine/mode_switching/tests -v
```

Tests cover schema/groups, numeric and missing values, malformed numeric input, timing and uncertainty, gaps/resets, pair comparisons, speed warnings, encodings, malformed headers, ragged rows, CLI behavior, and read-only operation. Local Vta25 observations above are a separate manual exploration, not a dependency of the tests.
