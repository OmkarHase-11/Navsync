# GNSS Availability Detection

## Purpose

Issue #9 determines whether the latest GNSS fix is usable for navigation. This is a stateless, deterministic Python 3.10+ module using only the standard library. It does not perform navigation, fusion, Dead Reckoning, or mode switching.

## Input

Call `detect_gnss_availability` with:

| Argument | Meaning |
| --- | --- |
| latitude | WGS84 decimal degrees, -90 through +90 inclusive; maps to SensorData.latitude. |
| longitude | WGS84 decimal degrees, -180 through +180 inclusive; maps to SensorData.longitude. |
| accuracy | Nonnegative horizontal GNSS accuracy in meters; maps to SensorData.gnss_accuracy. |
| fix_timestamp_ms | Original GNSS measurement time, integer Unix milliseconds. |
| current_timestamp_ms | Caller-supplied evaluation time, integer Unix milliseconds. |
| max_fix_age_ms | Configurable maximum acceptable age in milliseconds. |
| max_accuracy_m | Configurable maximum acceptable accuracy value in meters. |

Pass `None` for all four fix fields (latitude, longitude, accuracy, fix_timestamp_ms) when no fix exists. A partially supplied fix is checked for missing/invalid fields in the order below. Only `None` means missing; zero coordinates are valid.

The detector never reads the system clock or remembers a previous fix. Callers select the latest fix and reevaluate it as time advances, including when no new GNSS callbacks arrive.

## Output

The immutable `GNSSStatusResult` dataclass has three fields:

| Field | Values |
| --- | --- |
| status | `AVAILABLE` or `UNAVAILABLE` |
| reason | `OK` or one failure reason below |
| fix_age_ms | Nonnegative integer for OK, STALE_FIX, or POOR_ACCURACY; otherwise `None` (JSON null). |

Age is computed only after measurement and timestamp validation succeeds. Early failures return null age even if the supplied timestamps happen to be valid. `dataclasses.asdict(result)` produces a JSON-compatible dictionary. This local diagnostic result does not add fields to or alter Issue #8 interfaces.

## Detection Rules

A fix is AVAILABLE only if it exists, all measurements are present and valid, both timestamps are valid, the fix is not in the future, age is at most max_fix_age_ms, and accuracy is at most max_accuracy_m. Otherwise it is UNAVAILABLE with the first applicable reason.

Coordinates and accuracy accept Python int/float values only; strings, booleans, NaN, infinity, and other types are invalid. Coordinates must be in the inclusive ranges above; accuracy must be nonnegative. Both timestamps must be nonnegative Python integers (booleans and integral floats are rejected). Epoch zero is valid; pre-1970 timestamps are outside this MVP's supported time domain.

`fix_age_ms = current_timestamp_ms - fix_timestamp_ms`. Equal timestamps yield age zero. Future fixes are invalid. A fix exactly at either threshold is accepted; strictly greater age is stale and strictly greater accuracy is poor.

## Default Thresholds

- `MAX_GNSS_AGE_MS = 3000`, exposed as `max_fix_age_ms`.
- `MAX_GNSS_ACCURACY_M = 30.0`, exposed as `max_accuracy_m`.

These are **configurable MVP defaults requiring tuning during field testing**, not scientifically validated thresholds or project performance claims. max_fix_age_ms must be a nonnegative integer; max_accuracy_m must be a finite nonnegative int/float. Boolean thresholds are invalid. Zero thresholds are allowed. Invalid configuration raises `ValueError` before evaluating the fix because this is a caller configuration error, not a GNSS failure.

## Failure Reasons

The following table is the exact precedence order; the first matching condition wins.

| Order | Reason | Condition |
| --- | --- | --- |
| 1 | NO_FIX | All four fix fields are None. |
| 2 | MISSING_LATITUDE | latitude is None. |
| 3 | MISSING_LONGITUDE | longitude is None. |
| 4 | MISSING_ACCURACY | accuracy is None. |
| 5 | INVALID_LATITUDE | Wrong numeric type, nonfinite value, or out of range. |
| 6 | INVALID_LONGITUDE | Wrong numeric type, nonfinite value, or out of range. |
| 7 | INVALID_ACCURACY | Wrong numeric type, nonfinite value, or negative value. |
| 8 | INVALID_TIMESTAMP | Either timestamp is missing, incorrectly typed, negative, or fix time exceeds current time. |
| 9 | STALE_FIX | Age exceeds max_fix_age_ms. |
| 10 | POOR_ACCURACY | Accuracy exceeds max_accuracy_m. |
| 11 | OK | All checks pass; status is AVAILABLE. |

## Examples

Run from the repository root. These values are the request's illustrative test inputs, not actual measurements or accuracy results.

```python
from navigation_engine.gnss.gnss_availability import detect_gnss_availability

valid = detect_gnss_availability(
    18.5204, 73.8567, 8.0, 1725552000000, 1725552001000
)
# GNSSStatusResult(status='AVAILABLE', reason='OK', fix_age_ms=1000)

stale = detect_gnss_availability(
    18.5204, 73.8567, 8.0, 1725552000000, 1725552005000
)
# GNSSStatusResult(status='UNAVAILABLE', reason='STALE_FIX', fix_age_ms=5000)

poor = detect_gnss_availability(
    18.5204, 73.8567, 75.0, 1725552000000, 1725552001000
)
# GNSSStatusResult(status='UNAVAILABLE', reason='POOR_ACCURACY', fix_age_ms=1000)
```

## Integration

The [Issue #8 contract](../../integration/interfaces/README.md) remains unchanged. Run detection on raw GNSS fields before constructing the public SensorData snapshot:

- `AVAILABLE` maps to `gnss_available = true`; retain latitude, longitude, and gnss_accuracy.
- `UNAVAILABLE` maps to `gnss_available = false`; publish latitude, longitude, and gnss_accuracy as null.

Keep raw fix metadata separately if needed for reevaluation and diagnostics. A public unavailable SensorData record has already discarded its GNSS values, so it cannot reconstruct the original failure reason. Do not treat its flag as an independent detector input.

SensorData.timestamp is an aligned snapshot epoch. It is safe to use it as fix_timestamp_ms only when it actually equals the GNSS measurement epoch. For a reused GNSS fix, supply its original timestamp separately; never refresh an old fix's timestamp to the latest IMU/snapshot time. For this reason no generic SensorData dictionary helper is provided. Current time and fix time must share the same Unix time basis.

Issue #10 will consume this status to decide whether navigation should remain in GNSS_INS or switch to DEAD_RECKONING, and when to return. No mode transitions are implemented here. The team should review field-tested thresholds, clock alignment, callback/reevaluation cadence, and any later recovery/hysteresis policy in Issue #10.

## Tests

From the repository root:

```text
python -B -m unittest discover -s navigation_engine/gnss/tests -v
```

Tests cover valid and missing fixes, measurement validation, coordinate and threshold boundaries, timestamp errors, configurable thresholds, deterministic failure precedence, result serialization, and compatibility with the existing SensorData sample. All inputs are test fixtures, not collected sensor data.
