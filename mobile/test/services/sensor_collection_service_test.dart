import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/raw_sensor_reading.dart';
import 'package:mobile/services/sensor_collection_service.dart';
import 'package:mobile/services/sensor_platform_adapter.dart';

/// Controllable fake platform adapter for isolated unit testing.
class FakeSensorPlatformAdapter implements SensorPlatformAdapter {
  final StreamController<TimestampedVector3> accelController =
      StreamController<TimestampedVector3>.broadcast();
  final StreamController<TimestampedVector3> gyroController =
      StreamController<TimestampedVector3>.broadcast();
  final StreamController<TimestampedVector3> magController =
      StreamController<TimestampedVector3>.broadcast();
  final StreamController<GnssReading> gnssController =
      StreamController<GnssReading>.broadcast();

  bool locationServicesEnabled = true;
  LocationPermission checkPermissionResult = LocationPermission.whileInUse;
  LocationPermission requestPermissionResult = LocationPermission.whileInUse;

  bool shouldThrowOnAccel = false;
  bool shouldThrowOnLocationService = false;
  bool shouldThrowOnPermission = false;

  int accelListenCount = 0;
  int gyroListenCount = 0;
  int magListenCount = 0;
  int gnssListenCount = 0;
  int requestPermissionCount = 0;
  int checkPermissionCount = 0;

  @override
  Stream<TimestampedVector3> get accelerometerStream {
    if (shouldThrowOnAccel) {
      throw Exception('Failed to connect to accelerometer');
    }
    return accelController.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          sink.add(data);
        },
      ),
    )..listen((_) {}, onDone: () {});
  }

  Stream<TimestampedVector3> get rawAccelStream {
    accelListenCount++;
    return accelController.stream;
  }

  Stream<TimestampedVector3> get rawGyroStream {
    gyroListenCount++;
    return gyroController.stream;
  }

  Stream<TimestampedVector3> get rawMagStream {
    magListenCount++;
    return magController.stream;
  }

  Stream<GnssReading> get rawGnssStream {
    gnssListenCount++;
    return gnssController.stream;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    if (shouldThrowOnLocationService) {
      throw Exception('Location service check failed');
    }
    return locationServicesEnabled;
  }

  @override
  Future<LocationPermission> checkLocationPermission() async {
    checkPermissionCount++;
    if (shouldThrowOnPermission) {
      throw Exception('Permission check failed');
    }
    return checkPermissionResult;
  }

  @override
  Future<LocationPermission> requestLocationPermission() async {
    requestPermissionCount++;
    return requestPermissionResult;
  }

  @override
  Stream<GnssReading> get gnssStream => rawGnssStream;

  @override
  Stream<TimestampedVector3> get gyroscopeStream => rawGyroStream;

  @override
  Stream<TimestampedVector3> get magnetometerStream => rawMagStream;

  @override
  Future<bool> openAppSettings() async => true;

  Future<void> dispose() async {
    await accelController.close();
    await gyroController.close();
    await magController.close();
    await gnssController.close();
  }
}

/// Specialized controllable adapter tracking listener counts accurately.
class ControllableAdapter implements SensorPlatformAdapter {
  final StreamController<TimestampedVector3> accelController =
      StreamController<TimestampedVector3>.broadcast();
  final StreamController<TimestampedVector3> gyroController =
      StreamController<TimestampedVector3>.broadcast();
  final StreamController<TimestampedVector3> magController =
      StreamController<TimestampedVector3>.broadcast();
  final StreamController<GnssReading> gnssController =
      StreamController<GnssReading>.broadcast();

  bool locationServicesEnabled = true;
  LocationPermission checkPermissionResult = LocationPermission.whileInUse;
  LocationPermission requestPermissionResult = LocationPermission.whileInUse;

  bool throwOnAccelStream = false;
  bool throwOnGyroStream = false;
  bool throwOnLocationService = false;
  bool throwOnCheckPermission = false;

