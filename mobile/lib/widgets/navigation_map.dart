import 'package:flutter/material.dart' hide NavigationMode;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mobile/models/navigation_output.dart';
import 'package:mobile/models/navigation_state.dart';
import 'package:mobile/theme/navsync_theme.dart';

/// Master Google Maps Navigation Widget
///
/// Features:
/// - Real Google Maps engine with customized dark navigation styling
/// - Active navigation route polyline & travelled path de-emphasis
/// - Real-time vehicle location marker rotating according to heading
/// - Dead Reckoning estimated trajectory breadcrumbs
/// - Camera auto-follow with smooth perspective tilt
/// - Interactive pan/zoom with floating Re-Center button
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
  GoogleMapController? _mapController;
  BitmapDescriptor? _vehicleIcon;
  BitmapDescriptor? _destinationIcon;

  @override
  void initState() {
    super.initState();
    _loadCustomMarkers();
  }

  Future<void> _loadCustomMarkers() async {
    // Standard high-visibility navigation markers
    _vehicleIcon = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueOrange,
    );
    _destinationIcon = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueRed,
    );
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant NavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAutoTracking && _mapController != null) {
      _updateCameraPosition();
    }
  }

  void _updateCameraPosition() {
    final output = widget.state.navigationOutput;
    final pos = LatLng(output.latitude, output.longitude);
    final heading = output.heading;

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pos,
          zoom: widget.state.navigationActive ? 17.5 : 15.0,
          tilt: widget.state.navigationActive ? 40.0 : 0.0,
          bearing: widget.state.navigationActive ? heading : 0.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final output = widget.state.navigationOutput;
    final curPos = LatLng(output.latitude, output.longitude);
    final isDeadReckoning =
        output.navigationMode == NavigationMode.deadReckoning;

    // 1. Build Polylines
    final Set<Polyline> polylines = {};

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
          polylineId: const PolylineId('active_route'),
          points: remainingPoints,
          color: isDeadReckoning
              ? NavSyncTheme.warning
              : const Color(
                  0xFF1E88E5,
                ), // Blue in GNSS, Orange in Dead Reckoning
          width: 6,
          jointType: JointType.round,
          endCap: Cap.roundCap,
          startCap: Cap.roundCap,
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
          polylineId: const PolylineId('travelled_route'),
          points: travelledPoints,
          color: NavSyncTheme.secondaryText.withValues(alpha: 0.5),
          width: 5,
        ),
      );
    }

    // Dead Reckoning Estimated Trail (Wow Factor)
    if (isDeadReckoning && widget.state.deadReckoningBreadcrumbs.length > 1) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('dead_reckoning_trail'),
          points: widget.state.deadReckoningBreadcrumbs,
          color: NavSyncTheme.idrBlueLight,
          width: 4,
          patterns: [PatternItem.dash(12), PatternItem.gap(6)],
        ),
      );
    }

    // 2. Build Markers
    final Set<Marker> markers = {
      // Vehicle Location Marker
      Marker(
        markerId: const MarkerId('vehicle_marker'),
        position: curPos,
        rotation: output.heading,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        icon: _vehicleIcon ?? BitmapDescriptor.defaultMarker,
        infoWindow: InfoWindow(
          title: isDeadReckoning
              ? 'Estimated Position (Dead Reckoning)'
              : 'Current Position',
        ),
      ),

      // Destination Marker
      Marker(
        markerId: const MarkerId('destination_marker'),
        position: NavigationState.routeWaypoints.last.position,
        icon: _destinationIcon ?? BitmapDescriptor.defaultMarker,
        infoWindow: InfoWindow(
          title: widget.state.destinationName,
          snippet: 'Destination',
        ),
      ),
    };

    return SizedBox.expand(
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: curPos,
          zoom: 16.0,
          tilt: widget.state.navigationActive ? 40.0 : 0.0,
          bearing: widget.state.navigationActive ? output.heading : 0.0,
        ),
        mapType: MapType.hybrid,
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        compassEnabled: true,
        mapToolbarEnabled: false,
        polylines: polylines,
        markers: markers,
        onMapCreated: (controller) {
          _mapController = controller;
          _updateCameraPosition();
        },
        onCameraMoveStarted: () {
          widget.onUserPan();
        },
      ),
    );
  }
}
