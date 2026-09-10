import 'dart:async';

import 'package:mobile/models/raw_sensor_reading.dart';
import 'package:mobile/services/sensor_platform_adapter.dart';

/// Service responsible for lifecycle-safe, foreground sensor and GNSS acquisition.
///
/// Collects:
/// - 3-axis accelerometer readings (including gravity)
/// - 3-axis gyroscope readings (angular velocity)
/// - 3-axis magnetometer readings (ambient magnetic field)
/// - Foreground GNSS position fixes
///
/// Decoupled from platform implementations via [SensorPlatformAdapter].
/// Emits raw, acquisition-layer models ([TimestampedVector3], [GnssReading])
/// over broadcast streams. Does NOT generate fused or aligned [SensorData]
/// snapshots in this stage.
class SensorCollectionService {
  final SensorPlatformAdapter _adapter;

  final StreamController<TimestampedVector3> _accelerometerController =
      StreamController<TimestampedVector3>.broadcast(sync: true);
  final StreamController<TimestampedVector3> _gyroscopeController =
      StreamController<TimestampedVector3>.broadcast(sync: true);
  final StreamController<TimestampedVector3> _magnetometerController =
      StreamController<TimestampedVector3>.broadcast(sync: true);
  final StreamController<GnssReading> _gnssController =
      StreamController<GnssReading>.broadcast(sync: true);
  final StreamController<GnssAccessStatus> _gnssStatusController =
      StreamController<GnssAccessStatus>.broadcast(sync: true);
  final StreamController<SensorCollectionError> _errorController =
      StreamController<SensorCollectionError>.broadcast(sync: true);

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _isRunning = false;
  bool _isDisposed = false;
  bool _isStarting = false;
  GnssAccessStatus _gnssStatus = GnssAccessStatus.unknown;

  /// Creates a [SensorCollectionService] with an optional injectable [adapter].
  SensorCollectionService({SensorPlatformAdapter? adapter})
    : _adapter = adapter ?? DefaultSensorPlatformAdapter();

  /// Whether sensor collection is currently active.
  bool get isRunning => _isRunning;

  /// Whether this service has been permanently disposed.
  bool get isDisposed => _isDisposed;

  /// Current GNSS access and authorization status.
  GnssAccessStatus get gnssStatus => _gnssStatus;

  /// Broadcast stream of raw accelerometer readings (m/s², includes gravity).
  Stream<TimestampedVector3> get accelerometerStream =>
      _accelerometerController.stream;

  /// Broadcast stream of raw gyroscope readings (rad/s).
  Stream<TimestampedVector3> get gyroscopeStream => _gyroscopeController.stream;

  /// Broadcast stream of raw magnetometer readings (µT).
  Stream<TimestampedVector3> get magnetometerStream =>
      _magnetometerController.stream;

  /// Broadcast stream of foreground GNSS position fixes.
  Stream<GnssReading> get gnssStream => _gnssController.stream;

  /// Broadcast stream of GNSS access status transitions.
  Stream<GnssAccessStatus> get gnssStatusStream => _gnssStatusController.stream;

  /// Broadcast stream of recoverable sensor and acquisition errors.
  Stream<SensorCollectionError> get errorStream => _errorController.stream;

