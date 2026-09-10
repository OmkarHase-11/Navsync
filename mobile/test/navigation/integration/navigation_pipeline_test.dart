import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile/controllers/sensor_runtime_controller.dart';
import 'package:mobile/models/sensor_data.dart';
import 'package:mobile/navigation/integration/navigation_pipeline.dart';
import 'package:mobile/screens/navigation_screen.dart';
import 'package:mobile/widgets/navigation_map.dart';

SensorData sample(int time, {bool available = true}) => SensorData(
  timestamp: time,
  accelerometerX: 0,
  accelerometerY: 0,
  accelerometerZ: 9.8,
  gyroscopeX: 0,
  gyroscopeY: 0,
  gyroscopeZ: 0,
  magnetometerX: 1,
  magnetometerY: 0,
  magnetometerZ: 0,
  latitude: available ? 0.0001 : null,
  longitude: available ? 0.0005 : null,
  gnssAccuracy: available ? 5 : null,
  gnssAvailable: available,
);

// Protocol fixture only. Actual DR propagation is exercised by Python tests.
Map<String, dynamic> response(
  int time, {
  double lat = 0.0001,
  bool available = true,
}) => {
  'raw': {
    'timestamp': time,
    'latitude': lat,
    'longitude': 0.0005,
    'speed': 10.0,
    'heading': 90.0,
    'navigation_mode': available ? 'GNSS_INS' : 'DEAD_RECKONING',
    'gnss_status': available ? 'AVAILABLE' : 'UNAVAILABLE',
    'position_error': null,
  },
};

Future<MotionEstimate?> motion(SensorData sensor) async => MotionEstimate(
  timestamp: sensor.timestamp,
  speedMps: 10,
  headingDegrees: 90,
);

