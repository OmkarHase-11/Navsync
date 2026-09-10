import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/navigation_state.dart';
import 'package:mobile/theme/navsync_theme.dart';
import 'package:mobile/widgets/navigation_map.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    NavigationState state, {
    bool follow = true,
    VoidCallback? onPan,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMap(
          state: state,
          isAutoTracking: follow,
          onRecenter: () {},
          onUserPan: onPan ?? () {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('standard attribution stays visible and opens OSM copyright', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await mount(tester, NavigationState());
    final attribution = tester.widget<SimpleAttributionWidget>(
      find.byType(SimpleAttributionWidget),
    );
    expect(attribution.alignment, Alignment.bottomLeft);
    expect(
      find.text('OpenStreetMap\ncontributors').hitTestable(),
      findsOneWidget,
    );
    final tile = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(
      tile.tileProvider.headers['User-Agent'],
      contains('com.navsync.app'),
    );
    await tester.tap(find.text('OpenStreetMap\ncontributors'));
    await tester.pump();
    expect(calls.single.method, 'launch');
    expect(
      calls.single.arguments['url'],
      'https://www.openstreetmap.org/copyright',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('street tiles, route layers, markers and heading are preserved', (
    tester,
  ) async {
    final state = NavigationState(
      navigationActive: true,
      simulatedGnssAvailable: false,
      currentWaypointIndex: 2,
      segmentProgress: 0.5,
      heading: 90,
    );
    state.deadReckoningBreadcrumbs.addAll([
      NavigationState.routeWaypoints[2].position,
      state.currentPosition,
    ]);
    await mount(tester, state);
    final tile = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(tile.urlTemplate, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    final lines = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines;
    expect(lines.length, 3);
    expect(lines.first.points.first, state.currentPosition);
    expect(
      lines.first.points.last,
      NavigationState.routeWaypoints.last.position,
    );
    expect(lines.first.color, NavSyncTheme.warning);
    expect(
      lines[1].points.first,
      NavigationState.routeWaypoints.first.position,
    );
    expect(lines[1].points.last, state.currentPosition);
    expect(lines.last.pattern.segments, [12, 6]);
    final markers = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers;
    expect(markers.length, 2);
    expect(markers.first.point, state.currentPosition);
    expect(markers.first.rotate, false);
    expect(markers.last.point, NavigationState.routeWaypoints.last.position);
    expect((markers.last.child as Tooltip).message, state.destinationName);
    final transform = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byIcon(Icons.navigation),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(
      transform.transform.entry(0, 0),
      closeTo(math.cos(math.pi / 2), 1e-9),
    );
    expect(transform.transform.entry(1, 0), closeTo(1, 1e-9));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('follow, user drag and recenter distinguish camera origins', (
    tester,
  ) async {
    final state = NavigationState(navigationActive: true, heading: 90);
    var pans = 0;
    await mount(tester, state, onPan: () => pans++);
    var map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final controller = map.mapController!;
    expect(controller.camera.zoom, 17.5);
    expect(controller.camera.rotation, -90);
    state.segmentProgress = 0.5;
    await mount(tester, state, onPan: () => pans++);
    expect(controller.camera.center, state.currentPosition);
    expect(pans, 0);
    await tester.drag(find.byType(FlutterMap), const Offset(80, 40));
    await tester.pump();
    expect(pans, greaterThan(0));
    await mount(tester, state, follow: false);
    final center = controller.camera.center;
    state.segmentProgress = 0.8;
    await mount(tester, state, follow: false);
    expect(controller.camera.center, center);
    await mount(tester, state);
    expect(controller.camera.center, state.currentPosition);
    state.navigationActive = false;
    await mount(tester, state);
    expect(controller.camera.zoom, 15);
    expect(controller.camera.rotation, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('finished route omits single-point active line', (tester) async {
    final state = NavigationState(
      currentWaypointIndex: NavigationState.routeWaypoints.length - 1,
    );
    await mount(tester, state);
    expect(
      tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
