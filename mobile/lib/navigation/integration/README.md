# Issue #15 navigation integration

This is an adapter-backed integration, not a claim that Python runs inside Flutter.
The default app still uses the existing demo. An explicitly configured
`NavigationScreen(navigationPipeline: pipeline)` consumes the actual
`SensorRuntimeController.sensorDataStream` instead of running the simulation timer.
It waits for a valid result before displaying a live position. Start/Stop control
both acquisition and the pipeline. No fabricated speed or heading provider is
installed. Hardware deployment still needs an application-supplied transport and
an externally evaluated speed/heading source; this repository contains no deployed
server, on-device Python runtime, or new model wrapper.

## Data path and reuse

```text
Issue #11 SensorDataAssembler (real sensor timestamps and GNSS freshness)
  -> NavigationPipeline + injected MotionProvider
  -> injected NavigationExchange (one trip-scoped Python session)
  -> Issue #9 GNSS validation
  -> optional Issue #5 calibrated phone-to-vehicle rotation
  -> Issue #14 speed validation / stationary override / sequential DR
  -> Issue #10 source switching + Issue #6 propagation
  -> raw NavigationOutput
  -> Issue #13 loaded-route MapMatcher (Dart)
  -> separate display candidate -> NavigationState -> Issue #12 FlutterMap
```

`integration/navigation_pipeline/navigation_session.py` composes the existing
Python APIs without porting their math. Issue #14 and Issue #10 both delegate to
Issue #6; on an outage each computes the same propagation with identical inputs.
Both states are committed together only after successful processing. This small
duplication of calls preserves the public APIs without changing their modules.

The session supports newline-delimited JSON over stdin/stdout for a supplied host
transport. From the repository root:

```text
python -B -m integration.navigation_pipeline.navigation_session
```

Each request is either `{"operation":"reset"}` or an update containing
`sensor` (canonical SensorData JSON), `motion` (`timestamp`, `speed_mps`,
`heading_deg`, `stationary_override`), `gnss_prevalidated: true`, and optional
`mount_radians: [roll,pitch,yaw]`. Responses contain `raw` NavigationOutput,
optional `aligned_imu`, GNSS reason, and speed-policy metadata; errors contain
`error`. Reset returns `{"reset":true}`. Use one session per pipeline, preserve
request order, and do not share it across trips or clients. No map-matched point
is sent to this session.

`NavigationExchange` is an asynchronous JSON request/response callback; the
application provides its implementation. `MotionProvider` accepts a SensorData
snapshot and returns a timestamp-associated MotionEstimate, or null when not
available. It may call an existing host-side Issue #3 inference workflow; no model
is loaded, retrained, or executed by this Dart layer. Unit tests inject deterministic
motion and protocol fixtures, while Python tests exercise actual existing DR APIs.

Create a `NavigationPipeline(exchange: ..., motionProvider: ..., route: ...)`
and pass it to NavigationScreen with the existing sensor controller. `route` and
optional mount are copied on construction. `latest` exposes a
NavigationPipelineResult, `error` describes waiting/rejection, and `running`
describes subscription lifecycle. `start(stream)`, `stop()`, and `dispose()` manage
the pipeline. The screen stops an injected pipeline but its owner disposes it.

## GNSS, timing, and state

First usable GNSS plus valid supplied motion initializes a known raw position.
GNSS availability returns GNSS_INS using the GNSS coordinates directly. This mode
name does not imply Kalman fusion. Outages advance from the previous raw DR state;
recovery uses the recovered GNSS coordinates and reinitializes DR there. A missing
initial GNSS position or missing speed/heading emits an error, not a fake output.

SensorData uses integer Unix milliseconds. Motion must have the same timestamp.
The host subtracts the first accepted epoch and divides elapsed milliseconds by
1000 for Issue #14 seconds; output retains the original integer timestamp.
Repeated/decreasing epochs are rejected without state changes. The host defaults to `max_gap_ms=None`: valid longer intervals continue DR.
Callers may explicitly configure a positive millisecond limit to reject larger
intervals until GNSS re-anchors. This disabled-by-default safety policy is not a
project requirement or navigation accuracy threshold. The current speed and heading
apply across the preceding accepted interval, as documented by Issue #14.

