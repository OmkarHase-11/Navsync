/// Dart model for the canonical NavSync SensorData interface contract.
///
/// See: integration/interfaces/README.md §3 — SensorData
///
/// This is an immutable value class with JSON serialization matching the
/// exact field names, types, and enum strings defined in the contract.
///
/// All keys are required; only [latitude], [longitude], and [gnssAccuracy]
/// are nullable. When [gnssAvailable] is `true`, those three must be
/// non-null. When `false`, all three must be `null`.
library;

/// Measurements collected by the smartphone.
///
/// See: integration/interfaces/README.md §3 — SensorData
///
/// All fields are immutable. Sensor values use the contract's canonical units:
/// - Accelerometer: m/s² (including gravity)
/// - Gyroscope: rad/s
/// - Magnetometer: µT
/// - Coordinates: WGS84 decimal degrees
/// - Accuracy: meters
/// - Timestamp: Unix milliseconds
class SensorData {
  /// Measurement epoch of this sensor snapshot (Unix milliseconds).
  final int timestamp;

  /// Acceleration on device X axis, including gravity (m/s²).
  final double accelerometerX;

  /// Acceleration on device Y axis, including gravity (m/s²).
  final double accelerometerY;

  /// Acceleration on device Z axis, including gravity (m/s²).
  final double accelerometerZ;

  /// Angular velocity about device X axis (rad/s).
  final double gyroscopeX;

  /// Angular velocity about device Y axis (rad/s).
  final double gyroscopeY;

  /// Angular velocity about device Z axis (rad/s).
  final double gyroscopeZ;

  /// Magnetic field on device X axis (µT).
  final double magnetometerX;

  /// Magnetic field on device Y axis (µT).
  final double magnetometerY;

  /// Magnetic field on device Z axis (µT).
  final double magnetometerZ;

  /// Usable GNSS latitude in WGS84 decimal degrees (-90 to +90), or `null`.
  final double? latitude;

  /// Usable GNSS longitude in WGS84 decimal degrees (-180 to +180), or `null`.
  final double? longitude;

  /// Nonnegative horizontal accuracy estimate in meters, or `null`.
  final double? gnssAccuracy;

  /// Whether GNSS is currently considered usable.
  final bool gnssAvailable;

  /// Creates a [SensorData] instance with validation.
  ///
  /// Throws [ArgumentError] if:
  /// - [timestamp] is negative.
  /// - [gnssAvailable] is `true` but any of [latitude], [longitude],
  ///   or [gnssAccuracy] is `null`.
  /// - [gnssAvailable] is `false` but any of [latitude], [longitude],
  ///   or [gnssAccuracy] is non-null.
  /// - [latitude] is outside the range -90 to +90.
  /// - [longitude] is outside the range -180 to +180.
  /// - [gnssAccuracy] is negative.
  SensorData({
    required this.timestamp,
    required this.accelerometerX,
    required this.accelerometerY,
    required this.accelerometerZ,
    required this.gyroscopeX,
    required this.gyroscopeY,
    required this.gyroscopeZ,
    required this.magnetometerX,
    required this.magnetometerY,
    required this.magnetometerZ,
    required this.latitude,
    required this.longitude,
    required this.gnssAccuracy,
    required this.gnssAvailable,
  }) {
    if (timestamp < 0) {
      throw ArgumentError.value(
        timestamp,
        'timestamp',
        'Must be a non-negative Unix millisecond epoch.',
      );
    }

    if (gnssAvailable) {
      if (latitude == null || longitude == null || gnssAccuracy == null) {
        throw ArgumentError(
          'When gnssAvailable is true, latitude, longitude, and '
          'gnssAccuracy must all be non-null.',
        );
      }
      if (latitude! < -90 || latitude! > 90) {
        throw ArgumentError.value(
          latitude,
          'latitude',
          'Must be between -90 and +90 inclusive.',
        );
      }
      if (longitude! < -180 || longitude! > 180) {
        throw ArgumentError.value(
          longitude,
          'longitude',
          'Must be between -180 and +180 inclusive.',
        );
      }
      if (gnssAccuracy! < 0) {
        throw ArgumentError.value(
          gnssAccuracy,
          'gnssAccuracy',
          'Must be non-negative.',
        );
      }
    } else {
      if (latitude != null || longitude != null || gnssAccuracy != null) {
        throw ArgumentError(
          'When gnssAvailable is false, latitude, longitude, and '
          'gnssAccuracy must all be null.',
        );
      }
    }
  }

