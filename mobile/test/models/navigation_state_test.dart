import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/navigation_output.dart';
import 'package:mobile/models/navigation_state.dart';

void main() {
  group('NavigationState.navigationOutput integration', () {
    late NavigationState state;

    setUp(() {
      state = NavigationState();
    });

    test('initial state produces valid default NavigationOutput', () {
      final output = state.navigationOutput;

      expect(output.latitude, state.currentPosition.latitude);
      expect(output.longitude, state.currentPosition.longitude);
      expect(output.speedMps, 0.0);
      expect(output.speedKmh, 0.0);
      expect(output.heading, state.heading);
      expect(output.heading, greaterThanOrEqualTo(0.0));
      expect(output.heading, lessThan(360.0));
      expect(output.navigationMode, NavigationMode.gnssIns);
      expect(output.gnssStatus, GnssStatus.available);
      expect(output.positionError, isNull);
    });

    test('timestamp is an integer Unix-millisecond value close to now', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final ts = state.navigationOutput.timestamp;
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(ts, isA<int>());
      expect(ts, greaterThanOrEqualTo(before));
      expect(ts, lessThanOrEqualTo(after));
    });

    test('start produces speed in m/s with expected km/h display', () {
      state.start();
      final output = state.navigationOutput;

      expect(state.navigationActive, isTrue);
      // Waypoint 0 target is 45.0 km/h; stored internally as m/s
      expect(output.speedMps, closeTo(45.0 / 3.6, 0.5));
      expect(output.speedKmh, closeTo(45.0, 1.8));
    });

    test('stop produces zero speed in m/s and km/h', () {
      state.start();
      expect(state.navigationOutput.speedMps, greaterThan(0.0));

      state.stop();
      final output = state.navigationOutput;

      expect(state.navigationActive, isFalse);
      expect(output.speedMps, 0.0);
      expect(output.speedKmh, 0.0);
    });

    test('GNSS available produces GNSS_INS + AVAILABLE pairing', () {
      state.start();
      final output = state.navigationOutput;

      expect(output.navigationMode, NavigationMode.gnssIns);
      expect(output.gnssStatus, GnssStatus.available);
    });

    test('GNSS loss produces DEAD_RECKONING + UNAVAILABLE pairing', () {
      state.start();
      state.toggleManualGnss();
      final output = state.navigationOutput;

      expect(output.navigationMode, NavigationMode.deadReckoning);
      expect(output.gnssStatus, GnssStatus.unavailable);

      // Toggle back
      state.toggleManualGnss();
      final restored = state.navigationOutput;

      expect(restored.navigationMode, NavigationMode.gnssIns);
      expect(restored.gnssStatus, GnssStatus.available);
    });

    test('navigationOutput coordinates match simulated currentPosition', () {
      state.start();

      expect(state.navigationOutput.latitude, state.currentPosition.latitude);
      expect(state.navigationOutput.longitude, state.currentPosition.longitude);

      // Step simulation by 1 second
      state.stepSimulation(1.0);

      expect(state.navigationOutput.latitude, state.currentPosition.latitude);
      expect(state.navigationOutput.longitude, state.currentPosition.longitude);
    });

    test(
      'heading remains in range 0 <= heading < 360 through simulation steps',
      () {
        state.start();

        for (int i = 0; i < 50; i++) {
          state.stepSimulation(0.5);
          final heading = state.navigationOutput.heading;
          expect(heading, greaterThanOrEqualTo(0.0));
          expect(heading, lessThan(360.0));
        }
      },
    );

    test('existing simulation behavior still works: automatic GNSS cycle and breadcrumbs', () {
      state.start();

      // Simulate steps to reach automatic GNSS drop window (gnssCycleCounter > 220)
      for (int i = 0; i < 230; i++) {
        state.stepSimulation(0.05);
      }

      // GNSS should be lost automatically in this window
      expect(
        state.navigationOutput.navigationMode,
        NavigationMode.deadReckoning,
      );
      expect(state.navigationOutput.gnssStatus, GnssStatus.unavailable);
      expect(state.deadReckoningBreadcrumbs, isNotEmpty);

      // Advance through restoration window (cycle >= 340)
      for (int i = 0; i < 120; i++) {
        state.stepSimulation(0.05);
      }

      expect(state.navigationOutput.navigationMode, NavigationMode.gnssIns);
      expect(state.navigationOutput.gnssStatus, GnssStatus.available);
      expect(state.deadReckoningBreadcrumbs, isEmpty);
    });
  });
}
