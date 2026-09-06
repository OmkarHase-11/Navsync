# GNSS to Dead Reckoning Mode Switching

## Purpose

Issue #10 selects GNSS coordinates or Dead Reckoning (DR) coordinates with a small deterministic controller. It reuses Issue #6 propagation and consumes Issue #9's GNSS status. Python 3.10+ and the standard library suffice. This module maintains navigation continuity after initialization; it does not guarantee a smooth or jump-free trajectory.

## Modes

| navigation_mode | Behavior in this MVP |
| --- | --- |
| GNSS_INS | Use the supplied usable GNSS position directly. |
| DEAD_RECKONING | Propagate from the last successful position using Issue #6. |

These exact strings preserve the [Issue #8 contract](../../integration/interfaces/README.md). GNSS_INS is the contract's mode label; this controller does not implement INS or GNSS/INS fusion mathematics. Its local result is not a complete NavigationOutput and does not claim fusion has occurred.

## GNSS Status

Only the exact built-in strings `AVAILABLE` and `UNAVAILABLE` are accepted. Pass the `.status` of an Issue #9 `GNSSStatusResult`, not the entire result object. The associated GNSS coordinates must belong to the fix evaluated by Issue #9. This controller does not recheck accuracy, age, timestamps, or failure reasons and does not create a new detector.

## State

`NavigationModeController()` starts with `state is None` and `initialized == False`. It remembers only the last successful immutable `NavigationModeResult`, containing latitude, longitude, navigation_mode, and gnss_status. Read-only properties `state` and `initialized` expose this state without another mutable state structure.

`update(gnss_status, gnss_latitude=None, gnss_longitude=None, speed_mps=None, heading_deg=None, elapsed_time_s=None)` returns that result after each successful update. All optional defaults permit the inactive branch's arguments to be omitted; DR still requires valid speed, heading, and time. The result dataclass is a passive local container, not an additional shared interchange contract. There is no position_source field because mode/status already identify the selected source.

Failed updates raise ValueError and leave all state unchanged. Previously returned results remain unchanged after later updates. State describes the last successful update, not necessarily the latest attempted status. Use a separate controller per navigation session and call updates serially; concurrent use is not supported.

Public API: `NavigationModeController`, its `update()` method and `state`/`initialized` properties, frozen `NavigationModeResult`, and the `NavigationMode` type alias. GNSSStatus is imported from Issue #9.

## Initialization

The first successful AVAILABLE update establishes position. An UNAVAILABLE update before that raises `ValueError` with a not-initialized explanation; state remains None and no coordinates or navigation result are invented. There is no fallback to (0,0). A supplied valid GNSS fix at (0,0) is accepted normally.

## GNSS Available

AVAILABLE requires both coordinates. Latitude must be in [-90,90] and longitude in [-180,180], in WGS84 decimal degrees. Both accept built-in int/float values representable as finite floats. Missing values, strings, booleans, lists, dictionaries, other types, NaN, infinities, out-of-range coordinates, and integers outside float range raise ValueError. Valid values are converted to floats without smoothing, normalization, or offset.

The controller stores those coordinates directly with GNSS_INS / AVAILABLE. It does not call DR and ignores all DR parameters, even if omitted or malformed. Invalid AVAILABLE coordinates fail instead of silently falling back to DR. Accuracy/freshness remain Issue #9 responsibilities.

## GNSS Loss

After initialization, UNAVAILABLE calls the existing `propagate_position()` with the last successful latitude/longitude and the supplied speed_mps, heading_deg, elapsed_time_s. The returned position becomes the current position with DEAD_RECKONING / UNAVAILABLE. Consecutive losses propagate from the previous DR output.

GNSS coordinate arguments are ignored entirely in this branch; None is sufficient. Issue #6 validates active DR inputs: finite built-in numeric values, nonnegative speed in m/s, nonnegative elapsed seconds, and heading in [0,360) degrees clockwise from true north (0 North, 90 East, 180 South, 270 West). Its numeric/type/overflow failures propagate as ValueError with state unchanged. No propagation math or DR parameter validator is copied here.

Zero speed or time preserves geographic position according to Issue #6. Its existing +180° to -180° longitude normalization also applies during zero-motion DR; direct GNSS coordinates retain +180° when supplied.

## GNSS Recovery

The first AVAILABLE update with valid coordinates immediately replaces the DR estimate and sets GNSS_INS / AVAILABLE. No multi-sample confirmation, blending, or correction step occurs. The next GNSS loss starts from this recovered fix. Position can jump on recovery; this is the requested direct-switch MVP behavior.

## Sequence Example

All values below are synthetic examples, not recorded measurements or performance results.

```python
from navigation_engine.mode_switching.mode_switching import NavigationModeController

controller = NavigationModeController()
first = controller.update("AVAILABLE", 18.5204, 73.8567)
# GNSS_INS / AVAILABLE, exact supplied coordinates
second = controller.update("UNAVAILABLE", speed_mps=10, heading_deg=90, elapsed_time_s=1)
# DEAD_RECKONING / UNAVAILABLE, moves east from first
third = controller.update("UNAVAILABLE", speed_mps=10, heading_deg=90, elapsed_time_s=1)
# Continues east from second
fourth = controller.update("AVAILABLE", 18.5205, 73.8570)
# GNSS_INS / AVAILABLE, immediately replaces estimate with (18.5205, 73.8570)
```

## Integration

Issue #9 supplies status, Issue #6 supplies propagation, and Issue #10 selects the source. Issue #5 alignment remains independent. Issue #15 will later integrate the complete system. For example, after calling Issue #9, pass `detector_result.status` to update along with its associated coordinates if AVAILABLE, or supplied DR motion inputs if UNAVAILABLE.

The caller owns timing, fix/status association, speed, heading, and ordering. Elapsed time must cover the interval from the stored position's epoch to the intended DR output epoch; after a failed update it must still be measured from the last successful state. In particular, the first outage step must account for the age of the last GNSS fix rather than treating repeated use of that fix as a new measurement. No system clock, timestamp tracking, or freshness policy is introduced here. A later adapter constructs the full NavigationOutput, including timestamp, speed, heading, and optional position_error.

## Limitations

There is no hysteresis, debounce, recovery confirmation, smoothing, Kalman blending/filtering, confidence weighting, GNSS/INS fusion math, map matching, automatic heading, speed estimation, AI, sensor integration, or automatic calibration. The controller inherits Issue #6's spherical-model and accumulated-drift limitations. Recovery resets position directly; it does not estimate drift. The team should review timing/fix association, recovery jumps, and whether field testing later justifies hysteresis or debounce. None of those future policies is implemented now.

## Tests

Run from the repository root:

```text
python -B -m unittest discover -s navigation_engine/mode_switching/tests -v
python -B -m unittest discover -s navigation_engine/dead_reckoning/tests -v
python -B -m unittest discover -s navigation_engine/alignment/tests -v
python -B -m unittest discover -s navigation_engine/gnss/tests -v
```

Tests use synthetic inputs and verify initialization, full outage/recovery sequences, repeated DR, motion directions, zero motion, active-branch validation, ignored inactive inputs, transactional failures, immutability, independent instances, and real Issue #9 status integration. A wrapped Issue #6 function verifies calls use the stored position and confirms AVAILABLE never invokes DR.
