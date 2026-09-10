import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile/models/navigation_output.dart';
import 'package:mobile/models/sensor_data.dart';
import 'package:mobile/navigation/map_matching/map_matcher.dart';

import 'navigation_pipeline_result.dart';

/// Explicit external inference/heading result at a sensor measurement epoch.
class MotionEstimate {
  final int timestamp;
  final double speedMps;
  final double headingDegrees;
  final bool stationaryOverride;
  const MotionEstimate({
    required this.timestamp,
    required this.speedMps,
    required this.headingDegrees,
    this.stationaryOverride = false,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'speed_mps': speedMps,
    'heading_deg': headingDegrees,
    'stationary_override': stationaryOverride,
  };
}

typedef MotionProvider = Future<MotionEstimate?> Function(SensorData sensor);
typedef NavigationExchange = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> request,
);

/// Serialized adapter to a trip-scoped Python NavigationSession. No Python VM,
/// server URL, inferred heading, or synthetic speed is silently supplied here.
class NavigationPipeline extends ChangeNotifier {
  final NavigationExchange exchange;
  final MotionProvider motionProvider;
  final List<LatLng> route;
  final List<double>? mountRadians;
  final MapMatcher? matcher;
  StreamSubscription<SensorData>? _subscription;
  Future<void> _queue = Future.value();
  int _generation = 0;
  int? _lastTimestamp;
  bool _running = false;
  bool _disposed = false;
  bool _busy = false;
  SensorData? _pending;
  int? _lastReceivedTimestamp;
  NavigationPipelineResult? _latest;
  String? _error;

  NavigationPipeline({
    required this.exchange,
    required this.motionProvider,
    required List<LatLng> route,
    List<double>? mountRadians,
    bool mapMatching = true,
  }) : route = List.unmodifiable(route),
       mountRadians = mountRadians == null
           ? null
           : List.unmodifiable(mountRadians),
       matcher = mapMatching ? MapMatcher() : null;

  NavigationPipelineResult? get latest => _latest;
  String? get error => _error;
  bool get running => _running;

  Future<void> start(Stream<SensorData> snapshots) async {
    if (_disposed) throw StateError('Pipeline disposed');
    final generation = ++_generation;
    _running = true;
    _latest = null;
    _lastTimestamp = null;
    _pending = null;
    _lastReceivedTimestamp = null;
    _error = null;
    final previousSubscription = _subscription;
    _subscription = null;
    await previousSubscription?.cancel();
    if (!_running || generation != _generation || _disposed) return;
    try {
      final reset = _queue.then((_) async {
        if (!_running || generation != _generation || _disposed) return;
        final response = await exchange({'operation': 'reset'});
        if (response['reset'] != true) {
          throw StateError('Navigation reset failed');
        }
      });
      _queue = reset.catchError((Object _) {});
      await reset;
      if (!_running || generation != _generation || _disposed) return;
      _subscription = snapshots.listen(
        (sensor) {
          if (!_running || generation != _generation || _disposed) return;
          if (_lastReceivedTimestamp != null &&
              sensor.timestamp <= _lastReceivedTimestamp!) {
            _error = 'Sensor timestamps must strictly increase';
            notifyListeners();
            return;
          }
          _lastReceivedTimestamp = sensor.timestamp;
          // At most one in-flight request and one latest pending snapshot.
          if (_busy) {
            _pending = sensor;
            return;
          }
          _busy = true;
          _queue = _drain(sensor, generation).whenComplete(() => _busy = false);
        },
        onError: (Object error) {
          if (_running && generation == _generation) {
            _error = error.toString();
            notifyListeners();
          }
        },
      );
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _error = error.toString();
        _running = false;
        notifyListeners();
      }
    }
  }

  Future<void> _drain(SensorData first, int generation) async {
    SensorData? next = first;
    while (next != null &&
        _running &&
        generation == _generation &&
        !_disposed) {
      await _consume(next, generation);
      if (!_running || generation != _generation || _disposed) return;
      next = _pending;
      _pending = null;
    }
  }

  Future<void> _consume(SensorData sensor, int generation) async {
    try {
      if (_lastTimestamp != null && sensor.timestamp <= _lastTimestamp!) {
        throw StateError('Sensor timestamps must strictly increase');
      }
      final motion = await motionProvider(sensor);
      if (!_running || generation != _generation || _disposed) return;
      if (motion == null) {
        throw StateError('Waiting for speed and heading provider');
      }
      if (motion.timestamp != sensor.timestamp ||
          !motion.speedMps.isFinite ||
          motion.speedMps < 0 ||
          !motion.headingDegrees.isFinite ||
          motion.headingDegrees < 0 ||
          motion.headingDegrees >= 360) {
        throw StateError('Invalid or stale motion estimate');
      }
      final response = await exchange({
        'operation': 'update',
        'sensor': sensor.toJson(),
        'motion': motion.toJson(),
        // Only connect the existing assembler stream, which checks original fix age.
        'gnss_prevalidated': true, 'mount_radians': mountRadians,
      });
      if (!_running || generation != _generation || _disposed) return;
      if (response['error'] != null) {
        throw StateError(response['error'].toString());
      }
      final raw = NavigationOutput.fromJson(
        Map<String, dynamic>.from(response['raw'] as Map),
      );
      if (raw.timestamp != sensor.timestamp) {
        throw StateError('Stale navigation response');
      }
      final match = matcher?.match(
        latitude: raw.latitude,
        longitude: raw.longitude,
        headingDegrees: raw.heading,
        route: route,
      );
      _latest = NavigationPipelineResult(raw: raw, mapMatch: match);
      _lastTimestamp = sensor.timestamp;
      _error = null;
    } catch (error) {
      if (generation != _generation || _disposed) return;
      _error = error.toString();
    }
    if (!_disposed && generation == _generation) notifyListeners();
  }

  Future<void> stop() async {
    ++_generation;
    _running = false;
    _latest = null;
    _lastTimestamp = null;
    _pending = null;
    _lastReceivedTimestamp = null;
    _error = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
