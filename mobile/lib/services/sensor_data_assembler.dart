import 'dart:async';
import 'dart:math';

import 'package:mobile/models/raw_sensor_reading.dart';
import 'package:mobile/models/sensor_data.dart';
import 'package:mobile/services/sensor_collection_service.dart';

/// Status states for the [SensorDataAssembler].
enum AssemblerStatus {
  /// The assembler is stopped and not listening to sensor streams.
  stopped,

  /// Waiting for the first valid accelerometer reading.
  waitingForAccelerometer,

  /// Waiting for the first valid gyroscope reading.
  waitingForGyroscope,

  /// Waiting for the first valid magnetometer reading.
  waitingForMagnetometer,

  /// Readings exist but IMU skew exceeds the configured tolerance.
  waitingForAlignedImu,

  /// Candidate snapshot was skipped to respect the minimum output interval.
  waitingForRateLimit,

  /// Successfully aligned and actively emitting canonical [SensorData].
  emitting,

  /// The assembler has been permanently disposed.
  disposed,
}

/// Lifecycle-safe alignment service combining raw IMU and GNSS readings into
/// canonical [SensorData] snapshots.
///
/// Alignment rules:
/// 1. Requires at least one reading from accelerometer, gyroscope, and magnetometer.
/// 2. Snapshot timestamp is the latest measurement epoch among the three IMU readings.
/// 3. All three IMU readings must fall within [maxImuSkew] (default 250ms).
/// 4. Output rate is bounded by [minOutputInterval] (default 50ms / 20 Hz).
/// 5. Timestamps strictly increase between emitted snapshots.
/// 6. GNSS is usable only when access status is ready, fix age <= [maxGnssAge]
///    (default 3000ms), accuracy <= [maxGnssAccuracy] (default 30m), and fix is
///    not in the future relative to the snapshot timestamp.
/// 7. When GNSS is unavailable, [SensorData] coordinates and accuracy are null,
///    and gnssAvailable is false.
class SensorDataAssembler {
  /// Underlying sensor collection service.
  final SensorCollectionService collectionService;

  /// Maximum allowed skew among accelerometer, gyroscope, and magnetometer
  /// measurement timestamps.
  ///
  /// Defaults to 250ms, matching the upstream AI windowing limit.
  final Duration maxImuSkew;

  /// Minimum time interval between emitted [SensorData] snapshots.
  ///
  /// Defaults to 50ms (maximum 20 Hz output rate).
  final Duration minOutputInterval;

  /// Maximum acceptable age for a GNSS fix relative to snapshot epoch.
  ///
  /// Defaults to 3000ms, matching `navigation_engine/gnss/gnss_availability.py`.
  final Duration maxGnssAge;

  /// Maximum acceptable horizontal accuracy in meters.
  ///
  /// Defaults to 30.0m, matching `navigation_engine/gnss/gnss_availability.py`.
  final double maxGnssAccuracy;

  /// Whether starting/stopping the assembler also starts/stops the source
  /// [SensorCollectionService].
  ///
  /// Defaults to false.
  final bool autoManageService;

  /// Whether this assembler owns the [SensorCollectionService] and should
  /// dispose it when the assembler is disposed.
  ///
  /// Defaults to false to prevent unexpected disposal of externally supplied
  /// services.
  final bool ownsCollectionService;

  final StreamController<SensorData> _sensorDataController =
      StreamController<SensorData>.broadcast(sync: true);
  final StreamController<AssemblerStatus> _statusController =
      StreamController<AssemblerStatus>.broadcast(sync: true);

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  TimestampedVector3? _latestAccelerometer;
  TimestampedVector3? _latestGyroscope;
  TimestampedVector3? _latestMagnetometer;
  GnssReading? _latestGnssReading;
  GnssAccessStatus _latestGnssStatus = GnssAccessStatus.unknown;

  int? _lastEmittedTimestamp;
  bool _isRunning = false;
  bool _isDisposed = false;
  AssemblerStatus _status = AssemblerStatus.stopped;

  // Diagnostic counters
  int _emittedCount = 0;
  int _droppedSkewCount = 0;
  int _droppedRateLimitCount = 0;
  int _droppedOutOfOrderCount = 0;

  SensorDataAssembler({
    required this.collectionService,
    this.maxImuSkew = const Duration(milliseconds: 250),
    this.minOutputInterval = const Duration(milliseconds: 50),
    this.maxGnssAge = const Duration(milliseconds: 3000),
    this.maxGnssAccuracy = 30.0,
    this.autoManageService = false,
    this.ownsCollectionService = false,
  });

