# AI speed to dead reckoning integration

## Purpose and evidence

Issue #14 connects an experimental speed signal to position propagation. Issue #3 owns IMU feature construction and prediction; Issue #6 owns all spherical-Earth DR math. The core accepts generic speed estimates and does not depend on Random Forest internals or import ML libraries. The optional inference helper imports Issue #3 lazily.

Issue #4 showed weak held-out speed generalization: MAE 6.89202 m/s, RMSE 8.36091 m/s, R-squared 0.23694, and stationary false-motion rate 87.63%. This module does not improve the AI model or claim its speed is accurate. It only integrates a speed signal into DR. Validation and caller overrides do not establish navigation accuracy. Position drift has NOT been validated by this issue; no SIH drift-target claim is made.

```text
Prepared IMU records -> Issue #3 predict_from_records -> time_s/estimated_speed
  -> integration validation and explicit caller policy
  -> Issue #6 propagate_position -> local navigation result
  -> explicit Unix clock adapter -> Issue #8 NavigationOutput
```

## State and public APIs

`AISpeedDeadReckoningIntegrator(max_speed_mps=None)` starts uninitialized.

- `initialize(latitude, longitude, heading_deg, timestamp)` requires a known valid position at that timestamp. Returns a frozen `IntegrationState` containing latitude, longitude, heading_deg, and timestamp. Reinitialization replaces the state only on success.
- `update(timestamp, estimated_speed_mps, heading_deg=None, stationary_override=False)` advances from the last accepted timestamp and returns a fresh dictionary.
- `state` exposes the last immutable state; `initialized` reports whether one exists.
- `reset()` clears the state; update then fails until initialized again.
- `integrate_speed_predictions(initial_latitude, initial_longitude, initial_heading_deg, predictions, *, initial_timestamp, max_speed_mps=None)` integrates already-produced Issue #3 rows.
- `predict_and_integrate(model_bundle, records, initial_latitude, initial_longitude, initial_heading_deg, *, initial_timestamp, run_id=None, max_speed_mps=None)` calls the existing Issue #3 `predict_from_records` once and returns `predictions` plus `trajectory`. It neither loads nor trains a model; callers can supply an existing bundle obtained through Issue #3 `load_model`.
- `to_navigation_output(result, *, unix_origin_ms)` converts a result produced here to the Issue #8 wire fields.

No model, last speed, trajectory, or motion classifier is held in the state object. Returned result dictionaries are detached from state. The object is intended for sequential use, not concurrent updates.

## Time, heading, and interval semantics

The canonical local timestamp unit is **seconds on one caller-defined clock**. Initialization and every update must use that same origin. Numeric magnitudes cannot reveal units or prove a shared clock. Unix milliseconds must never be passed directly as seconds. Elapsed time is current minus previous accepted timestamp; repeated, decreasing, nonfinite, and overflowing intervals are rejected.

The current speed and current heading are assumed constant over the entire preceding interval. This is an explicit integration approximation: a window-end speed is not a measured average over that interval. Large finite intervals are accepted; there is no stale-data or maximum-gap policy here. Issue #15 must establish that policy before system use.

Batch integration requires an **explicit initial_timestamp strictly before the first prediction**. The known starting position must correspond to that time. There is no automatic t=0 initialization. For example, an initial time of 9 s and first window-end prediction at 10 s produce one second of propagation, not ten. An equal first timestamp is rejected. If that interval cannot be justified, the caller must establish a later known initialization and submit only subsequent predictions.

Heading follows Issue #6: degrees clockwise from true north, 0 North, 90 East, 180 South, 270 West. Require `[0, 360)`; 360 is rejected. A supplied heading is used for that step and retained; omission reuses the last heading. No heading estimation or phone-frame rotation occurs.

`to_navigation_output` requires the independently known Unix epoch in integer milliseconds corresponding to local clock zero. It computes `unix_origin_ms + round(timestamp * 1000)` with nearest-millisecond, ties-to-even rounding. Relative IO-VNBD times do not provide a Unix origin. Quantization can map closely spaced local updates to the same millisecond; downstream ordering policy belongs to the caller. Local dictionaries explicitly contain `timestamp_unit: "seconds"` and are not wire-ready Issue #8 objects. The adapter returns only the contract fields; retain local metadata separately if needed.

## Input validation and explicit speed policies

Inputs follow Issue #6's built-in finite int/float convention, rejecting booleans, strings, None, malformed objects, NaN, infinity, and overflowing numbers. Latitude must be in [-90, 90] and longitude in [-180, 180]; DR normalizes +180 to -180. Negative speed is rejected, never replaced with zero.

