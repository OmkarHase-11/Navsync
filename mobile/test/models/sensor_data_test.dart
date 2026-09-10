import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/sensor_data.dart';

void main() {
  // ── Canonical sample matching integration/interfaces/sample_data/sensor_data.json ──
  final Map<String, dynamic> sampleJson = {
    'timestamp': 1725552000123,
    'accelerometer_x': 0.12,
    'accelerometer_y': 0.35,
    'accelerometer_z': 9.78,
    'gyroscope_x': 0.002,
    'gyroscope_y': -0.003,
    'gyroscope_z': 0.015,
    'magnetometer_x': 21.4,
    'magnetometer_y': -5.8,
    'magnetometer_z': -38.2,
    'latitude': 18.5204,
    'longitude': 73.8567,
    'gnss_accuracy': 6.5,
    'gnss_available': true,
  };

  // ── GNSS-unavailable variant ──
  final Map<String, dynamic> gnssUnavailableJson = {
    'timestamp': 1725552000456,
    'accelerometer_x': 0.10,
    'accelerometer_y': 0.30,
    'accelerometer_z': 9.81,
    'gyroscope_x': 0.001,
    'gyroscope_y': -0.001,
    'gyroscope_z': 0.010,
    'magnetometer_x': 22.0,
    'magnetometer_y': -6.0,
    'magnetometer_z': -37.5,
    'latitude': null,
    'longitude': null,
    'gnss_accuracy': null,
    'gnss_available': false,
  };

  // ─────────────────────────────────────────────
  // §1 — fromJson: canonical sample data
  // ─────────────────────────────────────────────
  group('SensorData.fromJson', () {
    test('parses canonical sample data with GNSS available', () {
      final data = SensorData.fromJson(sampleJson);

      expect(data.timestamp, 1725552000123);
      expect(data.accelerometerX, 0.12);
      expect(data.accelerometerY, 0.35);
      expect(data.accelerometerZ, 9.78);
      expect(data.gyroscopeX, 0.002);
      expect(data.gyroscopeY, -0.003);
      expect(data.gyroscopeZ, 0.015);
      expect(data.magnetometerX, 21.4);
      expect(data.magnetometerY, -5.8);
      expect(data.magnetometerZ, -38.2);
      expect(data.latitude, 18.5204);
      expect(data.longitude, 73.8567);
      expect(data.gnssAccuracy, 6.5);
      expect(data.gnssAvailable, isTrue);
    });

    test('parses GNSS-unavailable data with all nullable fields null', () {
      final data = SensorData.fromJson(gnssUnavailableJson);

      expect(data.timestamp, 1725552000456);
      expect(data.latitude, isNull);
      expect(data.longitude, isNull);
      expect(data.gnssAccuracy, isNull);
      expect(data.gnssAvailable, isFalse);
    });

    test('parses integer sensor values as doubles', () {
      final json = {
        ...sampleJson,
        'accelerometer_x': 1,
        'gyroscope_y': 0,
        'magnetometer_z': -38,
      };
      final data = SensorData.fromJson(json);

      expect(data.accelerometerX, 1.0);
      expect(data.accelerometerX, isA<double>());
      expect(data.gyroscopeY, 0.0);
      expect(data.gyroscopeY, isA<double>());
      expect(data.magnetometerZ, -38.0);
      expect(data.magnetometerZ, isA<double>());
    });

    test('parses integer latitude/longitude as doubles', () {
      final json = {
        ...sampleJson,
        'latitude': 18,
        'longitude': 73,
        'gnss_accuracy': 7,
      };
      final data = SensorData.fromJson(json);

      expect(data.latitude, 18.0);
      expect(data.latitude, isA<double>());
      expect(data.longitude, 73.0);
      expect(data.longitude, isA<double>());
      expect(data.gnssAccuracy, 7.0);
      expect(data.gnssAccuracy, isA<double>());
    });

    test('parses negative sensor values correctly', () {
      final json = {
        ...sampleJson,
        'accelerometer_x': -9.81,
        'gyroscope_x': -3.14,
        'magnetometer_x': -100.5,
      };
      final data = SensorData.fromJson(json);

      expect(data.accelerometerX, -9.81);
      expect(data.gyroscopeX, -3.14);
      expect(data.magnetometerX, -100.5);
    });

    test('parses zero timestamp', () {
      final json = {...sampleJson, 'timestamp': 0};
      final data = SensorData.fromJson(json);

      expect(data.timestamp, 0);
    });

    test('parses boundary latitude values (-90 and +90)', () {
      final jsonNeg90 = {...sampleJson, 'latitude': -90.0};
      expect(SensorData.fromJson(jsonNeg90).latitude, -90.0);

      final jsonPos90 = {...sampleJson, 'latitude': 90.0};
      expect(SensorData.fromJson(jsonPos90).latitude, 90.0);
    });

    test('parses boundary longitude values (-180 and +180)', () {
      final jsonNeg180 = {...sampleJson, 'longitude': -180.0};
      expect(SensorData.fromJson(jsonNeg180).longitude, -180.0);

      final jsonPos180 = {...sampleJson, 'longitude': 180.0};
      expect(SensorData.fromJson(jsonPos180).longitude, 180.0);
    });

    test('parses zero gnss_accuracy', () {
      final json = {...sampleJson, 'gnss_accuracy': 0.0};
      final data = SensorData.fromJson(json);

      expect(data.gnssAccuracy, 0.0);
    });
  });

  // ─────────────────────────────────────────────
  // §2 — toJson: canonical output
  // ─────────────────────────────────────────────
  group('SensorData.toJson', () {
    test('produces exact canonical keys and values (GNSS available)', () {
      final data = SensorData.fromJson(sampleJson);
      final json = data.toJson();

      expect(json['timestamp'], 1725552000123);
      expect(json['accelerometer_x'], 0.12);
      expect(json['accelerometer_y'], 0.35);
      expect(json['accelerometer_z'], 9.78);
      expect(json['gyroscope_x'], 0.002);
      expect(json['gyroscope_y'], -0.003);
      expect(json['gyroscope_z'], 0.015);
      expect(json['magnetometer_x'], 21.4);
      expect(json['magnetometer_y'], -5.8);
      expect(json['magnetometer_z'], -38.2);
      expect(json['latitude'], 18.5204);
      expect(json['longitude'], 73.8567);
      expect(json['gnss_accuracy'], 6.5);
      expect(json['gnss_available'], true);
    });

    test('produces all 14 keys', () {
      final data = SensorData.fromJson(sampleJson);
      final json = data.toJson();

      expect(json.keys.length, 14);
      expect(json.containsKey('timestamp'), isTrue);
      expect(json.containsKey('accelerometer_x'), isTrue);
      expect(json.containsKey('accelerometer_y'), isTrue);
      expect(json.containsKey('accelerometer_z'), isTrue);
      expect(json.containsKey('gyroscope_x'), isTrue);
      expect(json.containsKey('gyroscope_y'), isTrue);
      expect(json.containsKey('gyroscope_z'), isTrue);
      expect(json.containsKey('magnetometer_x'), isTrue);
      expect(json.containsKey('magnetometer_y'), isTrue);
      expect(json.containsKey('magnetometer_z'), isTrue);
      expect(json.containsKey('latitude'), isTrue);
      expect(json.containsKey('longitude'), isTrue);
      expect(json.containsKey('gnss_accuracy'), isTrue);
      expect(json.containsKey('gnss_available'), isTrue);
    });

    test('serializes GNSS-unavailable data with null values', () {
      final data = SensorData.fromJson(gnssUnavailableJson);
      final json = data.toJson();

      expect(json['latitude'], isNull);
      expect(json['longitude'], isNull);
      expect(json['gnss_accuracy'], isNull);
      expect(json['gnss_available'], false);
    });

    test('uses snake_case keys, not camelCase', () {
      final data = SensorData.fromJson(sampleJson);
      final json = data.toJson();

      // Ensure no camelCase keys leak through
      expect(json.containsKey('accelerometerX'), isFalse);
      expect(json.containsKey('gyroscopeX'), isFalse);
      expect(json.containsKey('magnetometerX'), isFalse);
      expect(json.containsKey('gnssAccuracy'), isFalse);
      expect(json.containsKey('gnssAvailable'), isFalse);
    });
  });

  // ─────────────────────────────────────────────
  // §3 — round-trip: fromJson → toJson → fromJson
  // ─────────────────────────────────────────────
  group('round-trip serialization', () {
    test('GNSS-available data round-trips through fromJson/toJson', () {
      final original = SensorData.fromJson(sampleJson);
      final roundTripped = SensorData.fromJson(original.toJson());

      expect(roundTripped, original);
    });

    test('GNSS-unavailable data round-trips through fromJson/toJson', () {
      final original = SensorData.fromJson(gnssUnavailableJson);
      final roundTripped = SensorData.fromJson(original.toJson());

      expect(roundTripped, original);
    });
  });

  // ─────────────────────────────────────────────
  // §4 — validation: timestamp
  // ─────────────────────────────────────────────
  group('validation: timestamp', () {
    test('rejects negative timestamp', () {
      expect(
        () => SensorData.fromJson({...sampleJson, 'timestamp': -1}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('non-negative'),
          ),
        ),
      );
    });

    test('accepts zero timestamp', () {
      final data = SensorData.fromJson({...sampleJson, 'timestamp': 0});
      expect(data.timestamp, 0);
    });
  });

  // ─────────────────────────────────────────────
  // §5 — validation: GNSS coherence
  // ─────────────────────────────────────────────
  group('validation: GNSS coherence', () {
    test('rejects gnssAvailable=true with null latitude', () {
      expect(
        () => SensorData.fromJson({
          ...sampleJson,
          'gnss_available': true,
          'latitude': null,
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects gnssAvailable=true with null longitude', () {
      expect(
        () => SensorData.fromJson({
          ...sampleJson,
          'gnss_available': true,
          'longitude': null,
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects gnssAvailable=true with null gnss_accuracy', () {
      expect(
        () => SensorData.fromJson({
          ...sampleJson,
          'gnss_available': true,
          'gnss_accuracy': null,
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects gnssAvailable=false with non-null latitude', () {
      expect(
        () =>
            SensorData.fromJson({...gnssUnavailableJson, 'latitude': 18.5204}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects gnssAvailable=false with non-null longitude', () {
      expect(
        () =>
            SensorData.fromJson({...gnssUnavailableJson, 'longitude': 73.8567}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects gnssAvailable=false with non-null gnss_accuracy', () {
      expect(
        () =>
            SensorData.fromJson({...gnssUnavailableJson, 'gnss_accuracy': 6.5}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ─────────────────────────────────────────────
  // §6 — validation: latitude range
  // ─────────────────────────────────────────────
  group('validation: latitude range', () {
    test('rejects latitude > 90', () {
      expect(
        () => SensorData.fromJson({...sampleJson, 'latitude': 90.001}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('-90'),
          ),
        ),
      );
    });

    test('rejects latitude < -90', () {
      expect(
        () => SensorData.fromJson({...sampleJson, 'latitude': -90.001}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts latitude at -90 boundary', () {
      final data = SensorData.fromJson({...sampleJson, 'latitude': -90.0});
      expect(data.latitude, -90.0);
    });

    test('accepts latitude at +90 boundary', () {
      final data = SensorData.fromJson({...sampleJson, 'latitude': 90.0});
      expect(data.latitude, 90.0);
    });
  });

  // ─────────────────────────────────────────────
  // §7 — validation: longitude range
  // ─────────────────────────────────────────────
  group('validation: longitude range', () {
    test('rejects longitude > 180', () {
      expect(
        () => SensorData.fromJson({...sampleJson, 'longitude': 180.001}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('-180'),
          ),
        ),
      );
    });

    test('rejects longitude < -180', () {
      expect(
        () => SensorData.fromJson({...sampleJson, 'longitude': -180.001}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts longitude at -180 boundary', () {
      final data = SensorData.fromJson({...sampleJson, 'longitude': -180.0});
      expect(data.longitude, -180.0);
    });

    test('accepts longitude at +180 boundary', () {
      final data = SensorData.fromJson({...sampleJson, 'longitude': 180.0});
      expect(data.longitude, 180.0);
    });
  });

  // ─────────────────────────────────────────────
  // §8 — validation: gnss_accuracy range
  // ─────────────────────────────────────────────
  group('validation: gnss_accuracy range', () {
    test('rejects negative gnss_accuracy', () {
      expect(
        () => SensorData.fromJson({...sampleJson, 'gnss_accuracy': -0.1}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('non-negative'),
          ),
        ),
      );
    });

    test('accepts zero gnss_accuracy', () {
      final data = SensorData.fromJson({...sampleJson, 'gnss_accuracy': 0.0});
      expect(data.gnssAccuracy, 0.0);
    });

    test('accepts large gnss_accuracy', () {
      final data = SensorData.fromJson({
        ...sampleJson,
        'gnss_accuracy': 100000.0,
      });
      expect(data.gnssAccuracy, 100000.0);
    });
  });

  // ─────────────────────────────────────────────
  // §9 — equality and hashCode
  // ─────────────────────────────────────────────
  group('equality and hashCode', () {
    test('equal objects have equal hashCodes', () {
      final a = SensorData.fromJson(sampleJson);
      final b = SensorData.fromJson(sampleJson);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different timestamps produce unequal objects', () {
      final a = SensorData.fromJson(sampleJson);
      final b = SensorData.fromJson({...sampleJson, 'timestamp': 999});

      expect(a, isNot(b));
    });

    test('different accelerometer values produce unequal objects', () {
      final a = SensorData.fromJson(sampleJson);
      final b = SensorData.fromJson({...sampleJson, 'accelerometer_x': 99.9});

      expect(a, isNot(b));
    });

    test('different gyroscope values produce unequal objects', () {
      final a = SensorData.fromJson(sampleJson);
      final b = SensorData.fromJson({...sampleJson, 'gyroscope_z': 99.9});

      expect(a, isNot(b));
    });

    test('different magnetometer values produce unequal objects', () {
      final a = SensorData.fromJson(sampleJson);
      final b = SensorData.fromJson({...sampleJson, 'magnetometer_y': 99.9});

      expect(a, isNot(b));
    });

    test('different GNSS state produces unequal objects', () {
      final a = SensorData.fromJson(sampleJson);
      final b = SensorData.fromJson(gnssUnavailableJson);

      expect(a, isNot(b));
    });

    test('GNSS-unavailable objects with same values are equal', () {
      final a = SensorData.fromJson(gnssUnavailableJson);
      final b = SensorData.fromJson(gnssUnavailableJson);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('identity equality holds', () {
      final a = SensorData.fromJson(sampleJson);
      expect(a, a);
    });

    test('not equal to non-SensorData objects', () {
      final a = SensorData.fromJson(sampleJson);
      // ignore: unrelated_type_equality_checks
      expect(a == 'not a sensor', isFalse);
    });
  });

  // ─────────────────────────────────────────────
  // §10 — toString
  // ─────────────────────────────────────────────
  group('toString', () {
    test('contains SensorData prefix', () {
      final data = SensorData.fromJson(sampleJson);
      expect(data.toString(), startsWith('SensorData('));
    });

    test('includes key values', () {
      final data = SensorData.fromJson(sampleJson);
      final str = data.toString();

      expect(str, contains('timestamp: 1725552000123'));
      expect(str, contains('m/s²'));
      expect(str, contains('rad/s'));
      expect(str, contains('µT'));
    });
  });

  // ─────────────────────────────────────────────
  // §11 — fromJson: type casting errors
  // ─────────────────────────────────────────────
  group('fromJson: type errors', () {
    test('throws on missing timestamp key', () {
      final json = Map<String, dynamic>.from(sampleJson)..remove('timestamp');
      expect(() => SensorData.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws on string timestamp', () {
      final json = {...sampleJson, 'timestamp': '1725552000123'};
      expect(() => SensorData.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws on null required sensor field', () {
      final json = {...sampleJson, 'accelerometer_x': null};
      expect(() => SensorData.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws on string gnss_available', () {
      final json = {...sampleJson, 'gnss_available': 'true'};
      expect(() => SensorData.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('throws on missing gnss_available key', () {
      final json = Map<String, dynamic>.from(sampleJson)
        ..remove('gnss_available');
      expect(() => SensorData.fromJson(json), throwsA(isA<TypeError>()));
    });
  });

  // ─────────────────────────────────────────────
  // §12 — edge cases: extreme sensor values
  // ─────────────────────────────────────────────
  group('edge cases: extreme values', () {
    test('accepts very large sensor values', () {
      final json = {
        ...sampleJson,
        'accelerometer_x': 1e10,
        'gyroscope_x': 1e10,
        'magnetometer_x': 1e10,
      };
      final data = SensorData.fromJson(json);

      expect(data.accelerometerX, 1e10);
      expect(data.gyroscopeX, 1e10);
      expect(data.magnetometerX, 1e10);
    });

    test('accepts zero for all sensor axes', () {
      final json = {
        'timestamp': 1725552000123,
        'accelerometer_x': 0.0,
        'accelerometer_y': 0.0,
        'accelerometer_z': 0.0,
        'gyroscope_x': 0.0,
        'gyroscope_y': 0.0,
        'gyroscope_z': 0.0,
        'magnetometer_x': 0.0,
        'magnetometer_y': 0.0,
        'magnetometer_z': 0.0,
        'latitude': 0.0,
        'longitude': 0.0,
        'gnss_accuracy': 0.0,
        'gnss_available': true,
      };
      final data = SensorData.fromJson(json);

      expect(data.accelerometerX, 0.0);
      expect(data.gyroscopeZ, 0.0);
      expect(data.magnetometerY, 0.0);
      expect(data.latitude, 0.0);
      expect(data.longitude, 0.0);
    });

    test('accepts large timestamp', () {
      // Year 2100+ timestamp
      final json = {...sampleJson, 'timestamp': 4102444800000};
      final data = SensorData.fromJson(json);

      expect(data.timestamp, 4102444800000);
    });
  });

  // ─────────────────────────────────────────────
  // §13 — constructor: direct instantiation
  // ─────────────────────────────────────────────
  group('constructor', () {
    test('creates GNSS-available instance via constructor', () {
      final data = SensorData(
        timestamp: 1725552000123,
        accelerometerX: 0.12,
        accelerometerY: 0.35,
        accelerometerZ: 9.78,
        gyroscopeX: 0.002,
        gyroscopeY: -0.003,
        gyroscopeZ: 0.015,
        magnetometerX: 21.4,
        magnetometerY: -5.8,
        magnetometerZ: -38.2,
        latitude: 18.5204,
        longitude: 73.8567,
        gnssAccuracy: 6.5,
        gnssAvailable: true,
      );

      expect(data.timestamp, 1725552000123);
      expect(data.gnssAvailable, isTrue);
      expect(data.latitude, 18.5204);
    });

    test('creates GNSS-unavailable instance via constructor', () {
      final data = SensorData(
        timestamp: 1725552000123,
        accelerometerX: 0.12,
        accelerometerY: 0.35,
        accelerometerZ: 9.78,
        gyroscopeX: 0.002,
        gyroscopeY: -0.003,
        gyroscopeZ: 0.015,
        magnetometerX: 21.4,
        magnetometerY: -5.8,
        magnetometerZ: -38.2,
        latitude: null,
        longitude: null,
        gnssAccuracy: null,
        gnssAvailable: false,
      );

      expect(data.gnssAvailable, isFalse);
      expect(data.latitude, isNull);
      expect(data.longitude, isNull);
      expect(data.gnssAccuracy, isNull);
    });
  });
}