The existing assembler checks the original GNSS fix epoch, accuracy, and future
fixes before producing SensorData. SensorData itself does not retain that fix
epoch. `gnss_prevalidated` therefore asserts that the input came from that trusted
assembler; Python rechecks validity/accuracy but does not claim to reconstruct fix
age from the snapshot epoch. Other clients must supply `fix_timestamp_ms` or perform
the same upstream validation. Never mark arbitrary/stale payloads prevalidated.

Only one motion/request operation is in flight. While busy, a single pending slot
retains the newest strictly increasing snapshot, replacing older pending samples.
Processing drains that slot serially; memory is bounded and no stale backlog builds.
DR uses the actual elapsed measurement time between accepted snapshots, including
skipped samples, without an arbitrary default outage cutoff. Speed and heading
are assumed representative of that interval; coalescing does not reconstruct motion.
There is no transport timeout implementation: supply a bounded/cancellable transport
for deployment. Generation checks discard responses from stopped trips. A new start
waits for outstanding work and resets the host before subscribing. Stop clears the
published result immediately; next start always resets host state. Background sensor
pause preserves state. On resume the elapsed interval is integrated unless an
explicit caller gap policy rejects it; accuracy across unobserved motion is unknown.

## Raw versus display and UI

NavigationPipelineResult holds `raw` and optional `mapMatch` without duplicating
NavigationOutput fields. `displayPosition` uses the match only when matched is true;
otherwise it returns the raw coordinates. Matching can be disabled with
`mapMatching: false`. NavigationState retains raw currentPosition/navigationOutput;
only marker/follow/remaining-route display consumes displayPosition. Breadcrumbs
retain raw DR positions. Corrections never feed back into GNSS or DR state.

The existing Start/Stop, recenter, user pan, route layers, status rendering, and
destination remain. Injected live mode disables the simulated GNSS toggle and
shows adapter errors; when a sample fails after initialization the last accepted
position remains visible with that error (not a newly valid current fix). Demo
waypoint progression/turn guidance is not a live routing service and is not advanced
by this pipeline. The default screen retains its prototype simulation for existing
callers. Tests cover both paths.

## Motion and accuracy limitations

Heading is externally supplied clockwise from true north in [0,360); there is no
new magnetometer heading estimator. A mount must be explicitly calibrated in radians
to enable Issue #5 alignment. Rotated values are returned separately for inspection;
they are not silently substituted into the phone-frame features used by Issue #3.
Gravity remains present. A null mount means alignment is not applied, not that a
zero-angle calibration was inferred.

Issue #14 rejects invalid/negative speed and applies its optional maximum and
trusted stationary override. The raw estimate remains available. Issue #4 reported
weak generalization (MAE 6.89202 m/s, stationary false motion 87.63%); this integration
does not improve it or establish navigation accuracy. There is no full sensor fusion,
full OSM road graph, lane-level matching, UKF/EKF/HMM, routing, or model retraining.
Map matching uses only the supplied sparse route, with the existing 40 m default.
Independent trajectory validation remains necessary.

## Validation

From `mobile/`: `flutter pub get`, `flutter analyze`, `flutter test`.
Focused Dart tests: `flutter test test/navigation/integration/`.
From root: `python -B -m unittest discover -s integration/navigation_pipeline/tests -v`.
The Python tests cover real GNSS/outage/recovery propagation, elapsed time, reset,
atomic failure, speed policy, GNSS freshness, alignment, and public-API reuse.
Flutter tests cover the adapter contract, raw/display separation, no correction
feedback, stale responses, waiting, lifecycle, and live screen consumption. They
do not demonstrate physical-device inference or a deployed transport.
