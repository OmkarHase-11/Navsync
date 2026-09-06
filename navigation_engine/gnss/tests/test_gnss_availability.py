"""Synthetic boundary and regression cases; no recorded sensor measurements."""

import json
from dataclasses import asdict
from pathlib import Path
import unittest

from navigation_engine.gnss.gnss_availability import (
    GNSSStatusResult,
    detect_gnss_availability,
)


class GNSSAvailabilityTests(unittest.TestCase):
    def detect(self, **changes):
        args = dict(latitude=18.5204, longitude=73.8567, accuracy=8.0,
                    fix_timestamp_ms=1725552000000,
                    current_timestamp_ms=1725552001000)
        args.update(changes)
        return detect_gnss_availability(**args)

    def assert_reason(self, expected, **changes):
        result = self.detect(**changes)
        self.assertEqual(result.reason, expected)
        self.assertEqual(result.status, "AVAILABLE" if expected == "OK" else "UNAVAILABLE")
        if expected not in ("OK", "STALE_FIX", "POOR_ACCURACY"):
            self.assertIsNone(result.fix_age_ms)
        return result

    def test_valid_fix(self):
        self.assertEqual(self.detect(), GNSSStatusResult("AVAILABLE", "OK", 1000))

    def test_no_fix(self):
        self.assert_reason("NO_FIX", latitude=None, longitude=None,
                           accuracy=None, fix_timestamp_ms=None)

    def test_missing_measurements(self):
        for field in ("latitude", "longitude", "accuracy"):
            with self.subTest(field=field):
                self.assert_reason("MISSING_" + field.upper(), **{field: None})

    def test_out_of_range_coordinates(self):
        for field, values in (("latitude", (-90.001, 90.001)),
                              ("longitude", (-180.001, 180.001))):
            for value in values:
                with self.subTest(field=field, value=value):
                    self.assert_reason("INVALID_" + field.upper(), **{field: value})

    def test_invalid_numeric_types_and_nonfinite_values(self):
        for field in ("latitude", "longitude", "accuracy"):
            for value in (True, False, "12", [], {}, float("nan"),
                          float("inf"), -float("inf")):
                with self.subTest(field=field, value=value):
                    self.assert_reason("INVALID_" + field.upper(), **{field: value})

    def test_negative_accuracy(self):
        self.assert_reason("INVALID_ACCURACY", accuracy=-0.01)

    def test_accuracy_boundary(self):
        self.assert_reason("OK", accuracy=30.0)
        result = self.assert_reason("POOR_ACCURACY", accuracy=30.001)
        self.assertEqual(result.fix_age_ms, 1000)

    def test_age_boundary(self):
        result = self.assert_reason("OK", current_timestamp_ms=1725552003000)
        self.assertEqual(result.fix_age_ms, 3000)
        result = self.assert_reason("STALE_FIX", current_timestamp_ms=1725552003001)
        self.assertEqual(result.fix_age_ms, 3001)

    def test_future_fix(self):
        self.assert_reason("INVALID_TIMESTAMP", fix_timestamp_ms=1725552001001)

    def test_invalid_timestamps(self):
        for field in ("fix_timestamp_ms", "current_timestamp_ms"):
            for value in (None, -1, True, False, 1725552000000.0, "1725552000000",
                          float("nan"), float("inf"), [], {}):
                with self.subTest(field=field, value=value):
                    self.assert_reason("INVALID_TIMESTAMP", **{field: value})

    def test_zero_and_negative_coordinates_and_endpoints(self):
        for lat, lon in ((0, 0), (-18.5204, -73.8567), (-90, -180), (90, 180)):
            with self.subTest(latitude=lat, longitude=lon):
                self.assert_reason("OK", latitude=lat, longitude=lon)

    def test_good_and_zero_accuracy(self):
        for accuracy in (0, 0.01):
            with self.subTest(accuracy=accuracy):
                self.assert_reason("OK", accuracy=accuracy)

    def test_equal_timestamps_and_epoch_zero(self):
        for timestamp in (0, 1725552000000):
            with self.subTest(timestamp=timestamp):
                result = self.assert_reason("OK", fix_timestamp_ms=timestamp,
                                            current_timestamp_ms=timestamp)
                self.assertEqual(result.fix_age_ms, 0)

    def test_configurable_thresholds(self):
        self.assert_reason("STALE_FIX", max_fix_age_ms=999)
        self.assert_reason("OK", max_fix_age_ms=1000)
        self.assert_reason("OK", current_timestamp_ms=1725552005000, max_fix_age_ms=5000)
        self.assert_reason("POOR_ACCURACY", max_accuracy_m=7.99)
        self.assert_reason("OK", max_accuracy_m=8)
        self.assert_reason("OK", accuracy=75, max_accuracy_m=75)
        self.assert_reason("OK", accuracy=0, max_accuracy_m=0,
                           fix_timestamp_ms=0, current_timestamp_ms=0, max_fix_age_ms=0)

    def test_invalid_configuration(self):
        cases = {
            "max_fix_age_ms": (None, -1, True, False, 3.0, "3000", float("inf")),
            "max_accuracy_m": (None, -1, True, False, "30", float("nan"), float("inf")),
        }
        for field, values in cases.items():
            for value in values:
                with self.subTest(field=field, value=value):
                    with self.assertRaises(ValueError):
                        self.detect(**{field: value})
        with self.assertRaises(ValueError):
            self.detect(latitude=None, longitude=None, accuracy=None,
                        fix_timestamp_ms=None, max_fix_age_ms=-1)

    def test_failure_precedence(self):
        cases = [
            ("NO_FIX", dict(latitude=None, longitude=None, accuracy=None,
                            fix_timestamp_ms=None, current_timestamp_ms=None)),
            ("MISSING_LATITUDE", dict(latitude=None, longitude=None, accuracy=None)),
            ("MISSING_LONGITUDE", dict(latitude=91, longitude=None, accuracy=None)),
            ("MISSING_ACCURACY", dict(latitude=91, longitude=181, accuracy=None)),
            ("INVALID_LATITUDE", dict(latitude=91, longitude=181, accuracy=-1)),
            ("INVALID_LONGITUDE", dict(longitude=181, accuracy=-1)),
            ("INVALID_ACCURACY", dict(accuracy=-1, fix_timestamp_ms=None)),
            ("INVALID_TIMESTAMP", dict(fix_timestamp_ms=None, accuracy=75)),
            ("STALE_FIX", dict(current_timestamp_ms=1725552005000, accuracy=75)),
        ]
        for reason, changes in cases:
            with self.subTest(reason=reason):
                first = self.assert_reason(reason, **changes)
                self.assertEqual(first, self.detect(**changes))

    def test_same_fix_becomes_stale_on_reevaluation(self):
        self.assert_reason("OK")
        self.assert_reason("STALE_FIX", current_timestamp_ms=1725552005000)
        self.assert_reason("OK")  # No hidden state from prior evaluations.

    def test_requested_examples(self):
        self.assertEqual(self.detect(), GNSSStatusResult("AVAILABLE", "OK", 1000))
        self.assertEqual(self.detect(current_timestamp_ms=1725552005000),
                         GNSSStatusResult("UNAVAILABLE", "STALE_FIX", 5000))
        self.assertEqual(self.detect(accuracy=75),
                         GNSSStatusResult("UNAVAILABLE", "POOR_ACCURACY", 1000))

    def test_result_serialization_and_boolean_mapping(self):
        for result in (self.detect(), self.detect(latitude=None)):
            with self.subTest(reason=result.reason):
                payload = json.loads(json.dumps(asdict(result)))
                self.assertEqual(set(payload), {"status", "reason", "fix_age_ms"})
                self.assertEqual(payload["status"] == "AVAILABLE", result.reason == "OK")
                self.assertEqual(payload["fix_age_ms"], result.fix_age_ms)

    def test_existing_sensor_data_sample(self):
        root = Path(__file__).resolve().parents[3]
        sample = json.loads((root / "integration/interfaces/sample_data/sensor_data.json")
                            .read_text(encoding="utf-8"))
        # For this fixture only, assume the snapshot epoch is the GNSS fix epoch.
        result = detect_gnss_availability(
            sample["latitude"], sample["longitude"], sample["gnss_accuracy"],
            sample["timestamp"], sample["timestamp"],
        )
        self.assertEqual(result, GNSSStatusResult("AVAILABLE", "OK", 0))
        self.assertEqual(result.status == "AVAILABLE", sample["gnss_available"])


if __name__ == "__main__":
    unittest.main()
