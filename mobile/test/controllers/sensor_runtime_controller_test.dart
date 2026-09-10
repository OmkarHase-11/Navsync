import 'dart:async';

import 'package:flutter/material.dart' hide NavigationMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/controllers/sensor_runtime_controller.dart';
import 'package:mobile/models/navigation_output.dart';
import 'package:mobile/models/navigation_state.dart';
import 'package:mobile/models/raw_sensor_reading.dart';
import 'package:mobile/models/sensor_data.dart';
import 'package:mobile/screens/navigation_screen.dart';
import 'package:mobile/services/sensor_collection_service.dart';
import 'package:mobile/services/sensor_data_assembler.dart';
import 'package:mobile/services/sensor_platform_adapter.dart';
import 'package:mobile/widgets/navigation_drawer.dart';

class FakeSensorRuntimeController extends ChangeNotifier
    implements SensorRuntimeController {
  SensorPipelineStatus _status = SensorPipelineStatus.idle;
  int _snapshotCount = 0;
  String? _errorMessage;
  bool _running = false;
  bool _paused = false;
  bool _disposed = false;
  bool openSettingsCalled = false;

  void setStatus(
    SensorPipelineStatus status, {
    int snapshotCount = 0,
    String? error,
  }) {
    _status = status;
    _snapshotCount = snapshotCount;
    _errorMessage = error;
    notifyListeners();
  }

  @override
  SensorPipelineStatus get pipelineStatus => _status;

  @override
  int get totalSnapshotCount => _snapshotCount;

  @override
  String? get lastErrorMessage => _errorMessage;

  @override
  bool get isRunning => _running;

  @override
  bool get isPaused => _paused;

  @override
  bool get isDisposed => _disposed;

  @override
  SensorData? get latestSnapshot => null;

  @override
  int? get lastSnapshotTimestamp => null;

  @override
  bool get isImuActive =>
      _status == SensorPipelineStatus.collecting ||
      _status == SensorPipelineStatus.collectingWithoutGnss;

  @override
  GnssAccessStatus get gnssAccessStatus =>
      _status == SensorPipelineStatus.collecting
      ? GnssAccessStatus.ready
      : GnssAccessStatus.unknown;

  @override
  Duration get uiThrottleInterval => Duration.zero;

  @override
  Stream<SensorData> get sensorDataStream => const Stream.empty();

  @override
  Future<void> start() async {
    _running = true;
    _paused = false;
    _status = SensorPipelineStatus.collecting;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _running = false;
    _paused = false;
    _status = SensorPipelineStatus.stopped;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _running = false;
    _paused = true;
    _status = SensorPipelineStatus.paused;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    if (_paused) {
      _running = true;
      _paused = false;
      _status = SensorPipelineStatus.collecting;
      notifyListeners();
    }
  }

  @override
  Future<bool> openAppSettings() async {
    openSettingsCalled = true;
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class MockPlatformAdapter implements SensorPlatformAdapter {
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

  bool openAppSettingsCalled = false;
  int checkPermissionCount = 0;
  int requestPermissionCount = 0;

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
  Future<LocationPermission> checkLocationPermission() async {
    checkPermissionCount++;
    return checkPermissionResult;
  }

  @override
  Future<LocationPermission> requestLocationPermission() async {
    requestPermissionCount++;
    return requestPermissionResult;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalled = true;
    return true;
  }

  void emitMockImu({
    int timestamp = 1700000000000,
    double ax = 0.1,
    double ay = 0.2,
    double az = 9.81,
    double gx = 0.01,
    double gy = 0.02,
    double gz = 0.03,
    double mx = 20.0,
    double my = -10.0,
    double mz = 40.0,
  }) {
    accelController.add(
      TimestampedVector3(timestamp: timestamp, x: ax, y: ay, z: az),
    );
    gyroController.add(
      TimestampedVector3(timestamp: timestamp, x: gx, y: gy, z: gz),
    );
    magController.add(
      TimestampedVector3(timestamp: timestamp, x: mx, y: my, z: mz),
    );
  }

  void emitMockGnss({
    int timestamp = 1700000000000,
    double lat = 18.5204,
    double lng = 73.8567,
    double accuracy = 3.0,
  }) {
    gnssController.add(
      GnssReading(
        timestamp: timestamp,
        latitude: lat,
        longitude: lng,
        accuracy: accuracy,
      ),
    );
  }

  Future<void> dispose() async {
    await accelController.close();
    await gyroController.close();
    await magController.close();
    await gnssController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlatformAdapter adapter;
  late SensorCollectionService collectionService;
  late SensorDataAssembler assembler;
  late SensorRuntimeController controller;

  setUp(() {
    adapter = MockPlatformAdapter();
    collectionService = SensorCollectionService(adapter: adapter);
    assembler = SensorDataAssembler(
      collectionService: collectionService,
      autoManageService: false,
    );
    controller = SensorRuntimeController(
      collectionService: collectionService,
      assembler: assembler,
      uiThrottleInterval: Duration.zero,
    );
  });

  tearDown(() {
    if (!controller.isDisposed) {
      controller.dispose();
    }
  });

  group('SensorRuntimeController Lifecycle & State Transitions', () {
    test('Initial state is idle with zero snapshots and unactive IMU', () {
      expect(controller.pipelineStatus, SensorPipelineStatus.idle);
      expect(controller.totalSnapshotCount, 0);
      expect(controller.latestSnapshot, isNull);
      expect(controller.lastSnapshotTimestamp, isNull);
      expect(controller.isImuActive, isFalse);
      expect(controller.isRunning, isFalse);
      expect(controller.isPaused, isFalse);
      expect(controller.isDisposed, isFalse);
      expect(controller.lastErrorMessage, isNull);
    });

    test(
      'Explicit start transitions to starting and runs underlying services',
      () async {
        final startFuture = controller.start();
        expect(controller.isRunning, isTrue);
        expect(controller.isPaused, isFalse);
        await startFuture;
        expect(collectionService.isRunning, isTrue);
        expect(assembler.isRunning, isTrue);
      },
    );

    test('Successful IMU + GNSS collection triggers collecting status and valid snapshots', () async {
      await controller.start();

      adapter.emitMockGnss();
      adapter.emitMockImu();
      await pumpEventQueue();

      expect(controller.pipelineStatus, SensorPipelineStatus.collecting);
      expect(controller.isImuActive, isTrue);
      expect(controller.totalSnapshotCount, 1);
      expect(controller.latestSnapshot, isNotNull);
      expect(controller.latestSnapshot!.gnssAvailable, isTrue);
      expect(controller.latestSnapshot!.accelerometerZ, 9.81);
      expect(controller.lastSnapshotTimestamp, 1700000000000);
    });

    test('IMU-only collection triggers collectingWithoutGnss status', () async {
      await controller.start();

      adapter.emitMockImu();
      await pumpEventQueue();

      expect(
        controller.pipelineStatus,
        SensorPipelineStatus.collectingWithoutGnss,
      );
      expect(controller.isImuActive, isTrue);
      expect(controller.totalSnapshotCount, 1);
      expect(controller.latestSnapshot!.gnssAvailable, isFalse);
    });

    test(
      'Snapshot count increments and timestamp updates with multiple emissions',
      () async {
        await controller.start();

        for (int i = 1; i <= 5; i++) {
          adapter.emitMockImu(timestamp: 1700000000000 + i * 50);
          await pumpEventQueue();
          expect(controller.totalSnapshotCount, i);
          expect(controller.lastSnapshotTimestamp, 1700000000000 + i * 50);
        }
      },
    );

    test(
      'UI-facing update throttling throttles notifyListeners calls',
      () async {
        final throttledController = SensorRuntimeController(
          collectionService: collectionService,
          assembler: assembler,
          uiThrottleInterval: const Duration(milliseconds: 200),
        );

        int notifyCount = 0;
        throttledController.addListener(() => notifyCount++);

        await throttledController.start();
        notifyCount = 0;

        for (int i = 0; i < 5; i++) {
          adapter.emitMockImu(timestamp: 1700000000000 + i * 10);
        }
        await pumpEventQueue();

        expect(notifyCount, lessThanOrEqualTo(2));
        throttledController.dispose();
      },
    );

    test('Permission denied transitions to permissionDenied status', () async {
      adapter.checkPermissionResult = LocationPermission.denied;
      adapter.requestPermissionResult = LocationPermission.denied;

      await controller.start();
      await pumpEventQueue();

      expect(controller.pipelineStatus, SensorPipelineStatus.permissionDenied);
      adapter.emitMockImu();
      await pumpEventQueue();
      expect(controller.isImuActive, isTrue);
    });

    test('Permission denied forever transitions to permissionDeniedForever and allows openAppSettings', () async {
      adapter.checkPermissionResult = LocationPermission.deniedForever;

      await controller.start();
      await pumpEventQueue();

      expect(
        controller.pipelineStatus,
        SensorPipelineStatus.permissionDeniedForever,
      );

      expect(adapter.openAppSettingsCalled, isFalse);
      final opened = await controller.openAppSettings();
      expect(opened, isTrue);
      expect(adapter.openAppSettingsCalled, isTrue);
    });

    test(
      'Location services disabled transitions to locationServicesDisabled',
      () async {
        adapter.locationServicesEnabled = false;

        await controller.start();
        await pumpEventQueue();

        expect(
          controller.pipelineStatus,
          SensorPipelineStatus.locationServicesDisabled,
        );
      },
    );

    test('Recoverable GNSS error retains IMU collection without throwing unhandled', () async {
      await controller.start();

      adapter.emitMockImu();
      await pumpEventQueue();

      adapter.gnssController.addError(Exception('Temporary GPS lock failure'));
      await pumpEventQueue();

      expect(
        controller.lastErrorMessage,
        contains('Temporary GPS lock failure'),
      );
      expect(
        controller.pipelineStatus,
        SensorPipelineStatus.collectingWithoutGnss,
      );
    });

    test(
      'Stop cancels pipeline, resets running flags, and is idempotent',
      () async {
        await controller.start();
        adapter.emitMockImu();
        await pumpEventQueue();

        await controller.stop();
        expect(controller.isRunning, isFalse);
        expect(controller.isPaused, isFalse);
        expect(controller.isImuActive, isFalse);
        expect(controller.pipelineStatus, SensorPipelineStatus.stopped);

        final countBefore = controller.totalSnapshotCount;
        adapter.emitMockImu();
        await pumpEventQueue();
        expect(controller.totalSnapshotCount, countBefore);

        await controller.stop();
        expect(controller.pipelineStatus, SensorPipelineStatus.stopped);
      },
    );

    test('Repeated start/stop cycles do not duplicate subscriptions', () async {
      await controller.start();
      await controller.stop();
      await controller.start();
      await controller.stop();
      await controller.start();

      adapter.emitMockImu();
      await pumpEventQueue();

      expect(controller.totalSnapshotCount, 1);
    });

    test('Pause transitions to paused and resume restarts pipeline', () async {
      await controller.start();
      adapter.emitMockImu();
      await pumpEventQueue();

      await controller.pause();
      expect(controller.isPaused, isTrue);
      expect(controller.isRunning, isFalse);
      expect(controller.pipelineStatus, SensorPipelineStatus.paused);

      await controller.resume();
      expect(controller.isPaused, isFalse);
      expect(controller.isRunning, isTrue);

      adapter.emitMockImu(timestamp: 1700000000050);
      await pumpEventQueue();
      expect(controller.totalSnapshotCount, 2);
    });

    test('Resume does nothing if pipeline was not paused', () async {
      expect(controller.isPaused, isFalse);
      await controller.resume();
      expect(controller.isRunning, isFalse);
    });

    test('Disposal occurs safely and prevents future start', () async {
      controller.dispose();
      expect(controller.isDisposed, isTrue);

      expect(() => controller.start(), throwsStateError);

      controller.dispose();
      expect(controller.isDisposed, isTrue);
    });
  });

  group('Decoupling: Real SensorData Does Not Alter NavigationOutput', () {
    test('Simulated NavigationState navigation output remains independent of real sensors', () async {
      final navState = NavigationState();
      expect(navState.navigationOutput.speedKmh, 0.0);
      expect(navState.navigationOutput.gnssStatus, GnssStatus.available);

      await controller.start();
      adapter.emitMockGnss(lat: 28.6139, lng: 77.2090);
      adapter.emitMockImu();
      await pumpEventQueue();

      expect(controller.latestSnapshot, isNotNull);
      expect(controller.latestSnapshot!.latitude, 28.6139);
      expect(controller.latestSnapshot!.longitude, 77.2090);

      expect(navState.navigationOutput.speedKmh, 0.0);
      expect(navState.navigationOutput.latitude, isNot(equals(28.6139)));
      expect(navState.navigationOutput.longitude, isNot(equals(77.2090)));
      expect(navState.navigationOutput.gnssStatus, GnssStatus.available);
    });
  });

  group('Drawer Sensor Readiness UI States & Narrow Width Layout', () {
    late FakeSensorRuntimeController fakeController;

    setUp(() {
      fakeController = FakeSensorRuntimeController();
    });

    tearDown(() {
      fakeController.dispose();
    });

    Widget buildDrawerWithStatus({double width = 304.0}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: NavSyncDrawer(
              navigationOutput: const NavigationOutput(
                timestamp: 1700000000000,
                latitude: 18.5204,
                longitude: 73.8567,
                speedMps: 12.5,
                heading: 90.0,
                navigationMode: NavigationMode.gnssIns,
                gnssStatus: GnssStatus.available,
              ),
              sensorController: fakeController,
            ),
          ),
        ),
      );
    }

    testWidgets('Renders "Sensors off" when idle or stopped', (tester) async {
      fakeController.setStatus(SensorPipelineStatus.idle);
      await tester.pumpWidget(buildDrawerWithStatus());
      expect(find.text('Sensors off'), findsOneWidget);
      expect(find.text('Foreground collection stopped'), findsOneWidget);
      expect(find.byIcon(Icons.sensors_off_rounded), findsWidgets);
    });

    testWidgets('Renders "Starting sensors…" when starting', (tester) async {
      fakeController.setStatus(SensorPipelineStatus.starting);
      await tester.pumpWidget(buildDrawerWithStatus());
      expect(find.text('Starting sensors…'), findsOneWidget);
      expect(find.text('Awaiting hardware data'), findsOneWidget);
    });

    testWidgets('Renders "IMU + GNSS active" with snapshot count', (
      tester,
    ) async {
      fakeController.setStatus(
        SensorPipelineStatus.collecting,
        snapshotCount: 42,
      );
      await tester.pumpWidget(buildDrawerWithStatus());
      expect(find.text('IMU + GNSS active'), findsOneWidget);
      expect(find.text('42 snapshots • 20 Hz'), findsOneWidget);
    });

    testWidgets(
      'Renders "IMU active · Waiting for GNSS" when GNSS fix is pending',
      (tester) async {
        fakeController.setStatus(
          SensorPipelineStatus.collectingWithoutGnss,
          snapshotCount: 15,
        );
        await tester.pumpWidget(buildDrawerWithStatus());
        expect(find.text('IMU active · Waiting for GNSS'), findsOneWidget);
        expect(find.text('15 snapshots • IMU only'), findsOneWidget);
      },
    );

    testWidgets('Renders "Location permission denied" state', (tester) async {
      fakeController.setStatus(SensorPipelineStatus.permissionDenied);
      await tester.pumpWidget(buildDrawerWithStatus());
      expect(find.text('Location permission denied'), findsOneWidget);
      expect(find.text('IMU remains active for IDR'), findsOneWidget);
    });

    testWidgets(
      'Renders "Enable Location in Settings" and taps Open Settings',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeController.setStatus(SensorPipelineStatus.permissionDeniedForever);
        await tester.pumpWidget(buildDrawerWithStatus());
        expect(find.text('Enable Location in Settings'), findsOneWidget);
        expect(find.text('Open Settings'), findsOneWidget);

        await tester.tap(find.text('Open Settings'));
        await tester.pump();
        expect(fakeController.openSettingsCalled, isTrue);
      },
    );

    testWidgets('Renders "Location Services disabled" state', (tester) async {
      fakeController.setStatus(SensorPipelineStatus.locationServicesDisabled);
      await tester.pumpWidget(buildDrawerWithStatus());
      expect(find.text('Location Services disabled'), findsOneWidget);
      expect(find.text('Enable device GPS for fixes'), findsOneWidget);
    });

    testWidgets('Renders "Sensors paused" state', (tester) async {
      fakeController.setStatus(SensorPipelineStatus.paused);
      await tester.pumpWidget(buildDrawerWithStatus());
      expect(find.text('Sensors paused'), findsOneWidget);
      expect(find.text('App in background'), findsOneWidget);
    });

    testWidgets('Renders "Sensor unavailable" state', (tester) async {
      fakeController.setStatus(SensorPipelineStatus.sensorUnavailable);
      await tester.pumpWidget(buildDrawerWithStatus());
      expect(find.text('Sensor unavailable'), findsOneWidget);
      expect(find.text('Hardware sensor missing'), findsOneWidget);
    });

    testWidgets('Renders "Sensor error" state with error message', (
      tester,
    ) async {
      fakeController.setStatus(
        SensorPipelineStatus.error,
        error: 'Critical IMU failure',
      );
      await tester.pumpWidget(buildDrawerWithStatus());
      expect(find.text('Sensor error'), findsOneWidget);
      expect(find.text('Critical IMU failure'), findsOneWidget);
    });

    testWidgets('Renders without overflow on narrow 280px drawer', (
      tester,
    ) async {
      fakeController.setStatus(
        SensorPipelineStatus.collecting,
        snapshotCount: 9999,
      );
      await tester.pumpWidget(buildDrawerWithStatus(width: 280.0));
      expect(tester.takeException(), isNull);
    });
  });

  group('NavigationScreen Integration with Injected Controller', () {
    late FakeSensorRuntimeController fakeController;

    setUp(() {
      fakeController = FakeSensorRuntimeController();
    });

    tearDown(() {
      fakeController.dispose();
    });

    testWidgets(
      'Starts sensor runtime on Start Navigation and stops on Stop Navigation',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: NavigationScreen(sensorController: fakeController)),
        );
        await tester.pump(const Duration(milliseconds: 200));

        expect(fakeController.isRunning, isFalse);

        await tester.tap(find.text('START'));
        await tester.pump(const Duration(milliseconds: 100));

        expect(fakeController.isRunning, isTrue);

        await tester.tap(find.byKey(const ValueKey('stop_navigation_button')));
        await tester.pump(const Duration(milliseconds: 100));

        expect(fakeController.isRunning, isFalse);
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets('No duplicate transition notifications for same status', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: NavigationScreen(sensorController: fakeController)),
      );
      await tester.pump(const Duration(milliseconds: 200));

      fakeController.setStatus(SensorPipelineStatus.locationServicesDisabled);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Location Services disabled'), findsOneWidget);

      fakeController.setStatus(SensorPipelineStatus.locationServicesDisabled);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Location Services disabled'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
    });
  });
}
