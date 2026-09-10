import 'dart:math' as math;

import 'package:flutter/material.dart' hide NavigationMode;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile/models/navigation_output.dart';
import 'package:mobile/models/navigation_state.dart';
import 'package:mobile/theme/navsync_theme.dart';

/// OpenStreetMap navigation view for the existing simulated route.
class NavigationMap extends StatefulWidget {
  final NavigationState state;
  final bool isAutoTracking;
  final VoidCallback onRecenter;
  final VoidCallback onUserPan;

  const NavigationMap({
    super.key,
    required this.state,
    required this.isAutoTracking,
    required this.onRecenter,
    required this.onUserPan,
  });

  @override
  State<NavigationMap> createState() => _NavigationMapState();
}

class _NavigationMapState extends State<NavigationMap> {
  final MapController _mapController = MapController();
  bool _mapReady = false;

  @override
  void didUpdateWidget(covariant NavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAutoTracking && _mapReady) {
      _updateCameraPosition();
    }
  }

  void _updateCameraPosition() {
    final output = widget.state.navigationOutput;
    // flutter_map rotates the map clockwise, so heading-up uses -heading.
    // This is a 2D street map; perspective tilt is not supported.
    _mapController.moveAndRotate(
      LatLng(output.latitude, output.longitude),
      widget.state.navigationActive ? 17.5 : 15.0,
      widget.state.navigationActive ? -output.heading : 0.0,
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final output = widget.state.navigationOutput;
    final curPos = LatLng(output.latitude, output.longitude);
    final isDeadReckoning =
        output.navigationMode == NavigationMode.deadReckoning;

    // 1. Build Polylines
    final polylines = <Polyline>[];

    // Upcoming route (Active)
    final remainingPoints = <LatLng>[curPos];
    for (
      int i = widget.state.currentWaypointIndex + 1;
      i < NavigationState.routeWaypoints.length;
      i++
    ) {
      remainingPoints.add(NavigationState.routeWaypoints[i].position);
    }

    if (remainingPoints.length > 1) {
      polylines.add(
        Polyline(
          points: remainingPoints,
          color: isDeadReckoning
              ? NavSyncTheme.warning
              : const Color(
                  0xFF1E88E5,
                ), // Blue in GNSS, Orange in Dead Reckoning
          strokeWidth: 6,
        ),
      );
    }

    // Travelled route (Muted)
    if (widget.state.navigationActive &&
        widget.state.currentWaypointIndex > 0) {
      final travelledPoints = <LatLng>[];
      for (int i = 0; i <= widget.state.currentWaypointIndex; i++) {
        travelledPoints.add(NavigationState.routeWaypoints[i].position);
      }
      travelledPoints.add(curPos);

      polylines.add(
        Polyline(
          points: travelledPoints,
          color: NavSyncTheme.secondaryText.withValues(alpha: 0.5),
          strokeWidth: 5,
        ),
      );
    }

    // Dead Reckoning Estimated Trail (Wow Factor)
    if (isDeadReckoning && widget.state.deadReckoningBreadcrumbs.length > 1) {
      polylines.add(
        Polyline(
          points: widget.state.deadReckoningBreadcrumbs,
          color: NavSyncTheme.idrBlueLight,
          strokeWidth: 4,
          pattern: StrokePattern.dashed(segments: [12, 6]),
        ),
      );
    }

    return SizedBox.expand(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: curPos,
          initialZoom: widget.state.navigationActive ? 17.5 : 15.0,
          initialRotation: widget.state.navigationActive
              ? -output.heading
              : 0.0,
          onMapReady: () {
            _mapReady = true;
          },
          onPositionChanged: (camera, hasGesture) {
            if (hasGesture) widget.onUserPan();
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.navsync.app',
          ),
          PolylineLayer(polylines: polylines),
          MarkerLayer(
            markers: [
              Marker(
                point: curPos,
                width: 48,
                height: 48,
                alignment: Alignment.center,
                // Rotate with the map, then apply the vehicle's true heading.
                rotate: false,
                child: Tooltip(
                  message: isDeadReckoning
                      ? 'Estimated Position (Dead Reckoning)'
                      : 'Current Position',
                  child: Transform.rotate(
                    angle: output.heading * math.pi / 180,
                    child: const Icon(
                      Icons.navigation,
                      size: 40,
                      color: NavSyncTheme.warning,
                      shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                    ),
                  ),
                ),
              ),
              Marker(
                point: NavigationState.routeWaypoints.last.position,
                width: 48,
                height: 48,
                alignment: Alignment.topCenter,
                rotate: true,
                child: Tooltip(
                  message: widget.state.destinationName,
                  child: const Icon(
                    Icons.location_on,
                    size: 48,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
          // Always visible above the trip card; no expandable attribution popup.
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 110),
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.black, fontSize: 10),
              child: SimpleAttributionWidget(
                backgroundColor: Colors.white,
                alignment: Alignment.bottomLeft,
                source: const Text('OpenStreetMap\ncontributors'),
                onTap: () async {
                  await launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
