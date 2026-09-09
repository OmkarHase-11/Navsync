import math
import unittest
from dataclasses import FrozenInstanceError
from unittest.mock import patch

from integration.ai_dead_reckoning import ai_dead_reckoning as api
from navigation_engine.dead_reckoning.dead_reckoning import EARTH_RADIUS_M, propagate_position


class IntegrationTests(unittest.TestCase):
    def initialized(self, **kwargs):
        obj = api.AISpeedDeadReckoningIntegrator(**kwargs)
        obj.initialize(0, 0, 90, 0)
        return obj

    def test_initialization_reset_and_immutable_state(self):
        obj = api.AISpeedDeadReckoningIntegrator()
        self.assertFalse(obj.initialized)
        with self.assertRaises(ValueError):
            obj.update(1, 10)
        state = obj.initialize(0, 180, 0, -1)
        self.assertEqual(state.longitude, -180)
        with self.assertRaises(FrozenInstanceError):
            state.latitude = 1
        obj.reset()
        self.assertIsNone(obj.state)
        with self.assertRaises(ValueError):
            obj.update(1, 10)

    def test_invalid_initialization_is_atomic(self):
        obj = self.initialized()
        before = obj.state
        for index, values in enumerate(([91, -91, True], [181, -181, '0'],
                                       [-1, 360, float('nan')], [True, '0', float('inf')])):
            for value in values:
                args = [0, 0, 90, 0]
                args[index] = value
                with self.subTest(index=index, value=value), self.assertRaises(ValueError):
                    obj.initialize(*args)
                self.assertEqual(before, obj.state)

    def test_east_distance_elapsed_and_zero(self):
        obj = self.initialized()
        first = obj.update(1, 10)
        second = obj.update(2, 10)
        third = obj.update(3, 0)
        self.assertAlmostEqual(math.radians(second['longitude']) * EARTH_RADIUS_M, 20, places=6)
        self.assertAlmostEqual(first['latitude'], 0)
        self.assertEqual(second['longitude'], third['longitude'])
        self.assertEqual(third['metadata']['elapsed_time_s'], 1)
        self.assertEqual(obj.state.timestamp, 3)

    def test_north_and_heading_reuse(self):
        obj = self.initialized()
        first = obj.update(2, 5, heading_deg=0)
        second = obj.update(4, 5)
        self.assertAlmostEqual(math.radians(second['latitude']) * EARTH_RADIUS_M, 20, places=6)
        self.assertEqual(first['heading'], 0)
        self.assertEqual(second['longitude'], 0)
        third = obj.update(5, 5, heading_deg=90)
        self.assertGreater(third['longitude'], 0)
        self.assertEqual(obj.state.heading_deg, 90)

    def test_bad_timing_preserves_state(self):
        obj = self.initialized()
        for value in [0, -1, float('nan'), float('inf'), True, '1', None, 10**400]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                obj.update(value, 10, heading_deg=0)
            self.assertEqual(obj.state.timestamp, 0)
            self.assertEqual(obj.state.heading_deg, 90)

    def test_elapsed_and_distance_overflow_preserve_state(self):
        obj = self.initialized()
        obj.initialize(0, 0, 0, -1e308)
        before = obj.state
        with self.assertRaises(ValueError):
            obj.update(1e308, 1)
        self.assertEqual(obj.state, before)
        obj.initialize(0, 0, 0, 0)
        before = obj.state
        with self.assertRaises(ValueError):
            obj.update(1e308, 1e308)
        self.assertEqual(obj.state, before)

    def test_invalid_speed_even_with_override(self):
        obj = self.initialized()
        before = obj.state
        for value in [-1, float('nan'), float('inf'), True, '10', None, [], 10**400]:
            for override in [False, True]:
                with self.subTest(value=value, override=override), self.assertRaises(ValueError):
                    obj.update(1, value, stationary_override=override)
                self.assertEqual(obj.state, before)

    def test_maximum_configuration(self):
        for value in [0, -1, True, '20', float('inf'), float('nan')]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                api.AISpeedDeadReckoningIntegrator(max_speed_mps=value)
        self.initialized().update(1, 100)

    def test_maximum_rejects_before_override(self):
        obj = self.initialized(max_speed_mps=10)
        obj.update(1, 10)
        before = obj.state
        for override in [False, True]:
            with self.assertRaises(ValueError):
                obj.update(2, 11, stationary_override=override)
            self.assertEqual(obj.state, before)

    def test_stationary_metadata_and_resume(self):
        obj = self.initialized()
        result = obj.update(1, 12, stationary_override=True)
        self.assertEqual((result['latitude'], result['longitude'], result['speed']), (0, 0, 0))
        self.assertEqual(result['metadata']['raw_estimated_speed_mps'], 12)
        self.assertEqual(result['metadata']['used_speed_mps'], 0)
        self.assertTrue(result['metadata']['stationary_override_applied'])
        self.assertGreater(obj.update(2, 12)['longitude'], 0)

    def test_invalid_heading_and_override_atomic(self):
        obj = self.initialized()
        before = obj.state
        for kwargs in [dict(heading_deg=360), dict(heading_deg=True),
                       dict(heading_deg=float('inf')), dict(stationary_override=1),
                       dict(stationary_override='false')]:
            with self.assertRaises(ValueError):
                obj.update(1, 1, **kwargs)
            self.assertEqual(obj.state, before)

    def test_dr_reused_and_exception_atomic(self):
        obj = self.initialized()
        with patch.object(api, 'propagate_position', wraps=propagate_position) as dr:
            obj.update(2, 7, heading_deg=0)
            dr.assert_called_once_with(0, 0, 7, 0, 2)
        before = obj.state
        with patch.object(api, 'propagate_position', side_effect=ValueError('failure')):
            with self.assertRaises(ValueError):
                obj.update(3, 5)
        self.assertEqual(obj.state, before)

    def test_output_and_explicit_unix_boundary(self):
        obj = self.initialized()
        result = obj.update(1.25, 2)
        self.assertEqual(result['navigation_mode'], 'DEAD_RECKONING')
        self.assertEqual(result['gnss_status'], 'UNAVAILABLE')
        self.assertIsNone(result['position_error'])
        self.assertEqual(result['metadata']['speed_source'], 'AI_IMU')
        output = api.to_navigation_output(result, unix_origin_ms=1725552000000)
        self.assertEqual(output['timestamp'], 1725552001250)
        self.assertEqual(result['timestamp'], 1.25)
        self.assertNotIn('timestamp_unit', output)
        result['metadata']['used_speed_mps'] = 500
        self.assertEqual(obj.state.timestamp, 1.25)
        for origin in [True, 1.5, '0']:
            with self.assertRaises(ValueError):
                api.to_navigation_output(result, unix_origin_ms=origin)
        with self.assertRaises(ValueError):
            api.to_navigation_output(output, unix_origin_ms=0)

    def test_batch_schema_initial_delta_and_determinism(self):
        rows = [dict(time_s=10, estimated_speed=10, target_index=9, run_id='a'),
                dict(time_s=11, estimated_speed=10, target_index=10, run_id='a')]
        def run():
            return api.integrate_speed_predictions(0, 0, 90, rows, initial_timestamp=9)
        trajectory = run()
        self.assertEqual(trajectory, run())
        self.assertEqual(len(trajectory), 2)
        self.assertEqual(trajectory[0]['run_id'], 'a')
        self.assertAlmostEqual(math.radians(trajectory[-1]['longitude']) * EARTH_RADIUS_M, 20, places=6)
        self.assertEqual(rows[0]['time_s'], 10)
        with self.assertRaises(ValueError):
            api.integrate_speed_predictions(0, 0, 90, rows, initial_timestamp=10)

    def test_batch_rejects_order_runs_and_malformed_rows(self):
        cases = [[], None, [{}], [1],
                 [dict(time_s=1, estimated_speed=1), dict(time_s=1, estimated_speed=1)],
                 [dict(time_s=2, estimated_speed=1), dict(time_s=1, estimated_speed=1)],
                 [dict(time_s=1, estimated_speed=1, run_id='a'), dict(time_s=2, estimated_speed=1, run_id='b')],
                 [dict(time_s=1, estimated_speed=1, run_id=3)]]
        for rows in cases:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                api.integrate_speed_predictions(0, 0, 90, rows, initial_timestamp=0)

    def test_inference_helper_delegates_without_training(self):
        predictions = [dict(time_s=1, estimated_speed=3, run_id='x')]
        bundle, records = object(), [dict(time_s=1)]
        with patch('ai.speed_estimation.predict_from_records', return_value=predictions) as predict, \
                patch('ai.speed_estimation.train_from_pairs', side_effect=AssertionError('must not train')):
            result = api.predict_and_integrate(bundle, records, 0, 0, 90,
                                              initial_timestamp=0, run_id='x')
        predict.assert_called_once_with(bundle, records, run_id='x')
        self.assertEqual(result['predictions'], predictions)
        self.assertEqual(result['trajectory'][0]['speed'], 3)


if __name__ == '__main__':
    unittest.main()
