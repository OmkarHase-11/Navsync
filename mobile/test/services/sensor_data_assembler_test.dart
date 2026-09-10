import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/raw_sensor_reading.dart';
import 'package:mobile/models/sensor_data.dart';
import 'package:mobile/services/sensor_collection_service.dart';
import 'package:mobile/services/sensor_data_assembler.dart';
import 'package:mobile/services/sensor_platform_adapter.dart';

/// Controllable adapter for isolated, deterministic testing.
class TestPlatformAdapter implements SensorPlatformAdapter {
  final StreamController<TimestampedVector3> accelController =
      StreamController<TimestampedVector3>.broadcast(sync: true);
  final StreamController<TimestampedVector3> gyroController =
      StreamController<TimestampedVector3>.broadcast(sync: true);
  final StreamController<TimestampedVector3> magController =
      StreamController<TimestampedVector3>.broadcast(sync: true);
  final StreamController<GnssReading> gnssController =
      StreamController<GnssReading>.broadcast(sync: true);

  bool locationServicesEnabled = true;
  LocationPermission checkPermissionResult = LocationPermission.whileInUse;
  LocationPermission requestPermissionResult = LocationPermission.whileInUse;

  @override
  Stream<TimestampedVector3> get accelerometerStream => accelController.stream;

  @override
  Stream<TimestampedVector3> get gyroscopeStream => gyroController.stream;

  @override
  Stream<TimestampedVector3> get magnetometerStream => magController.stream;

  @override
  Stream<GnssReading> get gnssStream => gnssController.stream;

  @override
  Future<bool> isLocationServiceEnabled() async => locationServicesEnabled;

  @override
  Future<LocationPermission> checkLocationPermission() async =>
      checkPermissionResult;

  @override
  Future<LocationPermission> requestLocationPermission() async =>
      requestPermissionResult;

  Future<void> dispose() async {
    await accelController.close();
    await gyroController.close();
    await magController.close();
    await gnssController.close();
  }
}

