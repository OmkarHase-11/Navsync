import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'map_match_result.dart';

/// Stateless nearest-segment matching for short, local urban route polylines.
class MapMatcher {
  static const _earthRadiusMeters = 6371000.0;
  static const _radiansPerDegree = math.pi / 180;

  final double maxSnapDistanceMeters;
  final double headingTieDistanceMeters;

  MapMatcher({
    this.maxSnapDistanceMeters = 40,
    this.headingTieDistanceMeters = 3,
  }) {
    for (final value in [maxSnapDistanceMeters, headingTieDistanceMeters]) {
      if (!value.isFinite || value < 0) {
        throw ArgumentError('Distance limits must be finite and nonnegative');
      }
    }
  }

  MapMatchResult match({
    required double latitude,
    required double longitude,
    required List<LatLng> route,
    double? headingDegrees,
  }) {
    _validateCoordinates(latitude, longitude);
    for (final point in route) {
      _validateCoordinates(point.latitude, point.longitude);
    }
    if (headingDegrees != null && !headingDegrees.isFinite) {
      throw ArgumentError('Heading must be finite');
    }
    final original = LatLng(latitude, longitude);
    if (route.length < 2) {
      return MapMatchResult(
        matchedPosition: original,
        matched: false,
        distanceToRouteMeters: null,
        segmentIndex: -1,
      );
    }

    final candidates = <MapMatchResult>[];
    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      // Segment-local equirectangular coordinates in meters, origin A.
      final scale = _earthRadiusMeters * _radiansPerDegree;
      final cosLatitude = math.cos(
        (a.latitude / 2 + b.latitude / 2) * _radiansPerDegree,
      );
      final longitudeDelta = _wrappedLongitude(b.longitude - a.longitude);
      final bx = longitudeDelta * scale * cosLatitude;
      final by = (b.latitude - a.latitude) * scale;
      final px =
          _wrappedLongitude(longitude - a.longitude) * scale * cosLatitude;
      final py = (latitude - a.latitude) * scale;
      final lengthSquared = bx * bx + by * by;
      final progress = lengthSquared <= 1e-12
          ? 0.0
          : ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);
      final dx = px - progress * bx;
      final dy = py - progress * by;
      final distance = math.sqrt(dx * dx + dy * dy);
      final bearing = lengthSquared <= 1e-12
          ? null
          : math.atan2(bx, by) / _radiansPerDegree;
      final difference = headingDegrees == null || bearing == null
          ? null
          : _wrappedLongitude(headingDegrees % 360 - bearing).abs();
      candidates.add(
        MapMatchResult(
          matchedPosition: LatLng(
            a.latitude + progress * (b.latitude - a.latitude),
            _wrappedLongitude(a.longitude + progress * longitudeDelta),
          ),
          matched: true,
          distanceToRouteMeters: distance,
          segmentIndex: i,
          segmentProgress: progress,
          headingDifferenceDegrees: difference,
        ),
      );
    }

    // Strict comparison keeps the lower index for equal distances.
    var nearest = candidates.first;
    for (final candidate in candidates.skip(1)) {
      if (candidate.distanceToRouteMeters! < nearest.distanceToRouteMeters!) {
        nearest = candidate;
      }
    }
    if (nearest.distanceToRouteMeters! > maxSnapDistanceMeters) {
      return MapMatchResult(
        matchedPosition: original,
        matched: false,
        distanceToRouteMeters: nearest.distanceToRouteMeters,
        segmentIndex: nearest.segmentIndex,
        segmentProgress: nearest.segmentProgress,
        headingDifferenceDegrees: nearest.headingDifferenceDegrees,
      );
    }

    var selected = nearest;
    if (headingDegrees != null && nearest.headingDifferenceDegrees != null) {
      for (final candidate in candidates) {
        if (candidate.headingDifferenceDegrees == null ||
            candidate.distanceToRouteMeters! > maxSnapDistanceMeters ||
            candidate.distanceToRouteMeters! - nearest.distanceToRouteMeters! >
                headingTieDistanceMeters) {
          continue;
        }
        final difference = candidate.headingDifferenceDegrees!;
        final selectedDifference = selected.headingDifferenceDegrees!;
        if (difference < selectedDifference ||
            (difference == selectedDifference &&
                candidate.distanceToRouteMeters! <
                    selected.distanceToRouteMeters!)) {
          selected = candidate;
        }
      }
    }
    return selected;
  }

  static double _wrappedLongitude(double degrees) =>
      (degrees + 180) % 360 - 180;

  static void _validateCoordinates(double latitude, double longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError(
        'Coordinates must be finite latitude [-90,90], longitude [-180,180]',
      );
    }
  }
}
