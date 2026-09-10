import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobile/models/raw_sensor_reading.dart';
import 'package:mobile/models/sensor_data.dart';
import 'package:mobile/services/sensor_collection_service.dart';
import 'package:mobile/services/sensor_data_assembler.dart';
import 'package:mobile/services/sensor_platform_adapter.dart';

/// High-level UI and diagnostic status of the foreground sensor pipeline.
enum SensorPipelineStatus {
  /// The sensor pipeline is idle and has not been started.
  idle,

  /// Sensors are initializing and awaiting first hardware readings.
  starting,

  /// Actively collecting both IMU and valid GNSS fixes.
  collecting,

  /// Actively collecting IMU readings while GNSS is unavailable, waiting, or poor.
  collectingWithoutGnss,

  /// Collection was temporarily paused (e.g. app backgrounded during navigation).
  paused,

  /// Collection was explicitly stopped.
  stopped,

  /// Foreground location permission was denied by the user (IMU remains active).
  permissionDenied,

  /// Location permission was permanently denied; user can open Settings.
  permissionDeniedForever,

  /// Device location services are turned off in system settings.
  locationServicesDisabled,

  /// Required hardware sensor is missing or unavailable on this device.
  sensorUnavailable,

  /// An unrecoverable hardware or platform channel error occurred.
  error,
}

/// Central controller coordinating the real foreground sensor pipeline.
///
/// Responsibilities:
/// - Coordinates [SensorCollectionService] and [SensorDataAssembler].
/// - Exposes UI-safe state, snapshots, and diagnostic metrics via [ChangeNotifier].
/// - Throttles UI-facing rebuild notifications to prevent 20 Hz main-thread churn
///   while preserving the raw [sensorDataStream].
/// - Manages app lifecycle integration (pause on background, resume on foreground).
/// - Ensures zero platform channel leakages into the widget layer.
class SensorRuntimeController extends ChangeNotifier {
  final SensorCollectionService _collectionService;
  final SensorDataAssembler _assembler;
  final bool _ownsServices;
  final Duration uiThrottleInterval;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  SensorPipelineStatus _pipelineStatus = SensorPipelineStatus.idle;
  SensorData? _latestSnapshot;
  int _totalSnapshotCount = 0;
  int? _lastSnapshotTimestamp;
  bool _isImuActive = false;
  GnssAccessStatus _gnssAccessStatus = GnssAccessStatus.unknown;
  String? _lastErrorMessage;

  bool _isRunning = false;
  bool _isPaused = false;
  bool _isDisposed = false;

  Timer? _throttleTimer;
  DateTime _lastUiNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Creates a [SensorRuntimeController].
  ///
  /// Can be supplied with mock or fake [collectionService] and [assembler]
  /// for hermetic unit testing without real hardware.
  SensorRuntimeController({
    SensorCollectionService? collectionService,
    SensorDataAssembler? assembler,
    SensorPlatformAdapter? platformAdapter,
    this.uiThrottleInterval = const Duration(milliseconds: 250),
  }) : _ownsServices = collectionService == null && assembler == null,
       _collectionService =
           collectionService ??
           SensorCollectionService(adapter: platformAdapter),
       _assembler =
           assembler ??
           SensorDataAssembler(
             collectionService:
                 collectionService ??
                 SensorCollectionService(adapter: platformAdapter),
             autoManageService: true,
           );

  /// Current high-level pipeline status.
  SensorPipelineStatus get pipelineStatus => _pipelineStatus;

  /// Latest assembled [SensorData] snapshot, or null if none emitted yet.
  SensorData? get latestSnapshot => _latestSnapshot;

  /// Total number of valid [SensorData] snapshots emitted since start.
  int get totalSnapshotCount => _totalSnapshotCount;

  /// Timestamp (Unix milliseconds) of the most recent snapshot.
  int? get lastSnapshotTimestamp => _lastSnapshotTimestamp;

  /// Whether valid inertial data is actively arriving from the hardware.
  bool get isImuActive => _isImuActive;

  /// Current GNSS hardware and permission authorization status.
  GnssAccessStatus get gnssAccessStatus => _gnssAccessStatus;

  /// Most recent recoverable error message, if any.
  String? get lastErrorMessage => _lastErrorMessage;

  /// Whether the pipeline is currently running (not stopped or paused).
  bool get isRunning => _isRunning;

  /// Whether the pipeline was temporarily paused due to app suspension.
  bool get isPaused => _isPaused;

  /// Whether this controller has been permanently disposed.
  bool get isDisposed => _isDisposed;

  /// Direct unthrottled broadcast stream of canonical [SensorData] snapshots.
  Stream<SensorData> get sensorDataStream => _assembler.sensorDataStream;

  /// Starts foreground sensor acquisition and snapshot assembly.
  ///
  /// This method is idempotent. If already running, returns immediately.
  Future<void> start() async {
    if (_isDisposed) {
      throw StateError('Cannot start a disposed SensorRuntimeController.');
    }
    if (_isRunning) {
      return;
    }

    _isRunning = true;
    _isPaused = false;
    _updateStatus(SensorPipelineStatus.starting);

    _attachSubscriptions();

    try {
      await _collectionService.start();
      await _assembler.start();
      _gnssAccessStatus = _collectionService.gnssStatus;
      _deriveAndApplyPipelineStatus();
    } catch (e) {
      _lastErrorMessage = e.toString();
      _updateStatus(SensorPipelineStatus.error);
    }
  }

