import 'dart:math' as math;

import 'package:flutter/material.dart' hide NavigationMode;
import 'package:latlong2/latlong.dart';
import 'package:mobile/models/navigation_output.dart';
import 'package:mobile/navigation/map_matching/map_matcher.dart';
import 'package:mobile/navigation/map_matching/map_match_result.dart';

/// Navigation waypoint along real urban roads
class NavWaypoint {
  final LatLng position;
  final String streetName;
  final String instruction;
  final IconData maneuverIcon;
  final double speedTarget;

  const NavWaypoint({
    required this.position,
    required this.streetName,
    required this.instruction,
    required this.maneuverIcon,
    this.speedTarget = 42.0,
  });
}

/// Central state model for NavSync navigation
///
/// Holds trip metrics, real Pune coordinates, vehicle heading, speed,
/// ETA calculations, GNSS status, and Dead Reckoning breadcrumb history.
class NavigationState {
  static final _mapMatcher = MapMatcher();

  /// Optional route projection; never feeds back into raw simulation or output.
  MapMatchResult get mapMatchResult {
    final position = currentPosition;
    return _mapMatcher.match(
      latitude: position.latitude,
      longitude: position.longitude,
      headingDegrees: heading,
      route: routeWaypoints.map((waypoint) => waypoint.position).toList(),
    );
  }

  LatLng get mapMatchedPosition => mapMatchResult.matchedPosition;

  bool navigationActive;
  bool simulatedGnssAvailable;
  double _speedMps = 0.0; // Internal speed in m/s (contract unit)
  double heading;
  int currentWaypointIndex;
  double segmentProgress; // 0.0 to 1.0 between current and next waypoint
  int gnssCycleCounter;

  // Breadcrumbs recorded during Dead Reckoning mode for path estimation display
  final List<LatLng> deadReckoningBreadcrumbs = [];

  // Destination metadata
  String destinationName;
  double totalTripDistanceKm;

  NavigationState({
    this.navigationActive = false,
    this.simulatedGnssAvailable = true,
    this.heading = 165.0,
    this.currentWaypointIndex = 0,
    this.segmentProgress = 0.0,
    this.gnssCycleCounter = 0,
    this.destinationName = 'Pune Central Railway Station',
    this.totalTripDistanceKm = 3.8,
  });

  /// The latest canonical NavigationOutput for consumption by the UI
  /// and future backend integration.
  ///
  /// Speed is in m/s; use [NavigationOutput.speedKmh] for display.
  /// Mode/status pairings follow the contract:
  ///   GNSS_INS + AVAILABLE
  ///   DEAD_RECKONING + UNAVAILABLE
  NavigationOutput get navigationOutput {
    final pos = currentPosition;
    return NavigationOutput(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      latitude: pos.latitude,
      longitude: pos.longitude,
      speedMps: _speedMps,
      heading: heading,
      navigationMode: simulatedGnssAvailable
          ? NavigationMode.gnssIns
          : NavigationMode.deadReckoning,
      gnssStatus: simulatedGnssAvailable
          ? GnssStatus.available
          : GnssStatus.unavailable,
      // No real position-error estimator yet; null means unknown
      positionError: null,
    );
  }