  /// Broadcast stream of canonical, aligned [SensorData] snapshots.
  Stream<SensorData> get sensorDataStream => _sensorDataController.stream;

  /// Broadcast stream of assembler state transitions.
  Stream<AssemblerStatus> get statusStream => _statusController.stream;

  /// Current assembler status.
  AssemblerStatus get status => _status;

  /// Whether the assembler is actively listening and assembling readings.
  bool get isRunning => _isRunning;

  /// Whether the assembler has been permanently disposed.
  bool get isDisposed => _isDisposed;

  /// Total number of [SensorData] snapshots successfully emitted.
  int get emittedCount => _emittedCount;

  /// Number of candidate snapshots dropped because IMU skew exceeded [maxImuSkew].
  int get droppedSkewCount => _droppedSkewCount;

  /// Number of candidate snapshots dropped because they arrived within
  /// [minOutputInterval] of the previous snapshot.
  int get droppedRateLimitCount => _droppedRateLimitCount;

  /// Number of sensor readings ignored because their timestamps were older
  /// than or equal to the latest accepted reading for that sensor.
  int get droppedOutOfOrderCount => _droppedOutOfOrderCount;

  /// Starts listening to the collection service streams.
  ///
  /// This method is idempotent. If already running, returns immediately.
  /// Throws [StateError] if called after [dispose].
  Future<void> start() async {
    if (_isDisposed) {
      throw StateError('Cannot start a disposed SensorDataAssembler.');
    }
    if (_isRunning) {
      return;
    }

    if (autoManageService && !collectionService.isRunning) {
      await collectionService.start();
    }

    _isRunning = true;
    _latestGnssStatus = collectionService.gnssStatus;

    _subscriptions.add(
      collectionService.accelerometerStream.listen(
        _onAccelerometer,
        cancelOnError: false,
      ),
    );
    _subscriptions.add(
      collectionService.gyroscopeStream.listen(
        _onGyroscope,
        cancelOnError: false,
      ),
    );
    _subscriptions.add(
      collectionService.magnetometerStream.listen(
        _onMagnetometer,
        cancelOnError: false,
      ),
    );
    _subscriptions.add(
      collectionService.gnssStream.listen(_onGnss, cancelOnError: false),
    );
    _subscriptions.add(
      collectionService.gnssStatusStream.listen(
        _onGnssStatus,
        cancelOnError: false,
      ),
    );

    _updateInitialStatus();
  }

  /// Stops listening to collection service streams.
  ///
  /// This method is idempotent. Cancels all subscriptions and resets
  /// in-progress sensor buffers so restarts begin from a clean state.
  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;

    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    if (autoManageService && collectionService.isRunning) {
      await collectionService.stop();
    }

    _latestAccelerometer = null;
    _latestGyroscope = null;
    _latestMagnetometer = null;
    _latestGnssReading = null;
    _lastEmittedTimestamp = null;