  /// Deserialize from the canonical JSON representation.
  ///
  /// JSON keys use snake_case as defined in the contract.
  ///
  /// Throws [ArgumentError] if validation fails.
  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      timestamp: json['timestamp'] as int,
      accelerometerX: (json['accelerometer_x'] as num).toDouble(),
      accelerometerY: (json['accelerometer_y'] as num).toDouble(),
      accelerometerZ: (json['accelerometer_z'] as num).toDouble(),
      gyroscopeX: (json['gyroscope_x'] as num).toDouble(),
      gyroscopeY: (json['gyroscope_y'] as num).toDouble(),
      gyroscopeZ: (json['gyroscope_z'] as num).toDouble(),
      magnetometerX: (json['magnetometer_x'] as num).toDouble(),
      magnetometerY: (json['magnetometer_y'] as num).toDouble(),
      magnetometerZ: (json['magnetometer_z'] as num).toDouble(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      gnssAccuracy: (json['gnss_accuracy'] as num?)?.toDouble(),
      gnssAvailable: json['gnss_available'] as bool,
    );
  }

  /// Serialize to the canonical JSON representation.
  ///
  /// All 14 keys are always included. Nullable GNSS fields serialize as
  /// JSON `null` when absent, following the contract recommendation.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'accelerometer_x': accelerometerX,
      'accelerometer_y': accelerometerY,
      'accelerometer_z': accelerometerZ,
      'gyroscope_x': gyroscopeX,
      'gyroscope_y': gyroscopeY,
      'gyroscope_z': gyroscopeZ,
      'magnetometer_x': magnetometerX,
      'magnetometer_y': magnetometerY,
      'magnetometer_z': magnetometerZ,
      'latitude': latitude,
      'longitude': longitude,
      'gnss_accuracy': gnssAccuracy,
      'gnss_available': gnssAvailable,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorData &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          accelerometerX == other.accelerometerX &&
          accelerometerY == other.accelerometerY &&
          accelerometerZ == other.accelerometerZ &&
          gyroscopeX == other.gyroscopeX &&
          gyroscopeY == other.gyroscopeY &&
          gyroscopeZ == other.gyroscopeZ &&
          magnetometerX == other.magnetometerX &&
          magnetometerY == other.magnetometerY &&
          magnetometerZ == other.magnetometerZ &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          gnssAccuracy == other.gnssAccuracy &&
          gnssAvailable == other.gnssAvailable;

  @override
  int get hashCode => Object.hash(
    timestamp,
    accelerometerX,
    accelerometerY,
    accelerometerZ,
    gyroscopeX,
    gyroscopeY,
    gyroscopeZ,
    magnetometerX,
    magnetometerY,
    magnetometerZ,
    latitude,
    longitude,
    gnssAccuracy,
    gnssAvailable,
  );

  @override
  String toString() =>
      'SensorData(timestamp: $timestamp, '
      'accel: [$accelerometerX, $accelerometerY, $accelerometerZ] m/s², '
      'gyro: [$gyroscopeX, $gyroscopeY, $gyroscopeZ] rad/s, '
      'mag: [$magnetometerX, $magnetometerY, $magnetometerZ] µT, '
      'lat: $latitude, lng: $longitude, '
      'accuracy: $gnssAccuracy, gnss: $gnssAvailable)';
}