  // ── Real Pune Urban Road Waypoints ─────────────────────────────────────────
  // Route: Shivajinagar -> FC Road -> Deccan Gymkhana -> JM Road -> Sambhaji Bridge -> Pune Station
  static const List<NavWaypoint> routeWaypoints = [
    NavWaypoint(
      position: LatLng(18.5308, 73.8436),
      streetName: 'Shivaji Nagar Blvd',
      instruction: 'Head south on Shivaji Nagar Blvd',
      maneuverIcon: Icons.straight_rounded,
      speedTarget: 45.0,
    ),
    NavWaypoint(
      position: LatLng(18.5262, 73.8428),
      streetName: 'FC Road Corridor',
      instruction: 'Continue onto Fergusson College Rd',
      maneuverIcon: Icons.straight_rounded,
      speedTarget: 40.0,
    ),
    NavWaypoint(
      position: LatLng(18.5204, 73.8415),
      streetName: 'Fergusson College Rd',
      instruction: 'In 300 m, turn left onto Goodluck Chowk',
      maneuverIcon: Icons.turn_left_rounded,
      speedTarget: 36.0,
    ),
    NavWaypoint(
      position: LatLng(18.5178, 73.8442),
      streetName: 'Deccan Gymkhana Way',
      instruction: 'Turn left onto JM Road Transit Way',
      maneuverIcon: Icons.turn_left_rounded,
      speedTarget: 34.0,
    ),
    NavWaypoint(
      position: LatLng(18.5190, 73.8490),
      streetName: 'JM Road Transit Way',
      instruction: 'Continue straight toward Sambhaji Bridge',
      maneuverIcon: Icons.straight_rounded,
      speedTarget: 48.0,
    ),
    NavWaypoint(
      position: LatLng(18.5172, 73.8545),
      streetName: 'Sambhaji Bridge Overpass',
      instruction: 'Cross Sambhaji Bridge toward Station Rd',
      maneuverIcon: Icons.fork_right_rounded,
      speedTarget: 44.0,
    ),
    NavWaypoint(
      position: LatLng(18.5225, 73.8640),
      streetName: 'Station Approach Road',
      instruction: 'In 400 m, your destination will be on the left',
      maneuverIcon: Icons.turn_left_rounded,
      speedTarget: 38.0,
    ),
    NavWaypoint(
      position: LatLng(18.5284, 73.8744),
      streetName: 'Pune Central Station',
      instruction: 'You have arrived at Pune Central Station',
      maneuverIcon: Icons.place_rounded,
      speedTarget: 20.0,
    ),
  ];

  /// Get current interpolated vehicle coordinates
  LatLng get currentPosition {
    if (routeWaypoints.isEmpty) return const LatLng(18.5204, 73.8415);
    if (currentWaypointIndex >= routeWaypoints.length - 1) {
      return routeWaypoints.last.position;
    }

    final p0 = routeWaypoints[currentWaypointIndex].position;
    final p1 = routeWaypoints[currentWaypointIndex + 1].position;

    final lat = p0.latitude + (p1.latitude - p0.latitude) * segmentProgress;
    final lng = p0.longitude + (p1.longitude - p0.longitude) * segmentProgress;
    return LatLng(lat, lng);
  }

  /// Current turn-by-turn guidance instruction
  NavWaypoint get currentGuidance {
    final idx = currentWaypointIndex.clamp(0, routeWaypoints.length - 1);
    return routeWaypoints[idx];
  }

  /// Distance to the next turn maneuver in meters
  int get distanceToNextTurnMeters {
    if (currentWaypointIndex >= routeWaypoints.length - 1) return 0;
    final p0 = currentPosition;
    final p1 = routeWaypoints[currentWaypointIndex + 1].position;
    final meters = _distanceBetweenMeters(p0, p1);
    return meters.round();
  }

  /// Total remaining distance for the trip in kilometers
  double get remainingDistanceKm {
    if (!navigationActive) return totalTripDistanceKm;
    if (currentWaypointIndex >= routeWaypoints.length - 1) return 0.0;

    double dist = _distanceBetweenMeters(
      currentPosition,
      routeWaypoints[currentWaypointIndex + 1].position,
    );

    for (int i = currentWaypointIndex + 1; i < routeWaypoints.length - 1; i++) {
      dist += _distanceBetweenMeters(
        routeWaypoints[i].position,
        routeWaypoints[i + 1].position,
      );
    }
    return (dist / 1000.0).clamp(0.0, totalTripDistanceKm);
  }

  /// Estimated time remaining in minutes
  int get remainingMinutes {
    if (!navigationActive) return 12;
    // Base estimate at avg 30 km/h in city traffic
    final mins = (remainingDistanceKm / 30.0 * 60).round();
    return mins.clamp(1, 45);
  }

  /// Formatted Estimated Time of Arrival (e.g. "21:05")
  String get formattedEta {
    final now = DateTime.now();
    final arrival = now.add(Duration(minutes: remainingMinutes));
    final hour = arrival.hour.toString().padLeft(2, '0');
    final min = arrival.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }

