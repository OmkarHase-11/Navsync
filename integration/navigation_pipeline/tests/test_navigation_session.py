import math
import unittest
from unittest.mock import patch

from integration.navigation_pipeline.navigation_session import NavigationSession


def request(timestamp, available=True, lat=0, lon=0, speed=10, heading=90):
    return dict(operation='update', gnss_prevalidated=True,
        sensor=dict(timestamp=timestamp, gnss_available=available,
            latitude=lat if available else None, longitude=lon if available else None,
            gnss_accuracy=5 if available else None,
            **{f'{name}_{axis}': float(i + 1) for name in
               ('accelerometer', 'gyroscope', 'magnetometer') for i, axis in enumerate('xyz')}),
        motion=dict(timestamp=timestamp, speed_mps=speed, heading_deg=heading,
                    stationary_override=False))


class SessionTests(unittest.TestCase):
    def test_default_allows_long_intervals_with_explicit_seconds_conversion(self):
        session = NavigationSession()
        session.handle(request(1700000000000))
        result = session.handle(request(1700000010000, False))['raw']
        self.assertAlmostEqual(math.radians(result['longitude']) * 6371000, 100, places=6)
        result = session.handle(request(1700000015000, False))['raw']
        self.assertAlmostEqual(math.radians(result['longitude']) * 6371000, 150, places=6)
        self.assertEqual(result['timestamp'], 1700000015000)
        self.assertEqual(result['navigation_mode'], 'DEAD_RECKONING')

    def test_optional_gap_configuration(self):
        self.assertIsNone(NavigationSession().max_gap_ms)
        for value in [0, -1, True, 2.5, float('inf')]:
            with self.assertRaises(ValueError):
                NavigationSession(max_gap_ms=value)

    def test_first_gnss_and_outage_recovery(self):
        session = NavigationSession()
        first = session.handle(request(1700000000000))['raw']
        self.assertEqual(first['navigation_mode'], 'GNSS_INS')
        self.assertEqual(first['latitude'], 0)
        second = session.handle(request(1700000001000, False))['raw']
        third = session.handle(request(1700000002000, False))['raw']
        self.assertEqual(second['navigation_mode'], 'DEAD_RECKONING')
        self.assertEqual(third['gnss_status'], 'UNAVAILABLE')
        self.assertAlmostEqual(math.radians(third['longitude']) * 6371000, 20, places=6)
        recovery = session.handle(request(1700000003000, lat=1, lon=2))['raw']
        self.assertEqual((recovery['latitude'], recovery['longitude']), (1, 2))
        self.assertEqual(recovery['gnss_status'], 'AVAILABLE')
        after = session.handle(request(1700000004000, False))['raw']
        self.assertGreater(after['longitude'], 2)

    def test_uninitialized_outage(self):
        with self.assertRaisesRegex(ValueError, 'first valid GNSS'):
            NavigationSession().handle(request(1000, False))

    def test_invalid_time_and_motion_are_atomic(self):
        session = NavigationSession()
        session.handle(request(1000))
        for timestamp in [1000, 999, -1, True, 1000.5]:
            with self.assertRaises(ValueError):
                session.handle(request(timestamp, False))
            self.assertEqual(session.last_timestamp, 1000)
        for speed in [-1, float('nan'), float('inf'), True, '10']:
            with self.assertRaises(ValueError):
                session.handle(request(2000, False, speed=speed))
            self.assertEqual(session.last_timestamp, 1000)

    def test_large_gap_requires_reanchor(self):
        session = NavigationSession(max_gap_ms=1000)
        session.handle(request(1000))
        with self.assertRaisesRegex(ValueError, 'gap too large'):
            session.handle(request(3000, False))
        session.handle(request(4000, lat=3, lon=4))
        self.assertEqual(session.handle(request(5000, False))['raw']['timestamp'], 5000)

    def test_stationary_and_maximum_reuse(self):
        session = NavigationSession(max_speed_mps=20)
        session.handle(request(1000))
        row = request(2000, False, speed=12)
        row['motion']['stationary_override'] = True
        result = session.handle(row)
        self.assertEqual(result['raw']['longitude'], 0)
        self.assertEqual(result['raw']['speed'], 0)
        self.assertEqual(result['raw_speed_mps'], 12)
        row = request(3000, False, speed=30)
        row['motion']['stationary_override'] = True
        with self.assertRaises(ValueError):
            session.handle(row)

    def test_fix_freshness_accuracy_and_prevalidation(self):
        session = NavigationSession()
        row = request(5000)
        row['fix_timestamp_ms'] = 1000
        with self.assertRaisesRegex(ValueError, 'first valid GNSS'):
            session.handle(row)
        row['fix_timestamp_ms'] = 5000
        row['sensor']['gnss_accuracy'] = 31
        with self.assertRaises(ValueError):
            session.handle(row)
        row = request(5000)
        row.pop('gnss_prevalidated')
        with self.assertRaisesRegex(ValueError, 'validation required'):
            session.handle(row)

    def test_alignment_is_explicit_and_uses_existing_module(self):
        session = NavigationSession()
        row = request(1000)
        row['mount_radians'] = [0, 0, math.pi / 2]
        result = session.handle(row)
        self.assertAlmostEqual(result['aligned_imu']['accelerometer']['x'], -2)
        self.assertAlmostEqual(result['aligned_imu']['accelerometer']['y'], 1)
        self.assertEqual(result['raw_speed_mps'], 10)
        self.assertIsNone(session.handle(request(2000))['aligned_imu'])

    def test_reset_clears_trip(self):
        session = NavigationSession()
        session.handle(request(5000))
        self.assertEqual(session.handle({'operation': 'reset'}), {'reset': True})
        self.assertIsNone(session.last_timestamp)
        with self.assertRaises(ValueError):
            session.handle(request(1000, False))
        session.handle(request(1000))

    def test_motion_epoch_must_match(self):
        row = request(1000)
        row['motion']['timestamp'] = 0
        with self.assertRaises(ValueError):
            NavigationSession().handle(row)

    def test_existing_dr_and_switch_apis_are_called(self):
        session = NavigationSession()
        session.handle(request(1000))
        from integration.ai_dead_reckoning.ai_dead_reckoning import AISpeedDeadReckoningIntegrator
        from navigation_engine.mode_switching.mode_switching import NavigationModeController
        with patch.object(AISpeedDeadReckoningIntegrator, 'update', autospec=True,
                          side_effect=AISpeedDeadReckoningIntegrator.update) as dr, \
             patch.object(NavigationModeController, 'update', autospec=True,
                          side_effect=NavigationModeController.update) as switch:
            session.handle(request(2000, False))
            self.assertEqual(dr.call_count, 2)  # validation + actual sequential DR
            self.assertEqual(switch.call_count, 1)


if __name__ == '__main__':
    unittest.main()