    _setStatus(AssemblerStatus.stopped);
  }

  /// Permanently disposes the assembler and closes stream controllers.
  ///
  /// Does NOT dispose the underlying [SensorCollectionService] unless
  /// [ownsCollectionService] was explicitly set to true.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    await stop();

    if (ownsCollectionService && !collectionService.isDisposed) {
      await collectionService.dispose();
    }

    _status = AssemblerStatus.disposed;
    if (!_statusController.isClosed) {
      _statusController.add(AssemblerStatus.disposed);
    }

    await _sensorDataController.close();
    await _statusController.close();
  }

  void _onAccelerometer(TimestampedVector3 reading) {
    if (!_isRunning || _isDisposed) return;
    if (_latestAccelerometer != null &&
        reading.timestamp <= _latestAccelerometer!.timestamp) {
      _droppedOutOfOrderCount++;
      return;
    }
    _latestAccelerometer = reading;
    _evaluateCandidate();
  }

  void _onGyroscope(TimestampedVector3 reading) {
    if (!_isRunning || _isDisposed) return;
    if (_latestGyroscope != null &&
        reading.timestamp <= _latestGyroscope!.timestamp) {
      _droppedOutOfOrderCount++;
      return;
    }
    _latestGyroscope = reading;
    _evaluateCandidate();
  }

  void _onMagnetometer(TimestampedVector3 reading) {
    if (!_isRunning || _isDisposed) return;
    if (_latestMagnetometer != null &&
        reading.timestamp <= _latestMagnetometer!.timestamp) {
      _droppedOutOfOrderCount++;
      return;
    }
    _latestMagnetometer = reading;
    _evaluateCandidate();
  }

  void _onGnss(GnssReading reading) {
    if (!_isRunning || _isDisposed) return;
    if (_latestGnssReading != null &&
        reading.timestamp <= _latestGnssReading!.timestamp) {
      _droppedOutOfOrderCount++;
      return;
    }
    _latestGnssReading = reading;
  }

  void _onGnssStatus(GnssAccessStatus status) {
    if (!_isRunning || _isDisposed) return;
    _latestGnssStatus = status;
  }

  void _updateInitialStatus() {
    if (_latestAccelerometer == null) {
      _setStatus(AssemblerStatus.waitingForAccelerometer);
    } else if (_latestGyroscope == null) {
      _setStatus(AssemblerStatus.waitingForGyroscope);
    } else if (_latestMagnetometer == null) {
      _setStatus(AssemblerStatus.waitingForMagnetometer);
    }
  }

  void _evaluateCandidate() {
    if (!_isRunning || _isDisposed) return;

    if (_latestAccelerometer == null) {
      _setStatus(AssemblerStatus.waitingForAccelerometer);
      return;
    }
    if (_latestGyroscope == null) {
      _setStatus(AssemblerStatus.waitingForGyroscope);
      return;
    }
    if (_latestMagnetometer == null) {
      _setStatus(AssemblerStatus.waitingForMagnetometer);
      return;
    }

    final accelTs = _latestAccelerometer!.timestamp;
    final gyroTs = _latestGyroscope!.timestamp;
    final magTs = _latestMagnetometer!.timestamp;

    // Snapshot timestamp is the latest measurement timestamp among the 3 IMU readings
    final candidateTimestamp = max(accelTs, max(gyroTs, magTs));

    // IMU alignment skew check
    final minTs = min(accelTs, min(gyroTs, magTs));
    final skew = candidateTimestamp - minTs;
    if (skew > maxImuSkew.inMilliseconds) {
      _droppedSkewCount++;
      _setStatus(AssemblerStatus.waitingForAlignedImu);
      return;
    }

    // Monotonicity and rate limit check
    if (_lastEmittedTimestamp != null) {
      final elapsed = candidateTimestamp - _lastEmittedTimestamp!;
      if (elapsed <= 0) {
        return;
      }
      if (elapsed < minOutputInterval.inMilliseconds) {
        _droppedRateLimitCount++;
        _setStatus(AssemblerStatus.waitingForRateLimit);
        return;
      }
    }

    // GNSS Usability Policy
    bool isGnssUsable = false;
    double? latitude;
    double? longitude;
    double? gnssAccuracy;

    if (_latestGnssStatus == GnssAccessStatus.ready &&
        _latestGnssReading != null) {
      final fix = _latestGnssReading!;
      final fixAge = candidateTimestamp - fix.timestamp;
      if (fixAge >= 0 &&
          fixAge <= maxGnssAge.inMilliseconds &&
          fix.accuracy <= maxGnssAccuracy) {
        isGnssUsable = true;
        latitude = fix.latitude;
        longitude = fix.longitude;
        gnssAccuracy = fix.accuracy;
      }
    }

    // Canonical SensorData mapping
    final snapshot = SensorData(
      timestamp: candidateTimestamp,
      accelerometerX: _latestAccelerometer!.x,
      accelerometerY: _latestAccelerometer!.y,
      accelerometerZ: _latestAccelerometer!.z,
      gyroscopeX: _latestGyroscope!.x,
      gyroscopeY: _latestGyroscope!.y,
      gyroscopeZ: _latestGyroscope!.z,
      magnetometerX: _latestMagnetometer!.x,
      magnetometerY: _latestMagnetometer!.y,
      magnetometerZ: _latestMagnetometer!.z,
      latitude: latitude,
      longitude: longitude,
      gnssAccuracy: gnssAccuracy,
      gnssAvailable: isGnssUsable,
    );

    _lastEmittedTimestamp = candidateTimestamp;
    _emittedCount++;
    _setStatus(AssemblerStatus.emitting);

    if (!_sensorDataController.isClosed) {
      _sensorDataController.add(snapshot);
    }
  }

  void _setStatus(AssemblerStatus newStatus) {
    if (_isDisposed || _status == newStatus) return;
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
  }
}
