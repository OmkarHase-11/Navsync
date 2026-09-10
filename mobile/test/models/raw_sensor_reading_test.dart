import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/raw_sensor_reading.dart';

void main() {
  group('TimestampedVector3', () {
    test('constructs with valid parameters', () {
      final v = TimestampedVector3(
        timestamp: 1725552000123,
        x: 0.12,
        y: 0.35,
        z: 9.78,
      );

      expect(v.timestamp, 1725552000123);
      expect(v.x, 0.12);
      expect(v.y, 0.35);
      expect(v.z, 9.78);
    });

    test('rejects negative timestamp', () {
      expect(
        () => TimestampedVector3(timestamp: -1, x: 0, y: 0, z: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts zero timestamp', () {
      final v = TimestampedVector3(timestamp: 0, x: 0, y: 0, z: 0);
      expect(v.timestamp, 0);
    });

    test('rejects NaN on any axis', () {
      expect(
        () => TimestampedVector3(timestamp: 100, x: double.nan, y: 0, z: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => TimestampedVector3(timestamp: 100, x: 0, y: double.nan, z: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => TimestampedVector3(timestamp: 100, x: 0, y: 0, z: double.nan),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects infinity on any axis', () {
      expect(
        () =>
            TimestampedVector3(timestamp: 100, x: double.infinity, y: 0, z: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => TimestampedVector3(
          timestamp: 100,
          x: 0,
          y: double.negativeInfinity,
          z: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('implements value equality and hashCode', () {
      final a = TimestampedVector3(timestamp: 100, x: 1.0, y: 2.0, z: 3.0);
      final b = TimestampedVector3(timestamp: 100, x: 1.0, y: 2.0, z: 3.0);
      final c = TimestampedVector3(timestamp: 101, x: 1.0, y: 2.0, z: 3.0);
      final d = TimestampedVector3(timestamp: 100, x: 1.1, y: 2.0, z: 3.0);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
    });

    test('provides meaningful toString', () {
      final v = TimestampedVector3(timestamp: 100, x: 1.0, y: 2.0, z: 3.0);
      expect(v.toString(), contains('TimestampedVector3'));
      expect(v.toString(), contains('ts: 100'));
      expect(v.toString(), contains('x: 1.0'));
    });
  });

  group('GnssReading', () {
    test('constructs with valid parameters', () {
      final r = GnssReading(
        timestamp: 1725552000123,
        latitude: 18.5204,
        longitude: 73.8567,
        accuracy: 4.5,
      );

      expect(r.timestamp, 1725552000123);
      expect(r.latitude, 18.5204);
      expect(r.longitude, 73.8567);
      expect(r.accuracy, 4.5);
    });

    test('rejects negative timestamp', () {
      expect(
        () =>
            GnssReading(timestamp: -1, latitude: 0, longitude: 0, accuracy: 5),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects latitude outside [-90, 90]', () {
      expect(
        () => GnssReading(
          timestamp: 100,
          latitude: 90.1,
          longitude: 0,
          accuracy: 5,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => GnssReading(
          timestamp: 100,
          latitude: -90.1,
          longitude: 0,
          accuracy: 5,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts boundary latitude values (-90 and +90)', () {
      final neg = GnssReading(
        timestamp: 100,
        latitude: -90.0,
        longitude: 0,
        accuracy: 1,
      );
      final pos = GnssReading(
        timestamp: 100,
        latitude: 90.0,
        longitude: 0,
        accuracy: 1,
      );
      expect(neg.latitude, -90.0);
      expect(pos.latitude, 90.0);
    });

    test('rejects longitude outside [-180, 180]', () {
      expect(
        () => GnssReading(
          timestamp: 100,
          latitude: 0,
          longitude: 180.1,
          accuracy: 5,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => GnssReading(
          timestamp: 100,
          latitude: 0,
          longitude: -180.1,
          accuracy: 5,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts boundary longitude values (-180 and +180)', () {
      final neg = GnssReading(
        timestamp: 100,
        latitude: 0,
        longitude: -180.0,
        accuracy: 1,
      );
      final pos = GnssReading(
        timestamp: 100,
        latitude: 0,
        longitude: 180.0,
        accuracy: 1,
      );
      expect(neg.longitude, -180.0);
      expect(pos.longitude, 180.0);
    });

    test('rejects negative accuracy', () {
      expect(
        () => GnssReading(
          timestamp: 100,
          latitude: 0,
          longitude: 0,
          accuracy: -0.1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts zero accuracy', () {
      final r = GnssReading(
        timestamp: 100,
        latitude: 0,
        longitude: 0,
        accuracy: 0.0,
      );
      expect(r.accuracy, 0.0);
    });

    test('rejects NaN or infinity', () {
      expect(
        () => GnssReading(
          timestamp: 100,
          latitude: double.nan,
          longitude: 0,
          accuracy: 5,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => GnssReading(
          timestamp: 100,
          latitude: 0,
          longitude: double.infinity,
          accuracy: 5,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => GnssReading(
          timestamp: 100,
          latitude: 0,
          longitude: 0,
          accuracy: double.infinity,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('implements value equality and hashCode', () {
      final a = GnssReading(
        timestamp: 100,
        latitude: 18.5,
        longitude: 73.8,
        accuracy: 5.0,
      );
      final b = GnssReading(
        timestamp: 100,
        latitude: 18.5,
        longitude: 73.8,
        accuracy: 5.0,
      );
      final c = GnssReading(
        timestamp: 100,
        latitude: 18.6,
        longitude: 73.8,
        accuracy: 5.0,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('provides formatted toString', () {
      final r = GnssReading(
        timestamp: 100,
        latitude: 18.52043,
        longitude: 73.85674,
        accuracy: 4.52,
      );
      final str = r.toString();
      expect(str, contains('GnssReading'));
      expect(str, contains('18.5204'));
      expect(str, contains('73.8567'));
      expect(str, contains('4.5m'));
    });
  });

  group('Enums and Error models', () {
    test('GnssAccessStatus has all expected states', () {
      expect(
        GnssAccessStatus.values,
        containsAll([
          GnssAccessStatus.unknown,
          GnssAccessStatus.checking,
          GnssAccessStatus.ready,
          GnssAccessStatus.servicesDisabled,
          GnssAccessStatus.permissionDenied,
          GnssAccessStatus.permissionDeniedForever,
          GnssAccessStatus.error,
        ]),
      );
    });

    test('SensorSource has all expected sources', () {
      expect(
        SensorSource.values,
        containsAll([
          SensorSource.accelerometer,
          SensorSource.gyroscope,
          SensorSource.magnetometer,
          SensorSource.gnss,
        ]),
      );
    });

    test('SensorCollectionError captures source and error details', () {
      final err = SensorCollectionError(
        source: SensorSource.accelerometer,
        error: 'Sensor unavailable',
      );
      expect(err.source, SensorSource.accelerometer);
      expect(err.error, 'Sensor unavailable');
      expect(err.stackTrace, isNull);
      expect(err.toString(), contains('accelerometer'));
      expect(err.toString(), contains('Sensor unavailable'));
    });
  });
}