class TestSensors extends SensorRuntimeController {
  final samples = StreamController<SensorData>.broadcast();
  int starts = 0;
  int stops = 0;
  @override
  Stream<SensorData> get sensorDataStream => samples.stream;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 5));
  const route = [LatLng(0, 0), LatLng(0, 0.001)];

  test(
    'busy adapter retains only newest pending sample and serializes processing',
    () async {
      final stream = StreamController<SensorData>();
      final first = Completer<Map<String, dynamic>>();
      final times = <int>[];
      final pipeline = NavigationPipeline(
        route: route,
        motionProvider: motion,
        exchange: (r) async {
          if (r['operation'] == 'reset') return {'reset': true};
          final time = (r['sensor'] as Map)['timestamp'] as int;
          times.add(time);
          if (time == 1000) return first.future;
          return response(time, available: false);
        },
      );
      await pipeline.start(stream.stream);
      stream.add(sample(1000));
      await flush();
      for (final time in [2000, 3000, 10000]) {
        stream.add(sample(time, available: false));
      }
      await flush();
      expect(times, [1000]);
      first.complete(response(1000));
      await flush();
      expect(times, [1000, 10000]);
      expect(pipeline.latest!.raw.timestamp, 10000);
      expect(pipeline.error, isNull);
      pipeline.dispose();
      await stream.close();
    },
  );

  test('adapter failure is surfaced and subsequent sample recovers', () async {
    final stream = StreamController<SensorData>();
    final pipeline = NavigationPipeline(
      route: route,
      motionProvider: motion,
      exchange: (r) async {
        if (r['operation'] == 'reset') return {'reset': true};
        final time = (r['sensor'] as Map)['timestamp'] as int;
        if (time == 2000) throw StateError('transport unavailable');
        if (time == 3000) return {'error': 'invalid speed'};
        return response(time);
      },
    );
    await pipeline.start(stream.stream);
    stream.add(sample(1000));
    await flush();
    stream.add(sample(2000));
    await flush();
    expect(pipeline.error, contains('transport unavailable'));
    expect(pipeline.latest!.raw.timestamp, 1000);
    stream.add(sample(3000));
    await flush();
    expect(pipeline.error, contains('invalid speed'));
    stream.add(sample(4000));
    await flush();
    expect(pipeline.latest!.raw.timestamp, 4000);
    expect(pipeline.error, isNull);
    pipeline.dispose();
    await stream.close();
  });

  test('stop during initialization cannot reopen the subscription', () async {
    final stream = StreamController<SensorData>.broadcast();
    final reset = Completer<Map<String, dynamic>>();
    var calls = 0;
    final pipeline = NavigationPipeline(
      route: route,
      motionProvider: motion,
      exchange: (r) async {
        calls++;
        return reset.future;
      },
    );
    final starting = pipeline.start(stream.stream);
    await flush();
    await pipeline.stop();
    reset.complete({'reset': true});
    await starting;
    stream.add(sample(1000));
    await flush();
    expect(pipeline.running, isFalse);
    expect(pipeline.latest, isNull);
    expect(calls, 1);
    pipeline.dispose();
    await stream.close();
  });

  test('invalid injected speed is rejected before host calls', () async {
    final stream = StreamController<SensorData>();
    var calls = 0;
    final pipeline = NavigationPipeline(
      route: route,
      motionProvider: (s) async => MotionEstimate(
        timestamp: s.timestamp,
        speedMps: double.nan,
        headingDegrees: 0,
      ),
      exchange: (r) async {
        calls++;
        return {'reset': true};
      },
    );
    await pipeline.start(stream.stream);
    stream.add(sample(1000));
    await flush();
    expect(pipeline.error, contains('Invalid or stale motion'));
    expect(calls, 1);
    pipeline.dispose();
    await stream.close();
  });

  test('raw and matched display remain separate; requests never contain corrections', () async {
    final stream = StreamController<SensorData>();
    final requests = <Map<String, dynamic>>[];
    final pipeline = NavigationPipeline(
      route: route,
      motionProvider: motion,
      exchange: (request) async {
        requests.add(request);
        if (request['operation'] == 'reset') return {'reset': true};
        final sensor = request['sensor'] as Map;
        return response(
          sensor['timestamp'] as int,
          available: sensor['gnss_available'] as bool,
        );
      },
    );
    await pipeline.start(stream.stream);
    stream.add(sample(1000));
    await flush();
    expect(pipeline.latest!.raw.latitude, 0.0001);
    expect(pipeline.latest!.displayPosition.latitude, 0);
    expect(pipeline.latest!.mapMatch!.matched, isTrue);
    stream.add(sample(2000, available: false));
    await flush();
    expect(pipeline.latest!.raw.navigationMode.name, 'deadReckoning');
    stream.add(sample(3000));
    await flush();
    expect(pipeline.latest!.raw.navigationMode.name, 'gnssIns');
    expect(requests.last.containsKey('displayPosition'), isFalse);
    expect((requests.last['sensor'] as Map)['latitude'], 0.0001);
    expect((requests.last['motion'] as Map)['speed_mps'], 10);
    pipeline.dispose();
    await stream.close();
  });

  test('failed match and disabled matching use raw position', () async {
    for (final enabled in [true, false]) {
      final stream = StreamController<SensorData>();
      final pipeline = NavigationPipeline(
        route: route,
        motionProvider: motion,
        mapMatching: enabled,
        exchange: (r) async => r['operation'] == 'reset'
            ? {'reset': true}
            : response(1000, lat: 1),
      );
      await pipeline.start(stream.stream);
      stream.add(sample(1000));
      await flush();
      expect(pipeline.latest!.displayPosition.latitude, 1);
      expect(pipeline.latest!.mapMatch?.matched, enabled ? false : null);
      pipeline.dispose();
      await stream.close();
    }
  });

  test('nonincreasing timestamps and unavailable motion retain last result with error', () async {
    final stream = StreamController<SensorData>();
    var hasMotion = true;
    final pipeline = NavigationPipeline(
      route: route,
      motionProvider: (s) async => hasMotion ? await motion(s) : null,
      exchange: (r) async => r['operation'] == 'reset'
          ? {'reset': true}
          : response((r['sensor'] as Map)['timestamp'] as int),
    );
    await pipeline.start(stream.stream);
    stream.add(sample(1000));
    await flush();
    for (final t in [1000, 999]) {
      stream.add(sample(t));
      await flush();
      expect(pipeline.error, contains('strictly increase'));
      expect(pipeline.latest!.raw.timestamp, 1000);
    }
    hasMotion = false;
    stream.add(sample(2000));
    await flush();
    expect(pipeline.error, contains('Waiting for speed'));
    expect(pipeline.latest!.raw.timestamp, 1000);
    pipeline.dispose();
    await stream.close();
  });

  test(
    'stop rejects late responses and next start resets host session',
    () async {
      final stream = StreamController<SensorData>.broadcast();
      final pending = Completer<Map<String, dynamic>>();
      var resets = 0;
      final pipeline = NavigationPipeline(
        route: route,
        motionProvider: motion,
        exchange: (r) async {
          if (r['operation'] == 'reset') {
            resets++;
            return {'reset': true};
          }
          return pending.future;
        },
      );
      await pipeline.start(stream.stream);
      stream.add(sample(1000));
      await flush();
      await pipeline.stop();
      pending.complete(response(1000));
      await flush();
      expect(pipeline.latest, isNull);
      await pipeline.start(stream.stream);
      expect(resets, 2);
      expect(pipeline.latest, isNull);
      pipeline.dispose();
      await stream.close();
    },
  );

  test(
    'stale backend response and invalid motion do not publish output',
    () async {
      final stream = StreamController<SensorData>();
      final pipeline = NavigationPipeline(
        route: route,
        motionProvider: motion,
        exchange: (r) async =>
            r['operation'] == 'reset' ? {'reset': true} : response(0),
      );
      await pipeline.start(stream.stream);
      stream.add(sample(1000));
      await flush();
      expect(pipeline.latest, isNull);
      expect(pipeline.error, contains('Stale navigation response'));
      pipeline.dispose();
      await stream.close();
    },
  );

  testWidgets(
    'screen start consumes live stream, shows display candidate, stop clears trip',
    (tester) async {
      final sensors = TestSensors();
      final pipeline = NavigationPipeline(
        route: route,
        motionProvider: motion,
        exchange: (r) async => r['operation'] == 'reset'
            ? {'reset': true}
            : response((r['sensor'] as Map)['timestamp'] as int),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NavigationScreen(
            sensorController: sensors,
            navigationPipeline: pipeline,
          ),
        ),
      );
      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Waiting for live navigation'), findsOneWidget);
      expect(find.text('Waiting for navigation estimates'), findsOneWidget);
      expect(find.text('km/h'), findsNothing);
      expect(sensors.starts, 1);
      sensors.samples.add(sample(1000));
      await tester.pump();
      await tester.pump();
      final state = tester
          .widget<NavigationMap>(find.byType(NavigationMap))
          .state;
      expect(state.navigationOutput.latitude, 0.0001);
      expect(state.displayPosition.latitude, 0);
      await tester.tap(find.byKey(const ValueKey('stop_navigation_button')));
      await tester.pump();
      expect(pipeline.latest, isNull);
      expect(sensors.stops, 1);
      expect(find.text('START'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      pipeline.dispose();
      sensors.dispose();
      await sensors.samples.close();
    },
  );
}
