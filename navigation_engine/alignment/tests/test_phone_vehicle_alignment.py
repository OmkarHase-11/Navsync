"""Synthetic rotation tests; these are not real vehicle measurements."""

from dataclasses import FrozenInstanceError
import json
from math import cos, hypot, pi, sin
from pathlib import Path
import unittest

from navigation_engine.alignment.phone_vehicle_alignment import (
    Vector3, build_phone_to_vehicle_rotation, transform_phone_to_vehicle,
)


class AlignmentTests(unittest.TestCase):
    def assert_vector(self, actual, expected):
        for value, target in zip((actual.x, actual.y, actual.z), expected):
            self.assertAlmostEqual(value, target, delta=1e-9)

    def test_identity(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(1, 2, 3), 0, 0, 0), (1, 2, 3))

    def test_zero_vector(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(0, 0, 0), .3, -.7, 2), (0, 0, 0))

    def test_positive_yaw(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(1, 0, 0), 0, 0, pi/2), (0, 1, 0))

    def test_negative_yaw(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(1, 0, 0), 0, 0, -pi/2), (0, -1, 0))

    def test_positive_roll(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(0, 1, 0), pi/2, 0, 0), (0, 0, 1))

    def test_negative_roll(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(0, 1, 0), -pi/2, 0, 0), (0, 0, -1))

    def test_positive_pitch(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(1, 0, 0), 0, pi/2, 0), (0, 0, -1))

    def test_negative_pitch(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(1, 0, 0), 0, -pi/2, 0), (0, 0, 1))

    def test_half_turn(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(1, 2, 3), 0, 0, pi), (-1, -2, 3))

    def test_negative_components(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(-2, -3, -4), 0, 0, pi/2), (3, -2, -4))

    def test_composition_order(self):
        # Roll: (1,2,3)->(1,-3,2); pitch: ->(2,-3,-1); yaw: ->(3,2,-1).
        self.assert_vector(transform_phone_to_vehicle(Vector3(1, 2, 3), pi/2, pi/2, pi/2), (3, 2, -1))

    def test_arbitrary_angles_against_sequential_rotations(self):
        r, p, y = .37, -.82, 1.13
        x, b, c = 2.7, -4.1, .9
        b, c = cos(r)*b - sin(r)*c, sin(r)*b + cos(r)*c
        x, c = cos(p)*x + sin(p)*c, -sin(p)*x + cos(p)*c
        x, b = cos(y)*x - sin(y)*b, sin(y)*x + cos(y)*b
        self.assert_vector(transform_phone_to_vehicle(Vector3(2.7, -4.1, .9), r, p, y), (x, b, c))

    def test_magnitude_preservation(self):
        for vector in (Vector3(2.7, -4.1, .9), Vector3(-10, 20, 30), Vector3(.001, 0, -.02)):
            for angles in ((.37, -.82, 1.13), (-2, 1, 4), (0, pi/2, 0)):
                with self.subTest(vector=vector, angles=angles):
                    result = transform_phone_to_vehicle(vector, *angles)
                    self.assertAlmostEqual(hypot(vector.x, vector.y, vector.z),
                                           hypot(result.x, result.y, result.z), delta=1e-9)

    def test_repeatability_and_immutability(self):
        vector = Vector3(1, 2, 3)
        first = transform_phone_to_vehicle(vector, .3, -.4, .5)
        self.assertEqual(first, transform_phone_to_vehicle(vector, .3, -.4, .5))
        self.assertEqual(vector, Vector3(1, 2, 3))
        with self.assertRaises(FrozenInstanceError):
            vector.x = 4

    def test_invalid_components(self):
        for bad in ("1", True, False, None, [], {}, float("nan"), float("inf"), -float("inf"), 10**400):
            for index in range(3):
                with self.subTest(value=bad, index=index):
                    values = [1, 2, 3]
                    values[index] = bad
                    with self.assertRaises(ValueError):
                        Vector3(*values)

    def test_invalid_angles(self):
        for bad in ("1", True, False, None, [], {}, float("nan"), float("inf"), -float("inf"), 10**400):
            for index in range(3):
                with self.subTest(value=bad, index=index):
                    angles = [0, 0, 0]
                    angles[index] = bad
                    with self.assertRaises(ValueError):
                        build_phone_to_vehicle_rotation(*angles)
                    with self.assertRaises(ValueError):
                        transform_phone_to_vehicle(Vector3(1, 2, 3), *angles)

    def test_invalid_vector_container(self):
        for bad in (None, [1, 2, 3], (1, 2, 3), {}, True, "123"):
            with self.subTest(value=bad), self.assertRaises(ValueError):
                transform_phone_to_vehicle(bad, 0, 0, 0)

    def test_multiple_turns(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(1, 2, 3), 0, 0, 4*pi), (1, 2, 3))

    def test_very_large_finite_angles(self):
        for angles in ((1e100, -1e100, 1e100), (1e308, -1e308, 1e308)):
            with self.subTest(angles=angles):
                result = transform_phone_to_vehicle(Vector3(1, 2, 3), *angles)
                self.assertAlmostEqual(hypot(result.x, result.y, result.z), hypot(1, 2, 3), delta=1e-9)

    def test_output_overflow_rejected(self):
        with self.assertRaises(ValueError):
            transform_phone_to_vehicle(Vector3(1.7e308, 1.7e308, 0), 0, 0, -pi/4)

    def test_accelerometer_retains_gravity(self):
        result = transform_phone_to_vehicle(Vector3(0, 0, 9.81), pi/2, 0, 0)
        self.assert_vector(result, (0, -9.81, 0))

    def test_gyroscope(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(.1, .2, .3), 0, 0, pi/2), (-.2, .1, .3))

    def test_magnetometer(self):
        self.assert_vector(transform_phone_to_vehicle(Vector3(20, -5, 40), 0, pi/2, 0), (40, -5, -20))

    def test_identity_matrix(self):
        self.assertEqual(build_phone_to_vehicle_rotation(0, 0, 0),
                         ((1, 0, 0), (0, 1, 0), (0, 0, 1)))

    def test_matrix_properties(self):
        for angles in ((.3, -.7, 1.2), (0, pi/2, 0), (0, 0, 0)):
            with self.subTest(angles=angles):
                matrix = build_phone_to_vehicle_rotation(*angles)
                for vectors in (matrix, tuple(zip(*matrix))):
                    for i in range(3):
                        for j in range(3):
                            self.assertAlmostEqual(sum(a*b for a, b in zip(vectors[i], vectors[j])),
                                                   float(i == j), delta=1e-9)
                a, b, c = matrix
                determinant = (a[0]*(b[1]*c[2]-b[2]*c[1])
                               - a[1]*(b[0]*c[2]-b[2]*c[0])
                               + a[2]*(b[0]*c[1]-b[1]*c[0]))
                self.assertAlmostEqual(determinant, 1, delta=1e-9)

    def test_transpose_inverse(self):
        angles = (.3, -.7, 1.2)
        matrix = build_phone_to_vehicle_rotation(*angles)
        result = transform_phone_to_vehicle(Vector3(2, -3, 4), *angles)
        back = Vector3(*(sum(a*b for a, b in zip(column, (result.x, result.y, result.z)))
                         for column in zip(*matrix)))
        self.assert_vector(back, (2, -3, 4))

    def test_existing_sensor_sample_without_mutation(self):
        root = Path(__file__).resolve().parents[3]
        sample = json.loads((root / "integration/interfaces/sample_data/sensor_data.json")
                            .read_text(encoding="utf-8"))
        original = sample.copy()
        for sensor in ("accelerometer", "gyroscope", "magnetometer"):
            with self.subTest(sensor=sensor):
                values = tuple(sample[f"{sensor}_{axis}"] for axis in "xyz")
                self.assert_vector(transform_phone_to_vehicle(Vector3(*values), 0, 0, 0), values)
        self.assertEqual(sample, original)


if __name__ == "__main__":
    unittest.main()