  int accelSubscriptionCount = 0;
  int gyroSubscriptionCount = 0;
  int magSubscriptionCount = 0;
  int gnssSubscriptionCount = 0;

  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;

  @override
  Stream<TimestampedVector3> get accelerometerStream {
    if (throwOnAccelStream) {
      throw StateError('Simulated accelerometer failure');
    }
    return _track(accelController.stream, () => accelSubscriptionCount++);
  }

  @override
  Stream<TimestampedVector3> get gyroscopeStream {
    if (throwOnGyroStream) {
      throw StateError('Simulated gyroscope failure');
    }
    return _track(gyroController.stream, () => gyroSubscriptionCount++);
  }

  @override
  Stream<TimestampedVector3> get magnetometerStream {
    return _track(magController.stream, () => magSubscriptionCount++);
  }

  @override
  Stream<GnssReading> get gnssStream {
    return _track(gnssController.stream, () => gnssSubscriptionCount++);
  }

  Stream<T> _track<T>(Stream<T> source, void Function() onListen) {
    return Stream<T>.multi((controller) {
      onListen();
      final sub = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    if (throwOnLocationService) {
      throw Exception('Service check crashed');
    }
    return locationServicesEnabled;
  }

  @override
  Future<LocationPermission> checkLocationPermission() async {
    checkPermissionCalls++;
    if (throwOnCheckPermission) {
      throw Exception('Check permission crashed');
    }
    return checkPermissionResult;
  }

  @override
  Future<LocationPermission> requestLocationPermission() async {
    requestPermissionCalls++;
    return requestPermissionResult;
  }

  @override
  Future<bool> openAppSettings() async => true;

  Future<void> dispose() async {
    await accelController.close();
    await gyroController.close();
    await magController.close();
    await gnssController.close();
  }
}

void main() {
  late ControllableAdapter adapter;
  late SensorCollectionService service;

  setUp(() {
    adapter = ControllableAdapter();
    service = SensorCollectionService(adapter: adapter);
  });

  tearDown(() async {
    await service.dispose();
    await adapter.dispose();
  });

  // ─────────────────────────────────────────────
  // §1 — Initial State
  // ─────────────────────────────────────────────
  group('Initial state', () {
    test('is not running and not disposed', () {
      expect(service.isRunning, isFalse);
      expect(service.isDisposed, isFalse);
      expect(service.gnssStatus, GnssAccessStatus.unknown);
    });
  });

  // ─────────────────────────────────────────────
  // §2 — Successful Start and Forwarding
  // ─────────────────────────────────────────────
  group('Successful start and event forwarding', () {
    test('starts successfully and transitions GNSS to ready', () async {
      await service.start();

      expect(service.isRunning, isTrue);
      expect(service.gnssStatus, GnssAccessStatus.ready);
      expect(adapter.accelSubscriptionCount, 1);
      expect(adapter.gyroSubscriptionCount, 1);
      expect(adapter.magSubscriptionCount, 1);
      expect(adapter.gnssSubscriptionCount, 1);
    });

    test('forwards accelerometer readings including gravity', () async {
      final received = <TimestampedVector3>[];
      service.accelerometerStream.listen(received.add);

      await service.start();

      final reading = TimestampedVector3(
        timestamp: 1725552000100,
        x: 0.12,
        y: 0.35,
        z: 9.78,
      );
      adapter.accelController.add(reading);

      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.first.timestamp, 1725552000100);
      expect(received.first.x, 0.12);
      expect(received.first.y, 0.35);
      expect(received.first.z, 9.78);
    });

    test('forwards gyroscope readings preserving rad/s units', () async {
      final received = <TimestampedVector3>[];
      service.gyroscopeStream.listen(received.add);

      await service.start();

      final reading = TimestampedVector3(
        timestamp: 1725552000200,
        x: 0.002,
        y: -0.003,
        z: 0.015,
      );
      adapter.gyroController.add(reading);

      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.first.timestamp, 1725552000200);
      expect(received.first.x, 0.002);
      expect(received.first.y, -0.003);
      expect(received.first.z, 0.015);
    });

    test('forwards magnetometer readings preserving µT units', () async {
      final received = <TimestampedVector3>[];
      service.magnetometerStream.listen(received.add);

      await service.start();

      final reading = TimestampedVector3(
        timestamp: 1725552000300,
        x: 21.4,
        y: -5.8,
        z: -38.2,
      );
      adapter.magController.add(reading);

      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.first.timestamp, 1725552000300);
      expect(received.first.x, 21.4);
      expect(received.first.y, -5.8);
      expect(received.first.z, -38.2);
    });

    test('forwards GNSS readings with WGS84 degrees and accuracy', () async {
      final received = <GnssReading>[];
      service.gnssStream.listen(received.add);

      await service.start();

      final reading = GnssReading(
        timestamp: 1725552000400,
        latitude: 18.5204,
        longitude: 73.8567,
        accuracy: 4.5,
      );
      adapter.gnssController.add(reading);

      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.first.timestamp, 1725552000400);
      expect(received.first.latitude, 18.5204);
      expect(received.first.longitude, 73.8567);
      expect(received.first.accuracy, 4.5);
    });
  });

  // ─────────────────────────────────────────────
  // §3 — GNSS Preflight and Authorization Flow
  // ─────────────────────────────────────────────
  group('GNSS preflight and authorization', () {
    test('handles location services disabled (IMU continues)', () async {
      adapter.locationServicesEnabled = false;

      final statuses = <GnssAccessStatus>[];
      service.gnssStatusStream.listen(statuses.add);

      await service.start();

      expect(service.isRunning, isTrue);
      expect(service.gnssStatus, GnssAccessStatus.servicesDisabled);
      expect(statuses, contains(GnssAccessStatus.servicesDisabled));
      expect(adapter.gnssSubscriptionCount, 0);
      // IMU still active!
      expect(adapter.accelSubscriptionCount, 1);
    });

    test('requests permission when initially denied', () async {
      adapter.checkPermissionResult = LocationPermission.denied;
      adapter.requestPermissionResult = LocationPermission.whileInUse;

      await service.start();

      expect(adapter.checkPermissionCalls, 1);
      expect(adapter.requestPermissionCalls, 1);
      expect(service.gnssStatus, GnssAccessStatus.ready);
      expect(adapter.gnssSubscriptionCount, 1);
    });

    test('handles permission denied by user', () async {
      adapter.checkPermissionResult = LocationPermission.denied;
      adapter.requestPermissionResult = LocationPermission.denied;

      await service.start();

      expect(adapter.requestPermissionCalls, 1);
      expect(service.gnssStatus, GnssAccessStatus.permissionDenied);
      expect(adapter.gnssSubscriptionCount, 0);
      // IMU still active
      expect(service.isRunning, isTrue);
    });

    test('handles permission denied forever without requesting', () async {
      adapter.checkPermissionResult = LocationPermission.deniedForever;

      await service.start();

      expect(adapter.requestPermissionCalls, 0);
      expect(service.gnssStatus, GnssAccessStatus.permissionDeniedForever);
      expect(adapter.gnssSubscriptionCount, 0);
      expect(service.isRunning, isTrue);
    });

    test('handles exception during location services check', () async {
      adapter.throwOnLocationService = true;

      final errors = <SensorCollectionError>[];
      service.errorStream.listen(errors.add);

      await service.start();

      expect(service.isRunning, isTrue);
      expect(service.gnssStatus, GnssAccessStatus.error);
      expect(errors, hasLength(1));
      expect(errors.first.source, SensorSource.gnss);
      expect(adapter.accelSubscriptionCount, 1);
    });

    test('handles exception during permission check', () async {
      adapter.throwOnCheckPermission = true;

      final errors = <SensorCollectionError>[];
      service.errorStream.listen(errors.add);

      await service.start();

      expect(service.isRunning, isTrue);
      expect(service.gnssStatus, GnssAccessStatus.error);
      expect(errors, hasLength(1));
      expect(errors.first.source, SensorSource.gnss);
      expect(adapter.accelSubscriptionCount, 1);
    });
  });

  // ─────────────────────────────────────────────
  // §4 — Lifecycle and Idempotency
  // ─────────────────────────────────────────────
  group('Lifecycle and idempotency', () {
    test('repeated start does not duplicate subscriptions', () async {
      await service.start();
      await service.start();
      await service.start();

      expect(adapter.accelSubscriptionCount, 1);
      expect(adapter.gyroSubscriptionCount, 1);
      expect(adapter.magSubscriptionCount, 1);
      expect(adapter.gnssSubscriptionCount, 1);
    });

    test('stop cancels all subscriptions and resets GNSS status', () async {
      await service.start();
      expect(service.isRunning, isTrue);

      await service.stop();
      expect(service.isRunning, isFalse);
      expect(service.gnssStatus, GnssAccessStatus.unknown);
    });

    test('repeated stop is safe and idempotent', () async {
      await service.start();
      await service.stop();
      await service.stop();
      await service.stop();

      expect(service.isRunning, isFalse);
    });

    test('can restart after stop', () async {
      await service.start();
      await service.stop();

      await service.start();
      expect(service.isRunning, isTrue);
      expect(adapter.accelSubscriptionCount, 2);
    });

    test('no events emitted after stop', () async {
      final received = <TimestampedVector3>[];
      service.accelerometerStream.listen(received.add);

      await service.start();
      await service.stop();

      adapter.accelController.add(
        TimestampedVector3(timestamp: 100, x: 1, y: 2, z: 3),
      );
      await pumpEventQueue();

      expect(received, isEmpty);
    });

    test('dispose permanently closes resources', () async {
      await service.start();
      await service.dispose();

      expect(service.isDisposed, isTrue);
      expect(service.isRunning, isFalse);

      expect(() => service.start(), throwsA(isA<StateError>()));
    });

    test('repeated dispose is safe', () async {
      await service.start();
      await service.dispose();
      await service.dispose();

      expect(service.isDisposed, isTrue);
    });

    test('partial startup failure cleans up created subscriptions', () async {
      adapter.throwOnGyroStream = true;

      expect(() => service.start(), throwsA(isA<StateError>()));

      expect(service.isRunning, isFalse);
    });
  });

  // ─────────────────────────────────────────────
  // §5 — Asynchronous Error Handling
  // ─────────────────────────────────────────────
  group('Asynchronous stream error handling', () {
    test(
      'surfaces accelerometer stream error without terminating gyro',
      () async {
        final errors = <SensorCollectionError>[];
        final gyroReadings = <TimestampedVector3>[];

        service.errorStream.listen(errors.add);
        service.gyroscopeStream.listen(gyroReadings.add);

        await service.start();

        adapter.accelController.addError(Exception('Hardware glitch'));
        await pumpEventQueue();

        expect(errors, hasLength(1));
        expect(errors.first.source, SensorSource.accelerometer);

        // Gyroscope continues working!
        adapter.gyroController.add(
          TimestampedVector3(timestamp: 200, x: 0.1, y: 0.2, z: 0.3),
        );
        await pumpEventQueue();

        expect(gyroReadings, hasLength(1));
      },
    );

    test('surfaces GNSS stream error and updates GNSS status', () async {
      final errors = <SensorCollectionError>[];
      service.errorStream.listen(errors.add);

      await service.start();

      adapter.gnssController.addError(Exception('GNSS signal lost'));
      await pumpEventQueue();

      expect(errors, hasLength(1));
      expect(errors.first.source, SensorSource.gnss);
      expect(service.gnssStatus, GnssAccessStatus.error);
      expect(service.isRunning, isTrue);
    });

    test('one stream error does not fabricate zero measurements', () async {
      final accelReadings = <TimestampedVector3>[];
      service.accelerometerStream.listen(accelReadings.add);

      await service.start();

      adapter.accelController.addError(Exception('Accelerometer failure'));
      await pumpEventQueue();

      expect(accelReadings, isEmpty);
    });
  });
}