  /// Start navigation simulation
  void start() {
    navigationActive = true;
    simulatedGnssAvailable = true;
    _speedMps = 38.0 / 3.6; // ~10.56 m/s (displays as ~38 km/h)
    currentWaypointIndex = 0;
    segmentProgress = 0.0;
    gnssCycleCounter = 0;
    deadReckoningBreadcrumbs.clear();
    _updateMetrics();
  }

  /// Stop navigation simulation and reset
  void stop() {
    navigationActive = false;
    simulatedGnssAvailable = true;
    _speedMps = 0.0;
    currentWaypointIndex = 0;
    segmentProgress = 0.0;
    gnssCycleCounter = 0;
    deadReckoningBreadcrumbs.clear();
    _updateMetrics();
  }

  /// Manually toggle GNSS failure (for demo & testing)
  void toggleManualGnss() {
    simulatedGnssAvailable = !simulatedGnssAvailable;
    if (!simulatedGnssAvailable) {
      gnssCycleCounter = 250; // Jump into failure window (220..340)
    } else {
      gnssCycleCounter = 0;
      deadReckoningBreadcrumbs.clear();
    }
  }

  /// Step simulation by delta time (seconds)
  void stepSimulation(double dt) {
    if (!navigationActive) return;

    if (currentWaypointIndex >= routeWaypoints.length - 1) {
      // Loop route seamlessly for continuous demonstration
      currentWaypointIndex = 0;
      segmentProgress = 0.0;
      deadReckoningBreadcrumbs.clear();
    }

    final p0 = routeWaypoints[currentWaypointIndex].position;
    final p1 = routeWaypoints[currentWaypointIndex + 1].position;
    final segmentDist = _distanceBetweenMeters(p0, p1);

    if (segmentDist > 0) {
      // Advance by meters = speed (m/s) * dt (s)
      final deltaMeters = _speedMps * dt;
      segmentProgress += (deltaMeters / segmentDist);

      if (segmentProgress >= 1.0) {
        segmentProgress = 0.0;
        currentWaypointIndex++;
        if (currentWaypointIndex >= routeWaypoints.length - 1) {
          currentWaypointIndex = 0;
        }
      }
    }

    _updateMetrics();

    // GNSS cycle: available for ~18s, lost for ~7s
    gnssCycleCounter++;
    final cycle = gnssCycleCounter % 400;
    if (cycle > 220 && cycle < 340) {
      simulatedGnssAvailable = false;
      // Record dead-reckoning breadcrumbs for confidence trail visualization
      if (gnssCycleCounter % 4 == 0) {
        deadReckoningBreadcrumbs.add(currentPosition);
        if (deadReckoningBreadcrumbs.length > 30) {
          deadReckoningBreadcrumbs.removeAt(0);
        }
      }
    } else {
      simulatedGnssAvailable = true;
      if (deadReckoningBreadcrumbs.isNotEmpty) {
        deadReckoningBreadcrumbs.clear();
      }
    }
  }

  void _updateMetrics() {
    if (routeWaypoints.isEmpty) return;

    final curIdx = currentWaypointIndex.clamp(0, routeWaypoints.length - 2);
    final p0 = routeWaypoints[curIdx].position;
    final p1 = routeWaypoints[curIdx + 1].position;

    // Calculate heading angle in degrees (0 = North, 90 = East, 180 = South, 270 = West)
    final dLat = p1.latitude - p0.latitude;
    final dLng = p1.longitude - p0.longitude;
    final rad = math.atan2(dLng, dLat);
    heading = (rad * 180.0 / math.pi + 360.0) % 360.0;

    if (!navigationActive) {
      _speedMps = 0.0;
      return;
    }

    // Target speed with natural city variation — stored in m/s
    // speedTarget is in km/h, convert to m/s for internal use
    final targetKmh = routeWaypoints[curIdx].speedTarget;
    final variationKmh =
        math.sin(segmentProgress * math.pi * 2) * 3.0; // ±3 km/h
    _speedMps = (targetKmh + variationKmh) / 3.6;
  }

  static double _distanceBetweenMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;

    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);

    final aVal =
        sinDLat * sinDLat + sinDLng * sinDLng * math.cos(lat1) * math.cos(lat2);
    final cVal = 2 * math.atan2(math.sqrt(aVal), math.sqrt(1 - aVal));
    return earthRadius * cVal;
  }
}
