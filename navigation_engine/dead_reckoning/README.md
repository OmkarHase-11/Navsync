# Basic Smartphone Dead Reckoning

## Purpose

Issue #6 estimates a next vehicle position during GNSS unavailability from a known current position, supplied speed, supplied navigation heading, and elapsed time. The caller decides when to use it. This is a stateless Python 3.10+ position propagation layer using only the standard library.

## Inputs

`propagate_position(latitude, longitude, speed_mps, heading_deg, elapsed_time_s)` accepts:

| Input | Unit / valid range |
| --- | --- |
| latitude | WGS84 decimal degrees, -90 through +90 inclusive |
| longitude | WGS84 decimal degrees, -180 through +180 inclusive |
| speed_mps | Meters per second, nonnegative |
| heading_deg | Degrees clockwise from true north, 0 <= heading < 360 |
| elapsed_time_s | Seconds, nonnegative |

All values must be built-in int/float values representable as finite Python floats. Zero and valid negative coordinates are accepted. Strings, booleans, None, NaN, either infinity, lists, dictionaries, other types, out-of-range values, and integers exceeding float range raise `ValueError`. Inputs are not silently clamped or strings parsed. A nonfinite speed-times-time product also raises ValueError. Every input is checked even when speed or time is zero.

## Output

The public frozen `DeadReckoningResult` dataclass contains `latitude`, `longitude`, and `distance_m`. The function returns finite coordinates with latitude in [-90, 90] and longitude in [-180, 180), plus this step's traveled distance in meters. The dataclass is a result container; callers should obtain validated results through the function. It is not a new NavigationOutput interface. No timestamps, navigation modes, or confidence/error estimates are generated.

## Heading Convention

0° = North, 90° = East, 180° = South, 270° = West. Heading is a supplied vehicle/navigation bearing relative to true north. It is not phone yaw, Issue #5 mounting yaw, uncorrected magnetic heading, or a raw gyro angle. The API rejects 360° rather than normalizing malformed headings.

## Distance

```text
distance_m = speed_mps * elapsed_time_s
```

For example, 10 m/s for 5 s produces 50 m. Speed is treated as constant over each step; no acceleration is integrated.

## Position Propagation

Convert the starting latitude, longitude, and heading from degrees to radians. With lat1, lon1, theta in radians and d in meters:

```text
delta = d / EARTH_RADIUS_M
lat2 = asin(sin(lat1)*cos(delta) + cos(lat1)*sin(delta)*cos(theta))
lon2 = lon1 + atan2(
    sin(theta)*sin(delta)*cos(lat1),
    cos(delta) - sin(lat1)*sin(lat2)
)
latitude_out = degrees(lat2)
longitude_out = (degrees(lon2) + 180) % 360 - 180
```

The asin intermediate is limited to [-1, 1] solely to protect against floating-point roundoff; invalid public values are rejected before the calculation. This is the spherical great-circle destination at the supplied **initial bearing**. A single supplied heading represents each short step; the module does not model heading changes within it. A great circle's local bearing can change along its path, so this is not an exact constant-compass-bearing (rhumb-line) solver. Repeated short steps may use new headings supplied by the caller.

## Earth Model

`EARTH_RADIUS_M = 6371000.0` is an approximate spherical Earth radius for this short-distance MVP, not an exact Earth model. Inputs/outputs retain WGS84 geographic coordinate conventions, but propagation does not solve an ellipsoidal WGS84 geodesic. No centimeter-level, survey-grade, or measured accuracy is claimed.

## Zero Motion

Zero speed or zero elapsed time yields zero distance and preserves the input coordinates exactly after conversion to float, with one representation exception: input longitude +180° becomes -180°. Those longitudes represent the same location. This resolves the boundary between accepting +180° input and always returning longitude in [-180, 180). No other normalization is applied in the zero-motion branch.

## Integration

- Issue #9 detects GNSS availability; this module does not check it.
- Issue #10 will decide when to use GNSS or DR and handle transitions.
- Issue #3 may later supply AI-estimated speed; speed origin is outside this module.
- Issue #5 prepares vehicle-frame sensor vectors that may later help derive motion/heading. Issue #6 uses already-available speed and true-north heading, and does not call alignment.
- Issue #6 only propagates position. The caller supplies an initialized position, derives elapsed seconds (for example from Unix millisecond differences divided by 1000), preserves time association, and constructs any later NavigationOutput.

No existing [Issue #8 interface](../../integration/interfaces/README.md) is changed. Repeated updates require no hidden state:

```python
from navigation_engine.dead_reckoning.dead_reckoning import propagate_position

# Synthetic example, not recorded sensor data or an experimental result.
position = propagate_position(18.5204, 73.8567, 10, 0, 1)
position = propagate_position(position.latitude, position.longitude, 10, 0, 1)
# Each step reports distance_m=10; the caller retains the latest position.
```

## Limitations

Speed and heading must already be available. Speed is constant per step, and one supplied heading represents the step. Road curvature and turns within a step are not modeled. Speed error, heading error, elapsed-time error, the simplified Earth model, and unrepresented road curvature accumulate position error during outages. No drift percentages or performance results are asserted.

There is no drift correction, road/map matching, sensor fusion, Kalman filter, automatic heading calculation, accelerometer/gyroscope integration, gravity removal, full INS, or AI. No GNSS mode switching is implemented. The formula returns finite results at high latitudes, but heading/longitude are degenerate at exact poles and this MVP is not intended for specialized polar navigation. Extremely small motion can be lost to floating-point rounding, and very long propagation is outside the intended short-step use even if numerically accepted.

The team should review speed/heading sources, timing accuracy and update interval, the +180° zero-motion representation, and acceptable spherical-model limitations during field testing. Recovery and correction policies belong to later issues.

## Tests

Run from the repository root:

```text
python -B -m unittest discover -s navigation_engine/dead_reckoning/tests -v
python -B -m unittest discover -s navigation_engine/alignment/tests -v
python -B -m unittest discover -s navigation_engine/gnss/tests -v
```

All tests use synthetic inputs. Direction tests include analytic equatorial/meridian expectations; arbitrary-heading tests independently recover distance and initial bearing from the result. Coordinate tolerance is 1e-9 degrees for ordinary examples, distance tolerance is 1e-6 m, and bearing tolerance is 1e-7 degrees. These verify numerical behavior, not real-world navigation accuracy.
