"""Synthetic orchestration tests; no measured vehicle performance claims."""

from dataclasses import FrozenInstanceError
import unittest
from unittest.mock import patch

from navigation_engine.dead_reckoning.dead_reckoning import propagate_position
from navigation_engine.gnss.gnss_availability import detect_gnss_availability
from navigation_engine.mode_switching import mode_switching as module
from navigation_engine.mode_switching.mode_switching import NavigationModeController, NavigationModeResult


class ModeSwitchingTests(unittest.TestCase):
    def setUp(self):
        self.controller = NavigationModeController()

    def initialize(self):
        return self.controller.update("AVAILABLE", 18.5204, 73.8567)

    def loss(self, **changes):
        args = dict(speed_mps=10, heading_deg=90, elapsed_time_s=1)
        args.update(changes)
        return self.controller.update("UNAVAILABLE", **args)

    def test_initial_state(self):
        self.assertIsNone(self.controller.state)
        self.assertFalse(self.controller.initialized)

    def test_available_initializes_and_uses_exact_fix(self):
        result = self.initialize()
        self.assertEqual(result, NavigationModeResult(18.5204, 73.8567, "GNSS_INS", "AVAILABLE"))
        self.assertTrue(self.controller.initialized)
        self.assertIs(self.controller.state, result)

    def test_unavailable_before_initialization(self):
        with patch.object(module, "propagate_position", wraps=propagate_position) as dr:
            with self.assertRaisesRegex(ValueError, "not initialized"):
                self.loss()
            dr.assert_not_called()
        self.assertFalse(self.controller.initialized)
        self.assertIsNone(self.controller.state)

    def test_full_loss_and_recovery_sequence(self):
        first = self.initialize()
        second = self.loss()
        third = self.loss()
        recovered = self.controller.update("AVAILABLE", 18.5205, 73.8570)
        self.assertEqual([r.navigation_mode for r in (first, second, third, recovered)],
                         ["GNSS_INS", "DEAD_RECKONING", "DEAD_RECKONING", "GNSS_INS"])
        self.assertEqual([r.gnss_status for r in (first, second, third, recovered)],
                         ["AVAILABLE", "UNAVAILABLE", "UNAVAILABLE", "AVAILABLE"])
        self.assertGreater(second.longitude, first.longitude)
        self.assertGreater(third.longitude, second.longitude)
        self.assertEqual((recovered.latitude, recovered.longitude), (18.5205, 73.8570))
        self.assertIs(self.controller.state, recovered)

    def test_dr_reuses_existing_function_and_previous_position(self):
        first = self.initialize()
        self.assertIs(module.propagate_position, propagate_position)
        with patch.object(module, "propagate_position", wraps=propagate_position) as dr:
            second = self.loss()
            dr.assert_called_once_with(first.latitude, first.longitude, 10, 90, 1)
            self.loss()
            self.assertEqual(dr.call_count, 2)
            dr.assert_called_with(second.latitude, second.longitude, 10, 90, 1)

    def test_loss_after_recovery_uses_recovered_position(self):
        self.initialize()
        self.loss()
        self.controller.update("AVAILABLE", -33, -70)
        with patch.object(module, "propagate_position", wraps=propagate_position) as dr:
            self.loss()
            dr.assert_called_once_with(-33.0, -70.0, 10, 90, 1)

    def test_available_ignores_dr_parameters_and_never_calls_dr(self):
        with patch.object(module, "propagate_position", wraps=propagate_position) as dr:
            self.controller.update("AVAILABLE", 1, 2, None, None, None)
            result = self.controller.update("AVAILABLE", 3, 4, "bad", {}, -1)
            dr.assert_not_called()
        self.assertEqual((result.latitude, result.longitude), (3, 4))

    def test_unavailable_ignores_gnss_coordinates(self):
        self.initialize()
        result = self.loss(gnss_latitude="unusable", gnss_longitude={})
        self.assertEqual(result.navigation_mode, "DEAD_RECKONING")

    def test_missing_available_coordinates(self):
        for lat, lon in ((None, 1), (1, None), (None, None)):
            with self.subTest(latitude=lat, longitude=lon), self.assertRaises(ValueError):
                self.controller.update("AVAILABLE", lat, lon)
        self.assertIsNone(self.controller.state)

    def test_invalid_available_coordinates(self):
        for field, limit in (("gnss_latitude", 90), ("gnss_longitude", 180)):
            for value in (-limit-.001, limit+.001, "1", True, False, None, [], {},
                          float("nan"), float("inf"), -float("inf"), 10**400):
                with self.subTest(field=field, value=value):
                    args = dict(gnss_latitude=1, gnss_longitude=2)
                    args[field] = value
                    with self.assertRaises(ValueError):
                        self.controller.update("AVAILABLE", **args)
                    self.assertIsNone(self.controller.state)

    def test_valid_coordinate_boundaries_and_zero(self):
        for lat, lon in ((-90, -180), (90, 180), (0, 0), (-33, -70)):
            with self.subTest(latitude=lat, longitude=lon):
                result = self.controller.update("AVAILABLE", lat, lon)
                self.assertEqual((result.latitude, result.longitude), (lat, lon))

    def test_invalid_status(self):
        initial = self.initialize()
        for value in (None, "available", "UNKNOWN", "AVAILABLE ", "GNSS_INS", True, 1, [], {}):
            with self.subTest(status=value), self.assertRaises(ValueError):
                self.controller.update(value, 1, 2)
            self.assertIs(self.controller.state, initial)

    def test_invalid_dr_parameters_preserve_state(self):
        initial = self.initialize()
        for field in ("speed_mps", "heading_deg", "elapsed_time_s"):
            for value in (-1, None, "1", True, False, [], {}, float("nan"),
                          float("inf"), -float("inf"), 10**400):
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    self.loss(**{field: value})
                self.assertIs(self.controller.state, initial)
        with self.assertRaises(ValueError):
            self.loss(heading_deg=360)
        with self.assertRaises(ValueError):
            self.loss(speed_mps=1e308, elapsed_time_s=1e308)
        self.assertIs(self.controller.state, initial)

    def test_omitted_dr_parameters_fail(self):
        self.initialize()
        with self.assertRaises(ValueError):
            self.controller.update("UNAVAILABLE")

    def test_zero_speed_and_time(self):
        first = self.initialize()
        for changes in (dict(speed_mps=0), dict(elapsed_time_s=0)):
            with self.subTest(changes=changes):
                result = self.loss(**changes)
                self.assertEqual((result.latitude, result.longitude), (first.latitude, first.longitude))
                self.assertEqual(result.navigation_mode, "DEAD_RECKONING")

    def test_date_line_zero_motion_follows_dr_contract(self):
        first = self.controller.update("AVAILABLE", 0, 180)
        result = self.loss(speed_mps=0)
        self.assertEqual(first.longitude, 180)
        self.assertEqual(result.longitude, -180)

    def test_northward_motion(self):
        first = self.initialize()
        result = self.loss(heading_deg=0)
        self.assertGreater(result.latitude, first.latitude)
        self.assertAlmostEqual(result.longitude, first.longitude, delta=1e-9)

    def test_failed_recovery_preserves_dr_state(self):
        self.initialize()
        last = self.loss()
        with self.assertRaises(ValueError):
            self.controller.update("AVAILABLE", 1, None)
        self.assertIs(self.controller.state, last)
        expected = propagate_position(last.latitude, last.longitude, 10, 90, 1)
        result = self.loss()
        self.assertEqual((result.latitude, result.longitude), (expected.latitude, expected.longitude))

    def test_dr_exception_preserves_state(self):
        first = self.initialize()
        with patch.object(module, "propagate_position", side_effect=ValueError("propagation failed")):
            with self.assertRaises(ValueError):
                self.loss()
        self.assertIs(self.controller.state, first)

    def test_deterministic_sequence(self):
        def sequence():
            controller = NavigationModeController()
            return (controller.update("AVAILABLE", 18.5204, 73.8567),
                    controller.update("UNAVAILABLE", speed_mps=10, heading_deg=90, elapsed_time_s=1),
                    controller.update("UNAVAILABLE", speed_mps=10, heading_deg=90, elapsed_time_s=1),
                    controller.update("AVAILABLE", 18.5205, 73.8570))
        self.assertEqual(sequence(), sequence())

    def test_immutable_snapshot_and_read_only_properties(self):
        first = self.initialize()
        with self.assertRaises(FrozenInstanceError):
            first.latitude = 0
        with self.assertRaises(AttributeError):
            self.controller.state = None
        with self.assertRaises(AttributeError):
            self.controller.initialized = False
        self.loss()
        self.assertEqual(first, NavigationModeResult(18.5204, 73.8567, "GNSS_INS", "AVAILABLE"))

    def test_independent_controllers(self):
        self.initialize()
        other = NavigationModeController()
        self.assertFalse(other.initialized)
        other.update("AVAILABLE", 0, 0)
        self.assertEqual(self.controller.state.latitude, 18.5204)

    def test_real_issue9_status_integration(self):
        fix_time = 1725552000000
        usable = detect_gnss_availability(18.5204, 73.8567, 8, fix_time, fix_time)
        first = self.controller.update(usable.status, 18.5204, 73.8567)
        # Issue #9 alone decides the fix is stale; elapsed time spans from that fix.
        stale = detect_gnss_availability(18.5204, 73.8567, 8, fix_time, fix_time+4000)
        result = self.controller.update(stale.status, speed_mps=10, heading_deg=90, elapsed_time_s=4)
        self.assertEqual(first.navigation_mode, "GNSS_INS")
        self.assertEqual(result.navigation_mode, "DEAD_RECKONING")
        self.assertGreater(result.longitude, first.longitude)


if __name__ == "__main__":
    unittest.main()
