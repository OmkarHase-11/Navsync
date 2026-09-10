import 'package:latlong2/latlong.dart';

/// A route projection, not a position accuracy or confidence estimate.
class MapMatchResult {
  final LatLng matchedPosition;
  final bool matched;

  /// Distance to the selected candidate (possibly heading-preferred).
  /// Null when fewer than two route points exist.
  final double? distanceToRouteMeters;

  /// Zero-based start index of the selected segment; -1 for no segment.
  final int segmentIndex;
  final double? segmentProgress;

  /// Smallest angular difference between heading and segment bearing.
  /// Null when heading is unavailable or the segment is degenerate.
  final double? headingDifferenceDegrees;

  const MapMatchResult({
    required this.matchedPosition,
    required this.matched,
    required this.distanceToRouteMeters,
    required this.segmentIndex,
    this.segmentProgress,
    this.headingDifferenceDegrees,
  });
}