void main() {
  late TestPlatformAdapter adapter;
  late SensorCollectionService collectionService;
  late SensorDataAssembler assembler;

  setUp(() async {
    adapter = TestPlatformAdapter();
    collectionService = SensorCollectionService(adapter: adapter);
    await collectionService.start();

    assembler = SensorDataAssembler(
      collectionService: collectionService,
      maxImuSkew: const Duration(milliseconds: 250),
      minOutputInterval: const Duration(milliseconds: 50),
      maxGnssAge: const Duration(milliseconds: 3000),
      maxGnssAccuracy: 30.0,
    );
  });

  tearDown(() async {
    await assembler.dispose();
    await collectionService.dispose();
    await adapter.dispose();
  });

  // ─────────────────────────────────────────────
  // §1 — IMU Startup & Alignment Gating
  // ─────────────────────────────────────────────
  group('IMU startup gating', () {
    test('no output before any readings', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      expect(emitted, isEmpty);
      expect(assembler.status, AssemblerStatus.waitingForAccelerometer);
    });

    test('no output with only accelerometer', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0.1, y: 0.2, z: 9.8),
      );

      expect(emitted, isEmpty);
      expect(assembler.status, AssemblerStatus.waitingForGyroscope);
    });

    test('no output with only accelerometer and gyroscope', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0.1, y: 0.2, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1005, x: 0.01, y: 0.02, z: 0.03),
      );

      expect(emitted, isEmpty);
      expect(assembler.status, AssemblerStatus.waitingForMagnetometer);
    });

    test('first output after all three IMU readings exist', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0.1, y: 0.2, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1005, x: 0.01, y: 0.02, z: 0.03),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1010, x: 20.0, y: -5.0, z: -38.0),
      );

      expect(emitted, hasLength(1));
      expect(assembler.status, AssemblerStatus.emitting);
      expect(assembler.emittedCount, 1);
    });
  });

  // ─────────────────────────────────────────────
  // §2 — Contract Mapping & Value Integrity
  // ─────────────────────────────────────────────
  group('Contract mapping and value integrity', () {
    test('exact axis mapping and gravity preservation', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0.12, y: 0.35, z: 9.78),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1005, x: 0.002, y: -0.003, z: 0.015),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1010, x: 21.4, y: -5.8, z: -38.2),
      );

      expect(emitted, hasLength(1));
      final snapshot = emitted.first;

      // Accelerometer mapping (including gravity)
      expect(snapshot.accelerometerX, 0.12);
      expect(snapshot.accelerometerY, 0.35);
      expect(snapshot.accelerometerZ, 9.78);

      // Gyroscope mapping
      expect(snapshot.gyroscopeX, 0.002);
      expect(snapshot.gyroscopeY, -0.003);
      expect(snapshot.gyroscopeZ, 0.015);

      // Magnetometer mapping
      expect(snapshot.magnetometerX, 21.4);
      expect(snapshot.magnetometerY, -5.8);
      expect(snapshot.magnetometerZ, -38.2);

      // Serializes cleanly through canonical JSON
      final json = snapshot.toJson();
      expect(json['accelerometer_x'], 0.12);
      expect(json['gyroscope_y'], -0.003);
      expect(json['magnetometer_z'], -38.2);
    });

    test('snapshot timestamp uses latest represented measurement', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1015, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1010, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      // Max(1000, 1015, 1010) is 1015
      expect(emitted.first.timestamp, 1015);
    });
  });

  // ─────────────────────────────────────────────
  // §3 — Monotonicity, Rate Limiting & Skew
  // ─────────────────────────────────────────────
  group('Timing, rate limiting and skew', () {
    test(
      'timestamps strictly increase and duplicate timestamps are rejected',
      () async {
        final emitted = <SensorData>[];
        assembler.sensorDataStream.listen(emitted.add);

        await assembler.start();

        adapter.accelController.add(
          TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 9.8),
        );
        adapter.gyroController.add(
          TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
        );
        adapter.magController.add(
          TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
        );
        expect(emitted, hasLength(1));

        // Same timestamp on all 3 should not emit again
        adapter.accelController.add(
          TimestampedVector3(timestamp: 1000, x: 1, y: 1, z: 9.8),
        );
        expect(emitted, hasLength(1));
      },
    );

    test(
      'output is limited by the configured minimum output interval (50 ms)',
      () async {
        final emitted = <SensorData>[];
        assembler.sensorDataStream.listen(emitted.add);

        await assembler.start();

        // First snapshot at 1000
        adapter.accelController.add(
          TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 9.8),
        );
        adapter.gyroController.add(
          TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
        );
        adapter.magController.add(
          TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
        );
        expect(emitted, hasLength(1));

        // Arrives 20ms later (at 1020) -> should be rate-limited (< 50ms)
        adapter.accelController.add(
          TimestampedVector3(timestamp: 1020, x: 0.1, y: 0, z: 9.8),
        );
        adapter.gyroController.add(
          TimestampedVector3(timestamp: 1020, x: 0.01, y: 0, z: 0),
        );
        adapter.magController.add(
          TimestampedVector3(timestamp: 1020, x: 21, y: 0, z: 0),
        );
        expect(emitted, hasLength(1));
        expect(assembler.droppedRateLimitCount, greaterThan(0));

        // Arrives at 1050 (>= 1000 + 50ms) -> emits second snapshot!
        adapter.accelController.add(
          TimestampedVector3(timestamp: 1050, x: 0.2, y: 0, z: 9.8),
        );
        adapter.gyroController.add(
          TimestampedVector3(timestamp: 1050, x: 0.02, y: 0, z: 0),
        );
        adapter.magController.add(
          TimestampedVector3(timestamp: 1050, x: 22, y: 0, z: 0),
        );
        expect(emitted, hasLength(2));
        expect(emitted[1].timestamp, 1050);
      },
    );

    test('out-of-order readings are ignored', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1100, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1100, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1100, x: 0, y: 0, z: 0),
      );
      expect(emitted, hasLength(1));

      // Send older accelerometer reading (timestamp 1050 < 1100)
      adapter.accelController.add(
        TimestampedVector3(timestamp: 1050, x: 99, y: 99, z: 99),
      );
      expect(assembler.droppedOutOfOrderCount, 1);
    });

    test('stale IMU combination exceeding skew is not emitted', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      // Accel at 1000, gyro at 1010, mag at 1300 -> skew is 300ms (> 250ms max skew)
      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1010, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1300, x: 0, y: 0, z: 0),
      );

      expect(emitted, isEmpty);
      expect(assembler.status, AssemblerStatus.waitingForAlignedImu);
      expect(assembler.droppedSkewCount, 1);

      // Now bring accel and gyro up to 1300 -> skew becomes 0ms <= 250ms
      adapter.accelController.add(
        TimestampedVector3(timestamp: 1300, x: 0.1, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1300, x: 0.01, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      expect(emitted.first.timestamp, 1300);
    });

    test('respects configurable IMU skew', () async {
      final customAssembler = SensorDataAssembler(
        collectionService: collectionService,
        maxImuSkew: const Duration(milliseconds: 100),
      );
      final emitted = <SensorData>[];
      customAssembler.sensorDataStream.listen(emitted.add);

      await customAssembler.start();

      // Skew is 150ms: rejected by 100ms tolerance
      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1150, x: 0, y: 0, z: 0),
      );

      expect(emitted, isEmpty);
      expect(customAssembler.droppedSkewCount, 1);

      await customAssembler.dispose();
    });
  });

  // ─────────────────────────────────────────────
  // §4 — GNSS Usability Policy
  // ─────────────────────────────────────────────
  group('GNSS usability policy', () {
    test('GNSS ready + fresh + accurate produces available=true', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      // Fix at 1000, accuracy 5.0m
      adapter.gnssController.add(
        GnssReading(
          timestamp: 1000,
          latitude: 18.5204,
          longitude: 73.8567,
          accuracy: 5.0,
        ),
      );

      // Snapshot at 1050 -> fix age is 50ms (<= 3000ms), accuracy 5m (<= 30m)
      adapter.accelController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      final s = emitted.first;
      expect(s.gnssAvailable, isTrue);
      expect(s.latitude, 18.5204);
      expect(s.longitude, 73.8567);
      expect(s.gnssAccuracy, 5.0);
    });

    test('GNSS fix at exactly 3000 ms remains usable', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      // Fix at 1000
      adapter.gnssController.add(
        GnssReading(
          timestamp: 1000,
          latitude: 18.5204,
          longitude: 73.8567,
          accuracy: 10.0,
        ),
      );

      // Snapshot at exactly 4000 -> age = 3000ms
      adapter.accelController.add(
        TimestampedVector3(timestamp: 4000, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 4000, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 4000, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      expect(emitted.first.gnssAvailable, isTrue);
      expect(emitted.first.latitude, 18.5204);
    });

    test('GNSS fix older than 3000 ms becomes unavailable', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      // Fix at 1000
      adapter.gnssController.add(
        GnssReading(
          timestamp: 1000,
          latitude: 18.5204,
          longitude: 73.8567,
          accuracy: 10.0,
        ),
      );

      // Snapshot at 4001 -> age = 3001ms (> 3000ms)
      adapter.accelController.add(
        TimestampedVector3(timestamp: 4001, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 4001, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 4001, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      final s = emitted.first;
      expect(s.gnssAvailable, isFalse);
      expect(s.latitude, isNull);
      expect(s.longitude, isNull);
      expect(s.gnssAccuracy, isNull);
    });

    test('accuracy exactly 30.0 m remains usable', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      adapter.gnssController.add(
        GnssReading(
          timestamp: 1000,
          latitude: 18.5204,
          longitude: 73.8567,
          accuracy: 30.0,
        ),
      );

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      expect(emitted.first.gnssAvailable, isTrue);
      expect(emitted.first.gnssAccuracy, 30.0);
    });

    test('accuracy above 30.0 m becomes unavailable', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      adapter.gnssController.add(
        GnssReading(
          timestamp: 1000,
          latitude: 18.5204,
          longitude: 73.8567,
          accuracy: 30.1,
        ),
      );

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      expect(emitted.first.gnssAvailable, isFalse);
      expect(emitted.first.latitude, isNull);
    });

    test('future GNSS fix is unavailable', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      // Fix timestamp (2000) is in future relative to candidate timestamp (1050)
      adapter.gnssController.add(
        GnssReading(
          timestamp: 2000,
          latitude: 18.5204,
          longitude: 73.8567,
          accuracy: 5.0,
        ),
      );

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      expect(emitted.first.gnssAvailable, isFalse);
      expect(emitted.first.latitude, isNull);
    });

    test('no fix produces null GNSS fields', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      expect(emitted.first.gnssAvailable, isFalse);
      expect(emitted.first.latitude, isNull);
      expect(emitted.first.longitude, isNull);
      expect(emitted.first.gnssAccuracy, isNull);
    });

    test('valid GNSS recovery restores GNSS fields', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();

      // Snapshot 1: no GNSS fix yet
      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
      );
      expect(emitted.last.gnssAvailable, isFalse);

      // GNSS fix arrives at 1050
      adapter.gnssController.add(
        GnssReading(
          timestamp: 1050,
          latitude: 18.5204,
          longitude: 73.8567,
          accuracy: 8.0,
        ),
      );

      // Snapshot 2: GNSS is recovered!
      adapter.accelController.add(
        TimestampedVector3(timestamp: 1080, x: 0.1, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1080, x: 0.01, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1080, x: 21, y: 0, z: 0),
      );
      expect(emitted.last.gnssAvailable, isTrue);
      expect(emitted.last.latitude, 18.5204);
    });
  });

  // ─────────────────────────────────────────────
  // §5 — Lifecycle, Ownership & Serialization
  // ─────────────────────────────────────────────
  group('Lifecycle, ownership and serialization', () {
    test('repeated start does not duplicate output', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();
      await assembler.start();
      await assembler.start();

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
    });

    test('stop prevents output and restart works', () async {
      final emitted = <SensorData>[];
      assembler.sensorDataStream.listen(emitted.add);

      await assembler.start();
      await assembler.stop();

      expect(assembler.isRunning, isFalse);
      expect(assembler.status, AssemblerStatus.stopped);

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1000, x: 0, y: 0, z: 0),
      );

      expect(emitted, isEmpty);

      // Restart works cleanly
      await assembler.start();
      expect(assembler.isRunning, isTrue);

      adapter.accelController.add(
        TimestampedVector3(timestamp: 2000, x: 0.1, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 2000, x: 0.01, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 2000, x: 20, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      expect(emitted.first.timestamp, 2000);
    });

    test('dispose permanently prevents output and throws on restart', () async {
      await assembler.start();
      await assembler.dispose();

      expect(assembler.isDisposed, isTrue);
      expect(assembler.status, AssemblerStatus.disposed);

      expect(() => assembler.start(), throwsA(isA<StateError>()));
    });

    test(
      'externally supplied collection service is not unexpectedly disposed',
      () async {
        expect(collectionService.isDisposed, isFalse);

        await assembler.dispose();

        // Externally supplied service must remain intact
        expect(collectionService.isDisposed, isFalse);
        expect(collectionService.isRunning, isTrue);
      },
    );

    test(
      'every output successfully serializes through SensorData.toJson()',
      () async {
        final emitted = <SensorData>[];
        assembler.sensorDataStream.listen(emitted.add);

        await assembler.start();

        adapter.gnssController.add(
          GnssReading(
            timestamp: 1000,
            latitude: 18.5204,
            longitude: 73.8567,
            accuracy: 5.0,
          ),
        );

        adapter.accelController.add(
          TimestampedVector3(timestamp: 1050, x: 0.12, y: 0.35, z: 9.78),
        );
        adapter.gyroController.add(
          TimestampedVector3(timestamp: 1050, x: 0.002, y: -0.003, z: 0.015),
        );
        adapter.magController.add(
          TimestampedVector3(timestamp: 1050, x: 21.4, y: -5.8, z: -38.2),
        );

        expect(emitted, hasLength(1));
        final json = emitted.first.toJson();

        // Verify all 14 keys exist and match contract types
        expect(json.keys.length, 14);
        expect(json['timestamp'], 1050);
        expect(json['accelerometer_x'], 0.12);
        expect(json['accelerometer_y'], 0.35);
        expect(json['accelerometer_z'], 9.78);
        expect(json['gyroscope_x'], 0.002);
        expect(json['gyroscope_y'], -0.003);
        expect(json['gyroscope_z'], 0.015);
        expect(json['magnetometer_x'], 21.4);
        expect(json['magnetometer_y'], -5.8);
        expect(json['magnetometer_z'], -38.2);
        expect(json['latitude'], 18.5204);
        expect(json['longitude'], 73.8567);
        expect(json['gnss_accuracy'], 5.0);
        expect(json['gnss_available'], true);

        // Verify round-trip back into SensorData
        final deserialized = SensorData.fromJson(json);
        expect(deserialized, emitted.first);
      },
    );

    test('permission denied produces null GNSS fields', () async {
      // Discard default collectionService and start with permission denied
      await assembler.dispose();
      await collectionService.dispose();

      adapter.checkPermissionResult = LocationPermission.denied;
      adapter.requestPermissionResult = LocationPermission.denied;
      final localService = SensorCollectionService(adapter: adapter);
      await localService.start();

      final localAssembler = SensorDataAssembler(
        collectionService: localService,
      );
      final emitted = <SensorData>[];
      localAssembler.sensorDataStream.listen(emitted.add);

      await localAssembler.start();

      // Even if a reading was pushed to gnssController
      adapter.gnssController.add(
        GnssReading(
          timestamp: 1000,
          latitude: 18.5204,
          longitude: 73.8567,
          accuracy: 5.0,
        ),
      );

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      expect(emitted.first.gnssAvailable, isFalse);
      expect(emitted.first.latitude, isNull);
      expect(emitted.first.longitude, isNull);

      await localAssembler.dispose();
      await localService.dispose();
    });

    test('services disabled produces null GNSS fields', () async {
      await assembler.dispose();
      await collectionService.dispose();

      adapter.locationServicesEnabled = false;
      final localService = SensorCollectionService(adapter: adapter);
      await localService.start();

      final localAssembler = SensorDataAssembler(
        collectionService: localService,
      );
      final emitted = <SensorData>[];
      localAssembler.sensorDataStream.listen(emitted.add);

      await localAssembler.start();

      adapter.accelController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 9.8),
      );
      adapter.gyroController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );
      adapter.magController.add(
        TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
      );

      expect(emitted, hasLength(1));
      expect(emitted.first.gnssAvailable, isFalse);
      expect(emitted.first.latitude, isNull);

      await localAssembler.dispose();
      await localService.dispose();
    });

    test(
      'stale cached coordinates are never emitted after age exceeds 3000ms',
      () async {
        final emitted = <SensorData>[];
        assembler.sensorDataStream.listen(emitted.add);

        await assembler.start();

        // Fresh fix at 1000
        adapter.gnssController.add(
          GnssReading(
            timestamp: 1000,
            latitude: 18.5204,
            longitude: 73.8567,
            accuracy: 5.0,
          ),
        );

        // Snapshot at 1050 (usable, available=true)
        adapter.accelController.add(
          TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 9.8),
        );
        adapter.gyroController.add(
          TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
        );
        adapter.magController.add(
          TimestampedVector3(timestamp: 1050, x: 0, y: 0, z: 0),
        );
        expect(emitted.last.gnssAvailable, isTrue);
        expect(emitted.last.latitude, 18.5204);

        // 4000ms later at 5050 (age = 4050ms > 3000ms, NO new fix)
        adapter.accelController.add(
          TimestampedVector3(timestamp: 5050, x: 0.1, y: 0, z: 9.8),
        );
        adapter.gyroController.add(
          TimestampedVector3(timestamp: 5050, x: 0.01, y: 0, z: 0),
        );
        adapter.magController.add(
          TimestampedVector3(timestamp: 5050, x: 10, y: 0, z: 0),
        );

        expect(emitted.last.gnssAvailable, isFalse);
        expect(emitted.last.latitude, isNull);
        expect(emitted.last.longitude, isNull);
        expect(emitted.last.gnssAccuracy, isNull);
      },
    );

    test(
      'autoManageService manages collection service start and stop',
      () async {
        final localService = SensorCollectionService(adapter: adapter);
        final localAssembler = SensorDataAssembler(
          collectionService: localService,
          autoManageService: true,
        );

        expect(localService.isRunning, isFalse);

        await localAssembler.start();
        expect(localService.isRunning, isTrue);

        await localAssembler.stop();
        expect(localService.isRunning, isFalse);

        await localAssembler.dispose();
        await localService.dispose();
      },
    );

    test(
      'ownsCollectionService disposes collection service on assembler dispose',
      () async {
        final localService = SensorCollectionService(adapter: adapter);
        final localAssembler = SensorDataAssembler(
          collectionService: localService,
          ownsCollectionService: true,
        );

        await localAssembler.start();
        expect(localService.isDisposed, isFalse);

        await localAssembler.dispose();
        expect(localService.isDisposed, isTrue);
      },
    );
  });
}
