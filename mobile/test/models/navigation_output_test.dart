import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/navigation_output.dart';

void main() {
  // ── Sample data equivalent to integration/interfaces/sample_data/navigation_output.json ──
  final Map<String, dynamic> sampleJson = {
    'timestamp': 1725552000123,
    'latitude': 18.52041,
    'longitude': 73.85672,
    'speed': 11.1,
    'heading': 87.5,
    'navigation_mode': 'GNSS_INS',
    'gnss_status': 'AVAILABLE',
    'position_error': null,
  };

  group('NavigationOutput.fromJson', () {
    test('parses canonical sample data correctly', () {
      final output = NavigationOutput.fromJson(sampleJson);

      expect(output.timestamp, 1725552000123);
      expect(output.latitude, 18.52041);
      expect(output.longitude, 73.85672);
      expect(output.speedMps, 11.1);
      expect(output.heading, 87.5);
      expect(output.navigationMode, NavigationMode.gnssIns);
      expect(output.gnssStatus, GnssStatus.available);
      expect(output.positionError, isNull);
    });

    test('parses DEAD_RECKONING mode and UNAVAILABLE gnss_status', () {
      final json = {
        ...sampleJson,
        'navigation_mode': 'DEAD_RECKONING',
        'gnss_status': 'UNAVAILABLE',
      };
      final output = NavigationOutput.fromJson(json);

      expect(output.navigationMode, NavigationMode.deadReckoning);
      expect(output.gnssStatus, GnssStatus.unavailable);
    });

    test('parses numeric position_error', () {
      final json = {...sampleJson, 'position_error': 5.3};
      final output = NavigationOutput.fromJson(json);

      expect(output.positionError, 5.3);
    });

    test('handles null position_error', () {
      final json = {...sampleJson, 'position_error': null};
      final output = NavigationOutput.fromJson(json);

      expect(output.positionError, isNull);
    });

    test('handles omitted position_error key', () {
      final json = Map<String, dynamic>.from(sampleJson)
        ..remove('position_error');
      final output = NavigationOutput.fromJson(json);

      expect(output.positionError, isNull);
    });

    test('parses integer speed as double', () {
      final json = {...sampleJson, 'speed': 10};
      final output = NavigationOutput.fromJson(json);

      expect(output.speedMps, 10.0);
      expect(output.speedMps, isA<double>());
    });
  });

  group('NavigationOutput.toJson', () {
    test('produces exact canonical keys and values', () {
      final output = NavigationOutput.fromJson(sampleJson);
      final json = output.toJson();

      expect(json['timestamp'], 1725552000123);
      expect(json['latitude'], 18.52041);
      expect(json['longitude'], 73.85672);
      expect(json['speed'], 11.1);
      expect(json['heading'], 87.5);
      expect(json['navigation_mode'], 'GNSS_INS');
      expect(json['gnss_status'], 'AVAILABLE');
      expect(json.containsKey('position_error'), isTrue);
      expect(json['position_error'], isNull);
    });

    test('round-trips through fromJson/toJson', () {
      final original = NavigationOutput.fromJson(sampleJson);
      final roundTripped = NavigationOutput.fromJson(original.toJson());

      expect(roundTripped, original);
    });

    test('serializes DEAD_RECKONING and UNAVAILABLE correctly', () {
      final output = NavigationOutput(
        timestamp: 1725552000123,
        latitude: 18.52041,
        longitude: 73.85672,
        speedMps: 8.5,
        heading: 270.0,
        navigationMode: NavigationMode.deadReckoning,
        gnssStatus: GnssStatus.unavailable,
        positionError: 12.7,
      );
      final json = output.toJson();

      expect(json['navigation_mode'], 'DEAD_RECKONING');
      expect(json['gnss_status'], 'UNAVAILABLE');
      expect(json['position_error'], 12.7);
    });

    test('serializes speed as m/s under key "speed"', () {
      final output = NavigationOutput.fromJson(sampleJson);
      final json = output.toJson();

      // Internal field is speedMps but JSON key is "speed"
      expect(json.containsKey('speed'), isTrue);
      expect(json.containsKey('speedMps'), isFalse);
      expect(json['speed'], 11.1);
    });
  });

  group('speedKmh getter', () {
    test('converts m/s to km/h correctly', () {
      final output = NavigationOutput.fromJson(sampleJson);

      // 11.1 m/s * 3.6 = 39.96 km/h
      expect(output.speedKmh, closeTo(39.96, 0.001));
    });

    test('zero speed converts to zero km/h', () {
      final json = {...sampleJson, 'speed': 0.0};
      final output = NavigationOutput.fromJson(json);

      expect(output.speedKmh, 0.0);
    });
  });

  group('NavigationMode enum', () {
    test('serializes gnssIns to GNSS_INS', () {
      expect(NavigationMode.gnssIns.toJson(), 'GNSS_INS');
    });

    test('serializes deadReckoning to DEAD_RECKONING', () {
      expect(NavigationMode.deadReckoning.toJson(), 'DEAD_RECKONING');
    });

    test('parses GNSS_INS', () {
      expect(NavigationMode.fromJson('GNSS_INS'), NavigationMode.gnssIns);
    });

    test('parses DEAD_RECKONING', () {
      expect(
        NavigationMode.fromJson('DEAD_RECKONING'),
        NavigationMode.deadReckoning,
      );
    });

    test('throws FormatException on invalid string', () {
      expect(
        () => NavigationMode.fromJson('INVALID_MODE'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Invalid NavigationMode'),
          ),
        ),
      );
    });

    test('throws FormatException on lowercase variant', () {
      expect(
        () => NavigationMode.fromJson('gnss_ins'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('GnssStatus enum', () {
    test('serializes available to AVAILABLE', () {
      expect(GnssStatus.available.toJson(), 'AVAILABLE');
    });

    test('serializes unavailable to UNAVAILABLE', () {
      expect(GnssStatus.unavailable.toJson(), 'UNAVAILABLE');
    });

    test('parses AVAILABLE', () {
      expect(GnssStatus.fromJson('AVAILABLE'), GnssStatus.available);
    });

    test('parses UNAVAILABLE', () {
      expect(GnssStatus.fromJson('UNAVAILABLE'), GnssStatus.unavailable);
    });

    test('throws FormatException on invalid string', () {
      expect(
        () => GnssStatus.fromJson('LOST'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Invalid GnssStatus'),
          ),
        ),
      );
    });

    test('throws FormatException on empty string', () {
      expect(() => GnssStatus.fromJson(''), throwsA(isA<FormatException>()));
    });
  });

  group('equality and hashCode', () {
    test('equal objects have equal hashCodes', () {
      final a = NavigationOutput.fromJson(sampleJson);
      final b = NavigationOutput.fromJson(sampleJson);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different objects are not equal', () {
      final a = NavigationOutput.fromJson(sampleJson);
      final b = NavigationOutput.fromJson({...sampleJson, 'heading': 90.0});

      expect(a, isNot(b));
    });
  });
}