  /// Stops foreground sensor acquisition and cancels active subscriptions.
  ///
  /// This method is idempotent.
  Future<void> stop() async {
    if (!_isRunning && !_isPaused) {
      return;
    }

    _isRunning = false;
    _isPaused = false;
    _isImuActive = false;

    _detachSubscriptions();

    await _assembler.stop();
    await _collectionService.stop();

    _updateStatus(SensorPipelineStatus.stopped);
  }

  /// Pauses sensor acquisition when the app moves to background/inactive.
  Future<void> pause() async {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    _isPaused = true;
    _isImuActive = false;

    _detachSubscriptions();
    await _assembler.stop();
    await _collectionService.stop();

    _updateStatus(SensorPipelineStatus.paused);
  }

  /// Resumes sensor acquisition if it was previously paused.
  Future<void> resume() async {
    if (!_isPaused || _isDisposed) {
      return;
    }

    await start();
  }

  /// Opens the device settings page for user-initiated permission updates.
  Future<bool> openAppSettings() => _collectionService.openAppSettings();

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    _isRunning = false;
    _isPaused = false;

    _throttleTimer?.cancel();
    _detachSubscriptions();

    _assembler.stop();
    _collectionService.stop();

    if (_ownsServices) {
      _assembler.dispose();
      _collectionService.dispose();
    }

    super.dispose();
  }

  void _attachSubscriptions() {
    if (_subscriptions.isNotEmpty) return;

    _subscriptions.add(_assembler.sensorDataStream.listen(_onSnapshot));
    _subscriptions.add(
      _collectionService.gnssStatusStream.listen(_onGnssStatusChanged),
    );
    _subscriptions.add(_collectionService.errorStream.listen(_onErrorOccurred));
  }

  void _detachSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void _onSnapshot(SensorData snapshot) {
    if (!_isRunning || _isDisposed) return;

    _latestSnapshot = snapshot;
    _totalSnapshotCount++;
    _lastSnapshotTimestamp = snapshot.timestamp;
    _isImuActive = true;

    _deriveAndApplyPipelineStatus();
    _scheduleThrottledNotification();
  }

  void _onGnssStatusChanged(GnssAccessStatus status) {
    if (!_isRunning || _isDisposed) return;

    _gnssAccessStatus = status;
    _deriveAndApplyPipelineStatus();
    _notifyImmediate();
  }

  void _onErrorOccurred(SensorCollectionError error) {
    if (_isDisposed) return;

    _lastErrorMessage = error.error.toString();
    if (error.source == SensorSource.gnss) {
      // GNSS error still allows IMU collection
      _deriveAndApplyPipelineStatus();
    } else {
      _updateStatus(SensorPipelineStatus.error);
    }
    _notifyImmediate();
  }

  void _deriveAndApplyPipelineStatus() {
    if (!_isRunning) return;

    if (_gnssAccessStatus == GnssAccessStatus.permissionDeniedForever) {
      _updateStatus(SensorPipelineStatus.permissionDeniedForever);
      return;
    }
    if (_gnssAccessStatus == GnssAccessStatus.permissionDenied) {
      _updateStatus(SensorPipelineStatus.permissionDenied);
      return;
    }
    if (_gnssAccessStatus == GnssAccessStatus.servicesDisabled) {
      _updateStatus(SensorPipelineStatus.locationServicesDisabled);
      return;
    }

    if (_isImuActive) {
      if (_gnssAccessStatus == GnssAccessStatus.ready &&
          _latestSnapshot?.gnssAvailable == true) {
        _updateStatus(SensorPipelineStatus.collecting);
      } else {
        _updateStatus(SensorPipelineStatus.collectingWithoutGnss);
      }
    } else {
      _updateStatus(SensorPipelineStatus.starting);
    }
  }

  void _updateStatus(SensorPipelineStatus newStatus) {
    if (_pipelineStatus != newStatus) {
      _pipelineStatus = newStatus;
      _notifyImmediate();
    }
  }

  void _notifyImmediate() {
    if (_isDisposed) return;
    _throttleTimer?.cancel();
    _lastUiNotify = DateTime.now();
    notifyListeners();
  }

  void _scheduleThrottledNotification() {
    if (_isDisposed) return;

    if (uiThrottleInterval == Duration.zero) {
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastUiNotify) >= uiThrottleInterval) {
      _lastUiNotify = now;
      notifyListeners();
    } else {
      if (_throttleTimer == null || !_throttleTimer!.isActive) {
        final remaining = uiThrottleInterval - now.difference(_lastUiNotify);
        _throttleTimer = Timer(remaining, () {
          if (!_isDisposed) {
            _lastUiNotify = DateTime.now();
            notifyListeners();
          }
        });
      }
    }
  }
}