  /// Starts foreground sensor acquisition.
  ///
  /// This method is idempotent: if collection is already running or in the
  /// process of starting, repeated invocations return immediately without
  /// duplicating subscriptions.
  ///
  /// If IMU subscription fails, any subscriptions created during the attempt
  /// are cleanly cancelled before rethrowing. If GNSS preflight fails, the
  /// error is surfaced via [errorStream] and [gnssStatus] transitions to
  /// [GnssAccessStatus.error], but IMU collection continues unhindered.
  Future<void> start() async {
    if (_isDisposed) {
      throw StateError('Cannot start a disposed SensorCollectionService.');
    }
    if (_isRunning || _isStarting) {
      return;
    }

    _isStarting = true;
    final startingSubscriptions = <StreamSubscription<dynamic>>[];

    try {
      // 1. Subscribe to IMU streams
      final accelSub = _adapter.accelerometerStream.listen(
        (reading) {
          if (_isRunning && !_isDisposed) {
            _accelerometerController.add(reading);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _emitError(SensorSource.accelerometer, error, stackTrace);
        },
        cancelOnError: false,
      );
      startingSubscriptions.add(accelSub);

      final gyroSub = _adapter.gyroscopeStream.listen(
        (reading) {
          if (_isRunning && !_isDisposed) {
            _gyroscopeController.add(reading);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _emitError(SensorSource.gyroscope, error, stackTrace);
        },
        cancelOnError: false,
      );
      startingSubscriptions.add(gyroSub);

      final magSub = _adapter.magnetometerStream.listen(
        (reading) {
          if (_isRunning && !_isDisposed) {
            _magnetometerController.add(reading);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _emitError(SensorSource.magnetometer, error, stackTrace);
        },
        cancelOnError: false,
      );
      startingSubscriptions.add(magSub);

      _subscriptions.addAll(startingSubscriptions);
      _isRunning = true;
    } catch (e, st) {
      // Clean up any subscriptions created during this failed attempt
      for (final sub in startingSubscriptions) {
        await sub.cancel();
      }
      _isStarting = false;
      _emitError(SensorSource.accelerometer, e, st);
      rethrow;
    } finally {
      _isStarting = false;
    }

    // 2. Perform GNSS preflight and collection (isolated from IMU lifecycle)
    await _startGnssCollection();
  }

  /// Evaluates location services and permissions, starting the GNSS stream
  /// only if authorized.
  Future<void> _startGnssCollection() async {
    if (!_isRunning || _isDisposed) return;

    _updateGnssStatus(GnssAccessStatus.checking);

    try {
      final servicesEnabled = await _adapter.isLocationServiceEnabled();
      if (!servicesEnabled) {
        _updateGnssStatus(GnssAccessStatus.servicesDisabled);
        return;
      }

      var permission = await _adapter.checkLocationPermission();
      if (permission == LocationPermission.denied) {
        permission = await _adapter.requestLocationPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        _updateGnssStatus(GnssAccessStatus.permissionDeniedForever);
        return;
      }

      if (permission == LocationPermission.denied) {
        _updateGnssStatus(GnssAccessStatus.permissionDenied);
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        _updateGnssStatus(GnssAccessStatus.ready);

        final gnssSub = _adapter.gnssStream.listen(
          (reading) {
            if (_isRunning && !_isDisposed) {
              _gnssController.add(reading);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _emitError(SensorSource.gnss, error, stackTrace);
            _updateGnssStatus(GnssAccessStatus.error);
          },
          cancelOnError: false,
        );

        _subscriptions.add(gnssSub);
      } else {
        _updateGnssStatus(GnssAccessStatus.permissionDenied);
      }
    } catch (e, st) {
      _emitError(SensorSource.gnss, e, st);
      _updateGnssStatus(GnssAccessStatus.error);
    }
  }

  /// Stops all active sensor subscriptions.
  ///
  /// This method is idempotent: if collection is not running, it returns
  /// immediately. Cancels every active subscription and resets GNSS status.
  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;

    final activeSubscriptions = List<StreamSubscription<dynamic>>.from(
      _subscriptions,
    );
    _subscriptions.clear();

    for (final sub in activeSubscriptions) {
      await sub.cancel();
    }

    _updateGnssStatus(GnssAccessStatus.unknown);
  }

  /// Permanently disposes this service, cancelling subscriptions and closing
  /// all broadcast stream controllers.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    await stop();

    await _accelerometerController.close();
    await _gyroscopeController.close();
    await _magnetometerController.close();
    await _gnssController.close();
    await _gnssStatusController.close();
    await _errorController.close();
  }

  /// Opens device app settings for user-initiated permission updates.
  Future<bool> openAppSettings() => _adapter.openAppSettings();

  void _updateGnssStatus(GnssAccessStatus status) {
    if (_isDisposed) return;
    _gnssStatus = status;
    if (!_gnssStatusController.isClosed) {
      _gnssStatusController.add(status);
    }
  }

  void _emitError(SensorSource source, Object error, StackTrace? stackTrace) {
    if (_isDisposed) return;
    if (!_errorController.isClosed) {
      _errorController.add(
        SensorCollectionError(
          source: source,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
