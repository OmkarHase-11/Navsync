/// Dart model for the canonical NavSync NavigationOutput interface contract.
///
/// See: integration/interfaces/README.md §5 — NavigationOutput
///
/// This is an immutable value class with JSON serialization matching the
/// exact field names, types, and enum strings defined in the contract.
/// Speed is stored internally in m/s; use [speedKmh] for display conversion.
library;

/// Active navigation mode.
///
/// See: integration/interfaces/README.md §7 — Navigation Modes
enum NavigationMode {
  /// GNSS information is available and is being used with the
  /// navigation/inertial system.
  gnssIns,

  /// GNSS is unavailable and vehicle position is estimated using the
  /// Dead Reckoning/navigation system.
  deadReckoning;

  /// Canonical JSON string for this mode.
  String toJson() => switch (this) {
    NavigationMode.gnssIns => 'GNSS_INS',
    NavigationMode.deadReckoning => 'DEAD_RECKONING',
  };

  /// Parse the canonical JSON string into a [NavigationMode].
  ///
  /// Throws [FormatException] if [value] is not a recognized enum string.
  static NavigationMode fromJson(String value) => switch (value) {
    'GNSS_INS' => NavigationMode.gnssIns,
    'DEAD_RECKONING' => NavigationMode.deadReckoning,
    _ => throw FormatException(
      'Invalid NavigationMode: "$value". '
      'Expected "GNSS_INS" or "DEAD_RECKONING".',
    ),
  };
}

/// Whether the navigation engine currently considers GNSS usable.
///
/// See: integration/interfaces/README.md §6 — GNSS Status
enum GnssStatus {
  /// GNSS data is currently considered usable.
  available,

  /// GNSS data is currently considered unusable.
  unavailable;

  /// Canonical JSON string for this status.
  String toJson() => switch (this) {
    GnssStatus.available => 'AVAILABLE',
    GnssStatus.unavailable => 'UNAVAILABLE',
  };

  /// Parse the canonical JSON string into a [GnssStatus].
  ///
  /// Throws [FormatException] if [value] is not a recognized enum string.
  static GnssStatus fromJson(String value) => switch (value) {
    'AVAILABLE' => GnssStatus.available,
    'UNAVAILABLE' => GnssStatus.unavailable,
    _ => throw FormatException(
      'Invalid GnssStatus: "$value". '
      'Expected "AVAILABLE" or "UNAVAILABLE".',
    ),
  };
}

/// The position/navigation estimate produced by the navigation engine,
/// before optional map matching.
///
/// See: integration/interfaces/README.md §5 — NavigationOutput
///
/// All fields are immutable. [speedMps] is stored in m/s as required by the
/// contract (§10). Use [speedKmh] for UI display conversion.
class NavigationOutput {
  /// Epoch represented by the navigation estimate (Unix milliseconds).
  final int timestamp;

  /// Estimated latitude in WGS84 decimal degrees (-90 to +90).
  final double latitude;

  /// Estimated longitude in WGS84 decimal degrees (-180 to +180).
  final double longitude;

  /// Nonnegative scalar vehicle speed estimate in m/s.
  final double speedMps;

  /// Vehicle heading in degrees clockwise from true north (0 ≤ heading < 360).
  final double heading;

  /// Active navigation mode.
  final NavigationMode navigationMode;

  /// Whether the navigation engine currently considers GNSS usable.
  final GnssStatus gnssStatus;

  /// Nonnegative estimated horizontal position error in meters, if available.
  /// Null means unknown — not zero error.
  final double? positionError;

  const NavigationOutput({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speedMps,
    required this.heading,
    required this.navigationMode,
    required this.gnssStatus,
    this.positionError,
  });

  /// Speed converted to km/h for UI display.
  ///
  /// The interchange value remains m/s ([speedMps]).
  double get speedKmh => speedMps * 3.6;

  /// Deserialize from the canonical JSON representation.
  ///
  /// JSON key `"speed"` maps to [speedMps] (internal m/s).
  /// `"position_error"` may be `null` or omitted entirely.
  ///
  /// Throws [FormatException] on unrecognized enum strings.
  factory NavigationOutput.fromJson(Map<String, dynamic> json) {
    return NavigationOutput(
      timestamp: json['timestamp'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speedMps: (json['speed'] as num).toDouble(),
      heading: (json['heading'] as num).toDouble(),
      navigationMode: NavigationMode.fromJson(
        json['navigation_mode'] as String,
      ),
      gnssStatus: GnssStatus.fromJson(json['gnss_status'] as String),
      positionError: json.containsKey('position_error')
          ? (json['position_error'] as num?)?.toDouble()
          : null,
    );
  }

  /// Serialize to the canonical JSON representation.
  ///
  /// [speedMps] is serialized under key `"speed"`.
  /// [positionError] is always included (as `null` when unknown),
  /// following the contract recommendation.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'speed': speedMps,
      'heading': heading,
      'navigation_mode': navigationMode.toJson(),
      'gnss_status': gnssStatus.toJson(),
      'position_error': positionError,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigationOutput &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          speedMps == other.speedMps &&
          heading == other.heading &&
          navigationMode == other.navigationMode &&
          gnssStatus == other.gnssStatus &&
          positionError == other.positionError;

  @override
  int get hashCode => Object.hash(
    timestamp,
    latitude,
    longitude,
    speedMps,
    heading,
    navigationMode,
    gnssStatus,
    positionError,
  );

  @override
  String toString() =>
      'NavigationOutput(timestamp: $timestamp, '
      'lat: $latitude, lng: $longitude, '
      'speed: ${speedMps}m/s, heading: $heading°, '
      'mode: ${navigationMode.toJson()}, '
      'gnss: ${gnssStatus.toJson()}, '
      'error: $positionError)';
}