The optional `max_speed_mps` must be finite and positive. Its default is None, so no arbitrary vehicle threshold is imposed. Raw estimates strictly above a configured maximum are rejected, never clamped. The boundary value is accepted. This is a caller policy, not a tuned model correction.

`stationary_override` must be an actual boolean. True uses exactly 0.0 m/s while retaining the raw AI estimate in metadata. It requires a caller-provided trusted stationary state; this module infers no motion state. Raw-speed validation and the configured maximum apply **before** the override, so even overridden malformed or over-limit estimates fail. Timestamp and heading validation also remain active. A successful stationary step advances time and optionally heading without displacement.

Validation and DR propagation finish before state is replaced. Failed updates or reinitializations preserve the last state, including its timestamp and heading. Consequently the next accepted update spans from the last accepted timestamp; callers must explicitly handle gaps caused by rejected input. Validation errors raise ValueError; errors from dependencies propagate without committing state.

## Usage and synthetic example

```python
from integration.ai_dead_reckoning.ai_dead_reckoning import (
    AISpeedDeadReckoningIntegrator, integrate_speed_predictions,
    to_navigation_output,
)

dr = AISpeedDeadReckoningIntegrator()
dr.initialize(latitude=0, longitude=0, heading_deg=90, timestamp=0)
trajectory = [dr.update(1, 10), dr.update(2, 10), dr.update(3, 0)]
```

This synthetic sequence advances approximately 20 m east along the equator, ending near latitude 0 and longitude 0.0001798643 degrees. The final zero-speed interval leaves position unchanged. This checks integration behavior, not real navigation accuracy.

Example local result for the first step (rounded coordinates):

```json
{
  "timestamp": 1.0,
  "timestamp_unit": "seconds",
  "latitude": 0.0,
  "longitude": 0.0000899322,
  "speed": 10.0,
  "heading": 90.0,
  "navigation_mode": "DEAD_RECKONING",
  "gnss_status": "UNAVAILABLE",
  "position_error": null,
  "metadata": {
    "raw_estimated_speed_mps": 10.0,
    "used_speed_mps": 10.0,
    "stationary_override_applied": false,
    "elapsed_time_s": 1.0,
    "speed_source": "AI_IMU"
  }
}
```

The mode/status fields describe this DR-only path; they are not a GNSS detector. Unknown position error remains null, with no invented confidence.

```python
predictions = [
    {"time_s": 10.0, "estimated_speed": 10.0, "run_id": "demo"},
    {"time_s": 11.0, "estimated_speed": 0.0, "run_id": "demo"},
]
trajectory = integrate_speed_predictions(
    0, 0, 90, predictions, initial_timestamp=9.0,
)
# Only when this clock's actual Unix origin is independently known:
wire_result = to_navigation_output(trajectory[-1], unix_origin_ms=1725552000000)
```

Batch input is a nonempty list/tuple in strict chronological order; it is not sorted or repaired. `time_s` and `estimated_speed` are required. Optional run_id (nonempty string or None) is retained, and changing run IDs, including known to unknown, is rejected. Each run needs a separate known initialization. Extra Issue #3 fields such as target_index are ignored. No reference_speed, GPS speed, or vehicle labels are needed or used. There is one trajectory point per prediction. Batch integration uses a local state object and returns no partial trajectory on failure; input rows are untouched. It uses fixed initial heading and no stationary override; callers with per-step heading/motion information should use the stateful API.

## Tests and scope

Synthetic unittest tests need no dataset or internet. The inference convenience test patches Issue #3 inference; it verifies delegation without training. Existing AI regression tests separately exercise prediction and feature construction.

```text
python -B -m unittest discover -s integration/ai_dead_reckoning/tests -v
python -B -m unittest discover -s evaluation/tests -v
python -B -m unittest discover -s ai/tests -v
python -B -m unittest discover -s preprocessing/tests -v
python -B -m unittest discover -s dataset/tests -v
python -B -m unittest discover -s navigation_engine/dead_reckoning/tests -v
python -B -m unittest discover -s navigation_engine/alignment/tests -v
python -B -m unittest discover -s navigation_engine/gnss/tests -v
python -B -m unittest discover -s navigation_engine/mode_switching/tests -v
```

GNSS switching remains separate in Issue #10. Map matching remains separate in Issue #13; alignment stays in Issue #5. Final system integration belongs to Issue #15, including clock association, trustworthy heading/motion sources, missing/stale-speed fallback, and coordination with GNSS switching. Trajectory-level testing belongs to Issue #16. No model tuning, retraining, real-data LORO rerun, map matching, NHC, or navigation accuracy claim is part of Issue #14.
