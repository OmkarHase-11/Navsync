import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile/models/navigation_state.dart';
import 'package:mobile/navigation/map_matching/map_matcher.dart';

void main() {
  const east = [LatLng(0, 0), LatLng(0, 0.001)];
  final matcher = MapMatcher();

  test('exact point on route projects to segment middle', () {
    final result = matcher.match(latitude: 0, longitude: 0.0005, route: east);
    expect(result.matched, isTrue);
    expect(result.distanceToRouteMeters, closeTo(0, 1e-7));
    expect(result.segmentProgress, closeTo(0.5, 1e-8));
    expect(result.matchedPosition.longitude, closeTo(0.0005, 1e-10));
    expect(result.segmentIndex, 0);
    expect(result.headingDifferenceDegrees, isNull);
  });

  test('offset from horizontal segment is measured in meters', () {
    final result = matcher.match(
      latitude: 0.0001,
      longitude: 0.0005,
      route: east,
    );
    expect(result.matched, isTrue);
    expect(result.distanceToRouteMeters, closeTo(11.11949, 0.001));
    expect(result.matchedPosition.latitude, 0);
    expect(result.matchedPosition.longitude, closeTo(0.0005, 1e-10));
  });

  test('projection clamps to start', () {
    final result = matcher.match(latitude: 0, longitude: -0.0001, route: east);
    expect(result.segmentProgress, 0);
    expect(result.matchedPosition, east.first);
  });

  test('projection clamps to end', () {
    final result = matcher.match(latitude: 0, longitude: 0.0011, route: east);
    expect(result.segmentProgress, 1);
    expect(result.matchedPosition.longitude, closeTo(0.001, 1e-10));
  });

  test('vertical segment projection', () {
    final result = matcher.match(
      latitude: 0.0005,
      longitude: 0.0001,
      route: const [LatLng(0, 0), LatLng(0.001, 0)],
    );
    expect(result.matchedPosition.latitude, closeTo(0.0005, 1e-10));
    expect(result.matchedPosition.longitude, 0);
    expect(result.segmentProgress, closeTo(0.5, 1e-8));
  });

  test('arbitrary diagonal projection', () {
    final result = matcher.match(
      latitude: 0.0004,
      longitude: 0.0006,
      route: const [LatLng(0, 0), LatLng(0.001, 0.001)],
    );
    expect(result.matchedPosition.latitude, closeTo(0.0005, 1e-9));
    expect(result.matchedPosition.longitude, closeTo(0.0005, 1e-9));
    expect(result.distanceToRouteMeters, closeTo(15.7253, 0.001));
  });

  test('longitude distances scale at urban non-equatorial latitude', () {
    final result = matcher.match(
      latitude: 60,
      longitude: 0.0001,
      route: const [LatLng(59.999, 0), LatLng(60.001, 0)],
    );
    expect(result.distanceToRouteMeters, closeTo(5.55975, 0.001));
  });

  test('chooses nearest segment of a bend', () {
    final result = matcher.match(
      latitude: 0.0005,
      longitude: 0.0009,
      route: const [LatLng(0, 0), LatLng(0, 0.001), LatLng(0.001, 0.001)],
    );
    expect(result.segmentIndex, 1);
    expect(result.matched, isTrue);
  });

  test('far position is preserved with nearest diagnostics', () {
    final result = matcher.match(
      latitude: 0.01,
      longitude: 0.0005,
      route: east,
    );
    expect(result.matched, isFalse);
    expect(result.matchedPosition, const LatLng(0.01, 0.0005));
    expect(result.distanceToRouteMeters, greaterThan(1000));
    expect(result.segmentIndex, 0);
    expect(result.segmentProgress, closeTo(0.5, 1e-8));
  });

  test('snap threshold is configurable and inclusive', () {
    final distance = matcher
        .match(latitude: 0.0001, longitude: 0.0005, route: east)
        .distanceToRouteMeters!;
    expect(
      MapMatcher(maxSnapDistanceMeters: distance)
          .match(latitude: 0.0001, longitude: 0.0005, route: east)
          .matched,
      isTrue,
    );
    expect(
      MapMatcher(maxSnapDistanceMeters: distance - 0.01)
          .match(latitude: 0.0001, longitude: 0.0005, route: east)
          .matched,
      isFalse,
    );
    expect(
      MapMatcher(maxSnapDistanceMeters: 0)
          .match(latitude: 0, longitude: 0, route: east)
          .matched,
      isTrue,
    );
  });

  test('duplicate points remain valid point candidates', () {
    final result = matcher.match(
      latitude: 0.0001,
      longitude: 0,
      headingDegrees: 90,
      route: const [LatLng(0, 0), LatLng(0, 0)],
    );
    expect(result.matched, isTrue);
    expect(result.segmentProgress, 0);
    expect(result.headingDifferenceDegrees, isNull);
    expect(result.matchedPosition, const LatLng(0, 0));
  });

  test('duplicate does not hide a closer normal segment', () {
    final result = matcher.match(
      latitude: 0,
      longitude: 0.0005,
      route: const [LatLng(0, 0), LatLng(0, 0), LatLng(0, 0.001)],
    );
    expect(result.segmentIndex, 1);
  });

  const parallel = [
    LatLng(0, 0),
    LatLng(0, 0.001),
    LatLng(0.00002, 0.001),
    LatLng(0.00002, 0),
  ];
  test('heading prefers compatible direction only among near candidates', () {
    final nearest = matcher.match(
      latitude: 0.000009,
      longitude: 0.0005,
      route: parallel,
    );
    final west = matcher.match(
      latitude: 0.000009,
      longitude: 0.0005,
      headingDegrees: 270,
      route: parallel,
    );
    expect(nearest.segmentIndex, 0);
    expect(west.segmentIndex, 2);
    expect(west.headingDifferenceDegrees, closeTo(0, 1e-8));
    expect(
      west.distanceToRouteMeters!,
      greaterThan(nearest.distanceToRouteMeters!),
    );
  });

  test('heading cannot override a much closer segment', () {
    final result = matcher.match(
      latitude: 0.00001,
      longitude: 0.0005,
      headingDegrees: 270,
      route: const [
        LatLng(0, 0),
        LatLng(0, 0.001),
        LatLng(0.0002, 0.001),
        LatLng(0.0002, 0),
      ],
    );
    expect(result.segmentIndex, 0);
  });

  test('heading preference cannot exceed snap threshold', () {
    final result = MapMatcher(maxSnapDistanceMeters: 1.1).match(
      latitude: 0.000009,
      longitude: 0.0005,
      headingDegrees: 270,
      route: parallel,
    );
    expect(result.segmentIndex, 0);
    expect(result.matched, isTrue);
  });

  test('359 versus 1 degree bearing is approximately two degrees', () {
    final route = [
      const LatLng(0, 0),
      LatLng(0.001, 0.001 * math.tan(math.pi / 180)),
    ];
    final result = matcher.match(
      latitude: 0,
      longitude: 0,
      headingDegrees: 359,
      route: route,
    );
    expect(result.headingDifferenceDegrees, closeTo(2, 1e-6));
  });

  test('heading normalization and deterministic equal-distance ties', () {
    const route = [LatLng(0, 0), LatLng(0.001, 0), LatLng(0, 0)];
    for (final heading in [0.0, 360.0, -360.0]) {
      final result = matcher.match(
        latitude: 0.0005,
        longitude: 0,
        headingDegrees: heading,
        route: route,
      );
      expect(result.segmentIndex, 0);
      expect(result.headingDifferenceDegrees, 0);
    }
  });

  test(
    'empty and one-point routes return no match, not a fabricated segment',
    () {
      for (final route in [
        <LatLng>[],
        [const LatLng(0, 0)],
      ]) {
        final result = matcher.match(latitude: 1, longitude: 2, route: route);
        expect(result.matched, isFalse);
        expect(result.matchedPosition, const LatLng(1, 2));
        expect(result.distanceToRouteMeters, isNull);
        expect(result.segmentIndex, -1);
        expect(result.segmentProgress, isNull);
      }
    },
  );

  test('invalid inputs are rejected explicitly', () {
    for (final latitude in [double.nan, double.infinity, -91.0, 91.0]) {
      expect(
        () => matcher.match(latitude: latitude, longitude: 0, route: east),
        throwsArgumentError,
      );
    }
    for (final longitude in [double.nan, double.infinity, -181.0, 181.0]) {
      expect(
        () => matcher.match(latitude: 0, longitude: longitude, route: east),
        throwsArgumentError,
      );
    }
    expect(
      () => matcher.match(
        latitude: 0,
        longitude: 0,
        route: east,
        headingDegrees: double.nan,
      ),
      throwsArgumentError,
    );
    expect(
      () => matcher.match(
        latitude: 0,
        longitude: 0,
        route: [const LatLng(0, 0), LatLng(double.nan, 0)],
      ),
      throwsArgumentError,
    );
    for (final distance in [-1.0, double.nan, double.infinity]) {
      expect(
        () => MapMatcher(maxSnapDistanceMeters: distance),
        throwsArgumentError,
      );
      expect(
        () => MapMatcher(headingTieDistanceMeters: distance),
        throwsArgumentError,
      );
    }
  });

  test('short antimeridian crossing uses wrapped longitude', () {
    final result = matcher.match(
      latitude: 0.0001,
      longitude: 180,
      route: const [LatLng(0, 179.999), LatLng(0, -179.999)],
    );
    expect(result.matched, isTrue);
    expect(result.matchedPosition.longitude.abs(), closeTo(180, 1e-8));
    expect(result.distanceToRouteMeters, closeTo(11.11949, 0.001));
  });

  test('NavigationState exposes matching without mutating raw navigation', () {
    final state = NavigationState(
      navigationActive: true,
      currentWaypointIndex: 2,
      segmentProgress: 0.4,
    );
    final raw = state.currentPosition;
    final before = state.navigationOutput;
    final result = state.mapMatchResult;
    expect(result.matched, isTrue);
    expect(result.distanceToRouteMeters, closeTo(0, 1e-6));
    expect(state.mapMatchedPosition.latitude, closeTo(raw.latitude, 1e-9));
    expect(state.currentPosition, raw);
    expect(state.currentWaypointIndex, 2);
    expect(state.segmentProgress, 0.4);
    expect(state.deadReckoningBreadcrumbs, isEmpty);
    final after = state.navigationOutput;
    expect(after.latitude, before.latitude);
    expect(after.longitude, before.longitude);
    expect(after.speedMps, before.speedMps);
    expect(after.heading, before.heading);
    expect(after.navigationMode, before.navigationMode);
  });
}
