# Loaded-route map matching (Issue #13)

This MVP matches positions against the currently loaded route polyline. It is not full road-network map matching against the complete OpenStreetMap graph.

`MapMatcher.match` takes estimated `latitude`, `longitude`, a `List<LatLng>` route,
and optional `headingDegrees`. It returns an immutable `MapMatchResult` with
`matchedPosition`, `matched`, `distanceToRouteMeters`, `segmentIndex`,
`segmentProgress`, and optional `headingDifferenceDegrees`. Coordinates use
latlong2. The matcher has no Flutter widget, network, sensor, or model dependency.

For each segment, a local equirectangular projection converts degrees to meters
using Earth radius 6,371,000 m and the cosine of the segment's mean latitude.
The dot-product projection is clamped to [0,1], then converted back to a point
on that segment. Longitude deltas wrap across the antimeridian. The closest
candidate wins; equal distances retain the first route segment. Work and temporary
storage are linear in the number of segments. Inputs are not modified.

`maxSnapDistanceMeters` defaults to **40 m**, a configurable MVP limit, not a
validated accuracy threshold. A nearest candidate beyond that distance returns
`matched: false` and the original estimate, while retaining nearest-segment
diagnostics. The threshold is inclusive. With fewer than two points, no segment
exists: preserve the estimate, return false, segmentIndex -1 and null distance,
progress and heading difference. Duplicate vertices act as point candidates
with progress zero and no defined heading. Invalid coordinates, heading, or
configuration raise `ArgumentError`; callers should handle invalid input
explicitly. Geographic bounds and finiteness are validated even on short routes.

Heading is clockwise from north, normalized modulo 360, with smallest angular
difference in [0,180]. Among candidates within `headingTieDistanceMeters`
(default **3 m**) of the geometric nearest distance AND within the snap limit,
prefer the candidate with the smallest heading-to-segment angular difference. Equal bearing differences prefer distance,
then route index. Thus heading cannot cause a snap more than 3 m farther away
under defaults. Set the tie distance to zero for heading influence only at equal
distances. If the nearest segment is degenerate, keep its nearest-point result
without heading tie-breaking. Reported distance/progress refer to the selected
candidate, which can be slightly farther than the purely geometric nearest.

```dart
final result = MapMatcher(maxSnapDistanceMeters: 40).match(
  latitude: estimate.latitude,
  longitude: estimate.longitude,
  headingDegrees: estimate.heading,
  route: NavigationState.routeWaypoints.map((w) => w.position).toList(),
);
// Keep estimate unchanged; result.matchedPosition is a separate candidate.
```

`NavigationState.mapMatchResult` demonstrates this call with currentPosition,
heading, and existing Pune waypoints; `mapMatchedPosition` exposes its position.
No match is fed back into raw NavigationOutput, route progression, breadcrumbs,
speed, or the simulation. The map widget continues to display raw output. This
keeps the demonstration separate from Issue #15's eventual display/fusion wiring.

Snapping can reduce visible lateral DR/GNSS drift when the loaded route is correct.
It can also conceal genuine off-route motion or select the wrong crossing/parallel
segment. Sparse navigation waypoints describe straight chords, not surveyed road
geometry; a snap to a chord need not lie on an actual OSM road. This approximation
is intended for short urban segments, not global or polar routes. There is no
previous-segment state or progression restriction: a new position can recover
anywhere on the route, but ambiguous intersections can cause backward jumps.
Heading is directed by route order and is only a bounded spatial tie-breaker,
not a motion validator. Thresholds require later validation on independent data.

There is no HMM/Viterbi, routing service, road-graph download, offline routing or
tile storage, lane-level positioning, AI retraining, or production navigation
accuracy claim. Sensor collection, GNSS switching, Python DR, and OSM rendering
are unchanged.

From `mobile/`, run `flutter pub get`, `flutter analyze`, and `flutter test`.
Focused deterministic tests: `flutter test test/navigation/map_matching/`.
Tests use synthetic coordinates and the existing demo route, with no live tiles
or network dependency.
