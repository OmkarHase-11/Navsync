import 'package:geolocator/geolocator.dart';
import 'package:mobile/models/raw_sensor_reading.dart';
import 'package:sensors_plus/sensors_plus.dart' as sensors_plus;

export 'package:geolocator/geolocator.dart' show LocationPermission;

/// Injectable abstraction over platform sensor and location APIs.
///
/// Decouples [SensorCollectionService] from direct platform channel calls,
/// enabling fully isolated unit testing without hardware or platform channels.
abstract class SensorPlatformAdapter {
  /// Stream of accelerometer measurements including gravity (m/s²).
  Stream<TimestampedVector3> get accelerometerStream;

  /// Stream of gyroscope angular velocity measurements (rad/s).
  Stream<TimestampedVector3> get gyroscopeStream;

  /// Stream of magnetometer ambient magnetic field measurements (µT).
  Stream<TimestampedVector3> get magnetometerStream;

  /// Whether location services are enabled on the device.
  Future<bool> isLocationServiceEnabled();

  /// Checks the current location permission state.
  Future<LocationPermission> checkLocationPermission();

  /// Requests foreground location permission from the user.
  Future<LocationPermission> requestLocationPermission();

  /// Stream of foreground GNSS position fixes.
  Stream<GnssReading> get gnssStream;
}

/// Production implementation of [SensorPlatformAdapter] using `sensors_plus`
/// and `geolocator`.
///
/// Units follow canonical NavSync contracts:
/// - Accelerometer: m/s² (including gravity)
/// - Gyroscope: rad/s
/// - Magnetometer: µT
/// - GNSS: WGS84 decimal degrees and horizontal accuracy in meters
/// - Timestamps: Unix milliseconds
class DefaultSensorPlatformAdapter implements SensorPlatformAdapter {
  /// Sampling interval for hardware IMU sensors (accelerometer, gyro, mag).
  ///
  /// Defaults to 50ms (20 Hz), which is a moderate sampling rate suitable
  /// for an MVP and well below the Android 200 Hz permission threshold.
  final Duration samplingPeriod;

  /// Custom location settings for the GNSS position stream.
  final LocationSettings locationSettings;

  /// Injectable clock for fallback timestamp generation.
  final int Function() clock;

  DefaultSensorPlatformAdapter({
    this.samplingPeriod = const Duration(milliseconds: 50),
    this.locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    ),
    int Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  @override
  Stream<TimestampedVector3> get accelerometerStream {
    return sensors_plus
        .accelerometerEventStream(samplingPeriod: samplingPeriod)
        .map((event) {
          final ts = event.timestamp.millisecondsSinceEpoch;
          final validTs = ts > 0 ? ts : clock();
          return TimestampedVector3(
            timestamp: validTs,
            x: event.x,
            y: event.y,
            z: event.z,
          );
        });
  }

  @override
  Stream<TimestampedVector3> get gyroscopeStream {
    return sensors_plus
        .gyroscopeEventStream(samplingPeriod: samplingPeriod)
        .map((event) {
          final ts = event.timestamp.millisecondsSinceEpoch;
          final validTs = ts > 0 ? ts : clock();
          return TimestampedVector3(
            timestamp: validTs,
            x: event.x,
            y: event.y,
            z: event.z,
          );
        });
  }

  @override
  Stream<TimestampedVector3> get magnetometerStream {
    return sensors_plus
        .magnetometerEventStream(samplingPeriod: samplingPeriod)
        .map((event) {
          final ts = event.timestamp.millisecondsSinceEpoch;
          final validTs = ts > 0 ? ts : clock();
          return TimestampedVector3(
            timestamp: validTs,
            x: event.x,
            y: event.y,
            z: event.z,
          );
        });
  }

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkLocationPermission() =>
      Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestLocationPermission() =>
      Geolocator.requestPermission();

  @override
  Stream<GnssReading> get gnssStream {
    return Geolocator.getPositionStream(locationSettings: locationSettings)
        .map((pos) {
          final ts = pos.timestamp.millisecondsSinceEpoch;
          final validTs = ts > 0 ? ts : clock();
          final acc = pos.accuracy >= 0 ? pos.accuracy : 0.0;
          return GnssReading(
            timestamp: validTs,
            latitude: pos.latitude,
            longitude: pos.longitude,
            accuracy: acc,
          );
        });
  }
}
