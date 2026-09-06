"""Synthetic propagation checks, not real sensor or performance measurements."""

import ast
from dataclasses import FrozenInstanceError
import inspect
from math import asin, atan2, cos, degrees, isfinite, radians, sin, sqrt
import sys
import unittest

from navigation_engine.dead_reckoning import dead_reckoning as module
from navigation_engine.dead_reckoning.dead_reckoning import (
    EARTH_RADIUS_M, DeadReckoningResult, propagate_position,
)


class DeadReckoningTests(unittest.TestCase):
    def propagate(self, **changes):
        args = dict(latitude=18.5204, longitude=73.8567,
                    speed_mps=10, heading_deg=0, elapsed_time_s=10)
        args.update(changes)
        return propagate_position(**args)

    def assert_valid(self, result):
        self.assertTrue(all(isfinite(v) for v in
                            (result.latitude, result.longitude, result.distance_m)))
        self.assertTrue(-90 <= result.latitude <= 90)
        self.assertTrue(-180 <= result.longitude < 180)
        self.assertGreaterEqual(result.distance_m, 0)

    def test_zero_speed(self):
        self.assertEqual(self.propagate(speed_mps=0), DeadReckoningResult(18.5204, 73.8567, 0))

    def test_zero_time(self):
        self.assertEqual(self.propagate(elapsed_time_s=0), DeadReckoningResult(18.5204, 73.8567, 0))

    def test_zero_motion_date_line_representation(self):
        for longitude in (-180, 180):
            for changes in (dict(speed_mps=0), dict(elapsed_time_s=0)):
                with self.subTest(longitude=longitude, changes=changes):
                    result = self.propagate(longitude=longitude, **changes)
                    self.assertEqual(result.longitude, -180)
                    self.assertEqual(result.latitude, 18.5204)

    def test_north(self):
        result = self.propagate(heading_deg=0)
        self.assertGreater(result.latitude, 18.5204)
        self.assertAlmostEqual(result.latitude, 18.5204 + degrees(100/EARTH_RADIUS_M), delta=1e-9)
        self.assertAlmostEqual(result.longitude, 73.8567, delta=1e-9)

    def test_east(self):
        result = self.propagate(latitude=0, heading_deg=90)
        self.assertGreater(result.longitude, 73.8567)
        self.assertAlmostEqual(result.longitude, 73.8567 + degrees(100/EARTH_RADIUS_M), delta=1e-9)
        self.assertAlmostEqual(result.latitude, 0, delta=1e-9)

    def test_south(self):
        result = self.propagate(heading_deg=180)
        self.assertLess(result.latitude, 18.5204)
        self.assertAlmostEqual(result.latitude, 18.5204 - degrees(100/EARTH_RADIUS_M), delta=1e-9)
        self.assertAlmostEqual(result.longitude, 73.8567, delta=1e-9)

    def test_west(self):
        result = self.propagate(latitude=0, heading_deg=270)
        self.assertLess(result.longitude, 73.8567)
        self.assertAlmostEqual(result.longitude, 73.8567 - degrees(100/EARTH_RADIUS_M), delta=1e-9)
        self.assertAlmostEqual(result.latitude, 0, delta=1e-9)

    def test_known_distance(self):
        self.assertEqual(self.propagate(elapsed_time_s=5).distance_m, 50)

    def test_invalid_ranges(self):
        cases = dict(latitude=(-90.001, 90.001), longitude=(-180.001, 180.001),
                     speed_mps=(-.001,), heading_deg=(-.001, 360, 720), elapsed_time_s=(-.001,))
        for field, values in cases.items():
            for value in values:
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    self.propagate(**{field: value})

    def test_invalid_types_and_nonfinite_values(self):
        for field in ("latitude", "longitude", "speed_mps", "heading_deg", "elapsed_time_s"):
            for value in ("1", True, False, None, [], {}, float("nan"),
                          float("inf"), -float("inf"), 10**400):
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    self.propagate(**{field: value})

    def test_zero_motion_still_validates(self):
        for changes in (dict(speed_mps=0, heading_deg=360),
                        dict(elapsed_time_s=0, latitude=91),
                        dict(speed_mps=0, elapsed_time_s=-1)):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.propagate(**changes)

    def test_distance_overflow(self):
        with self.assertRaises(ValueError):
            self.propagate(speed_mps=1e308, elapsed_time_s=1e308)

    def test_deterministic(self):
        self.assertEqual(self.propagate(heading_deg=37), self.propagate(heading_deg=37))

    def test_east_date_line_crossing(self):
        result = self.propagate(latitude=0, longitude=179.9999, heading_deg=90)
        self.assertLess(result.longitude, -179.99)
        self.assert_valid(result)

    def test_west_date_line_crossing(self):
        result = self.propagate(latitude=0, longitude=-179.9999, heading_deg=270)
        self.assertGreater(result.longitude, 179.99)
        self.assert_valid(result)

    def test_high_latitudes(self):
        for latitude in (-89, 89, -89.999, 89.999, -90, 90):
            for heading in (0, 90, 180, 270):
                with self.subTest(latitude=latitude, heading=heading):
                    self.assert_valid(self.propagate(latitude=latitude, heading_deg=heading))

    def test_arbitrary_heading_inverse_distance_and_bearing(self):
        # Independent inverse haversine/bearing checks, not destination-formula duplication.
        for latitude, longitude, heading in ((18.5204, 73.8567, 37), (-33, -70, 213), (0, 0, 125)):
            with self.subTest(latitude=latitude, longitude=longitude, heading=heading):
                result = self.propagate(latitude=latitude, longitude=longitude, heading_deg=heading)
                lat1, lat2 = radians(latitude), radians(result.latitude)
                dlat, dlon = lat2-lat1, radians(result.longitude-longitude)
                h = sin(dlat/2)**2 + cos(lat1)*cos(lat2)*sin(dlon/2)**2
                recovered_distance = 2*EARTH_RADIUS_M*asin(sqrt(h))
                recovered_bearing = degrees(atan2(sin(dlon)*cos(lat2),
                    cos(lat1)*sin(lat2)-sin(lat1)*cos(lat2)*cos(dlon))) % 360
                self.assertAlmostEqual(recovered_distance, 100, delta=1e-6)
                self.assertAlmostEqual(recovered_bearing, heading, delta=1e-7)

    def test_very_small_time_step(self):
        result = self.propagate(latitude=0, longitude=0, elapsed_time_s=1e-6)
        self.assertAlmostEqual(result.distance_m, 1e-5, delta=1e-18)
        self.assertGreater(result.latitude, 0)
        self.assertAlmostEqual(result.latitude, degrees(1e-5/EARTH_RADIUS_M), delta=1e-15)

    def test_large_reasonable_time_step(self):
        result = self.propagate(latitude=0, longitude=0, speed_mps=20, elapsed_time_s=300)
        self.assertEqual(result.distance_m, 6000)
        self.assertAlmostEqual(result.latitude, degrees(6000/EARTH_RADIUS_M), delta=1e-9)

    def test_repeated_updates(self):
        first = self.propagate(elapsed_time_s=1)
        second = self.propagate(latitude=first.latitude, longitude=first.longitude, elapsed_time_s=1)
        combined = self.propagate(elapsed_time_s=2)
        self.assertGreater(second.latitude, first.latitude)
        self.assertAlmostEqual(second.latitude, combined.latitude, delta=1e-9)
        self.assertAlmostEqual(second.longitude, combined.longitude, delta=1e-9)
        self.assertEqual(second.distance_m, 10)  # Per step, not cumulative state.

    def test_coordinate_ranges_and_valid_boundaries(self):
        for latitude in (-90, -45, 0, 45, 90):
            for longitude in (-180, -90, 0, 90, 180):
                for heading in (0, 123, 359.999):
                    with self.subTest(latitude=latitude, longitude=longitude, heading=heading):
                        self.assert_valid(self.propagate(latitude=latitude, longitude=longitude,
                                                        heading_deg=heading))

    def test_input_unchanged(self):
        args = dict(latitude=18.5204, longitude=73.8567, speed_mps=10,
                    heading_deg=37, elapsed_time_s=5)
        original = args.copy()
        propagate_position(**args)
        self.assertEqual(args, original)

    def test_result_immutable(self):
        result = self.propagate()
        with self.assertRaises(FrozenInstanceError):
            result.latitude = 0

    def test_only_standard_library_imports(self):
        tree = ast.parse(inspect.getsource(module))
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom):
                self.assertEqual(node.level, 0)
                self.assertIn(node.module.split('.')[0], sys.stdlib_module_names)
            elif isinstance(node, ast.Import):
                for alias in node.names:
                    self.assertIn(alias.name.split('.')[0], sys.stdlib_module_names)


if __name__ == "__main__":
    unittest.main()
