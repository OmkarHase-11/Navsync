/// Plugin-independent raw sensor acquisition models.
///
/// These immutable data classes represent discrete hardware readings captured
/// during foreground sensor acquisition. They decouple higher-level services
/// from specific platform plugin types (e.g. `sensors_plus` and `geolocator`).
library;

/// Discrete 3-axis sensor measurement with an acquisition timestamp.
///
/// Used for accelerometer, gyroscope, and magnetometer readings.
class TimestampedVector3 {
  /// Unix millisecond epoch of the measurement.
  final int timestamp;

  /// Measurement on the X axis.
  final double x;

  /// Measurement on the Y axis.
  final double y;

  /// Measurement on the Z axis.
  final double z;

  /// Creates an immutable [TimestampedVector3] with validation.
  ///
  /// Throws [ArgumentError] if:
  /// - [timestamp] is negative
  /// - [x], [y], or [z] is not finite (NaN or infinite)
  TimestampedVector3({
    required this.timestamp,
    required this.x,
    required this.y,
    required this.z,
  }) {
    if (timestamp < 0) {
      throw ArgumentError.value(
        timestamp,
        'timestamp',
        'Timestamp must be a non-negative Unix epoch millisecond value.',
      );
    }
    if (!x.isFinite) {
      throw ArgumentError.value(x, 'x', 'Value must be finite.');
    }
    if (!y.isFinite) {
      throw ArgumentError.value(y, 'y', 'Value must be finite.');
    }
    if (!z.isFinite) {
      throw ArgumentError.value(z, 'z', 'Value must be finite.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimestampedVector3 &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          x == other.x &&
          y == other.y &&
          z == other.z;

  @override
  int get hashCode => Object.hash(timestamp, x, y, z);

  @override
  String toString() =>
      'TimestampedVector3(ts: $timestamp, x: $x, y: $y, z: $z)';
}

/// Discrete GNSS location reading with horizontal accuracy.
class GnssReading {
  /// Unix millisecond epoch when the position was determined.
  final int timestamp;

  /// WGS84 latitude in decimal degrees (-90 to +90).
  final double latitude;

  /// WGS84 longitude in decimal degrees (-180 to +180).
  final double longitude;

  /// Estimated horizontal accuracy in meters (non-negative).
  final double accuracy;

  /// Creates an immutable [GnssReading] with validation.
  ///
  /// Throws [ArgumentError] if:
  /// - [timestamp] is negative
  /// - any coordinate or accuracy value is not finite
  /// - [latitude] is outside [-90, +90]
  /// - [longitude] is outside [-180, +180]
  /// - [accuracy] is negative
  GnssReading({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  }) {
    if (timestamp < 0) {
      throw ArgumentError.value(
        timestamp,
        'timestamp',
        'Timestamp must be a non-negative Unix epoch millisecond value.',
      );
    }
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'Latitude must be a finite number between -90 and +90.',
      );
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'Longitude must be a finite number between -180 and +180.',
      );
    }
    if (!accuracy.isFinite || accuracy < 0) {
      throw ArgumentError.value(
        accuracy,
        'accuracy',
        'Accuracy must be a non-negative finite number.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GnssReading &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          accuracy == other.accuracy;

  @override
  int get hashCode => Object.hash(timestamp, latitude, longitude, accuracy);

  @override
  String toString() =>
      'GnssReading(ts: $timestamp, lat: ${latitude.toStringAsFixed(4)}, '
      'lng: ${longitude.toStringAsFixed(4)}, acc: ${accuracy.toStringAsFixed(1)}m)';
}

/// Lifecycle and authorization states for GNSS location access.
enum GnssAccessStatus {
  /// GNSS access state has not been checked yet.
  unknown,

  /// Currently evaluating location service availability and permissions.
  checking,

  /// Location services enabled and foreground permission granted; receiving fixes.
  ready,

  /// System location services are disabled on the device.
  servicesDisabled,

  /// Foreground location permission was denied by the user.
  permissionDenied,

  /// Location permission was permanently denied (requires manual app settings change).
  permissionDeniedForever,

  /// An unexpected error occurred while checking or requesting GNSS access.
  error,
}

/// Identifies the sensor hardware stream that produced an event or error.
enum SensorSource {
  /// Accelerometer stream (including gravity).
  accelerometer,

  /// Gyroscope stream (angular velocity).
  gyroscope,

  /// Magnetometer stream (ambient magnetic field).
  magnetometer,

  /// GNSS / location fix stream.
  gnss,
}

/// Recoverable asynchronous error emitted by a sensor stream.
class SensorCollectionError {
  /// Sensor hardware source that produced the error.
  final SensorSource source;

  /// Underlying error object.
  final Object error;

  /// Associated stack trace, if available.
  final StackTrace? stackTrace;

  const SensorCollectionError({
    required this.source,
    required this.error,
    this.stackTrace,
  });

  @override
  String toString() => 'SensorCollectionError($source: $error)';
}
