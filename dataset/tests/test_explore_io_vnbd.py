"""Temporary synthetic CSV fixtures; no dependency on the real dataset."""

from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest

from dataset.explore_io_vnbd import ALIGNMENT_NOTE, explore_file, explore_pair, load_csv, main


class ExplorationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, name, text, encoding="utf-8"):
        path = self.root / name
        path.write_bytes(text.encode(encoding))
        return path

    def pair(self):
        phone = self.write("S.csv", "Time (ms),GPS SPEED (Kmh),Accelerometer X,Gyroscope X,Magnetic Field X,GPS Latitude\n0,1,1,2,3,4\n100,2,2,3,4,5\n200,3,3,4,5,6\n")
        vehicle = self.write("V.csv", "Time (seconds),Velocity (km/hr),Wheel Speed (rad/sec)\n0,10,1\n0.1,20,2\n0.2,30,3\n")
        return phone, vehicle

    def test_missing_file(self):
        with self.assertRaisesRegex(FileNotFoundError, "does not exist"):
            explore_file(self.root / "absent.csv")

    def test_directory_rejected(self):
        with self.assertRaisesRegex(ValueError, "not a file"):
            explore_file(self.root)

    def test_schema_and_groups(self):
        phone, vehicle = self.pair()
        report = explore_pair(phone, vehicle)
        self.assertEqual(set(report), {"smartphone", "vehicle", "comparison", "suitability"})
        s = report["smartphone"]
        self.assertEqual((s["row_count"], s["column_count"]), (3, 6))
        self.assertEqual(s["columns"][0], "Time (ms)")
        for group in ("timestamp", "gps", "accelerometer", "gyroscope", "magnetometer", "speed"):
            self.assertTrue(s["groups"][group], group)
        self.assertEqual(report["vehicle"]["groups"]["vehicle_wheel_speed"], ["Wheel Speed (rad/sec)"])

    def test_statistics_and_missing(self):
        path = self.write("a.csv", "value,text\n1,hello\n3,world\n , \nbad,name\nNaN,name\ninf,name\n5,name\n")
        result = explore_file(path)
        stats = result["numeric_statistics"]["value"]
        self.assertEqual((stats["min"], stats["max"], stats["mean"]), (1, 5, 3))
        self.assertEqual(stats["numeric_count"], 3)
        self.assertEqual(stats["invalid_nonblank_count"], 3)
        self.assertNotIn("text", result["numeric_statistics"])
        self.assertEqual(result["missing_values"]["value"]["blank_count"], 1)
        self.assertAlmostEqual(result["missing_values"]["value"]["blank_percentage"], 100/7)

    def test_sampling_ms_and_seconds(self):
        report = explore_pair(*self.pair())
        for name in ("smartphone", "vehicle"):
            sampling = report[name]["sampling"]
            self.assertAlmostEqual(sampling["duration_s"], .2)
            self.assertAlmostEqual(sampling["median_sample_interval_s"], .1)
            self.assertAlmostEqual(sampling["estimated_hz"], 10)
            self.assertEqual(sampling["sample_count"], 3)
        self.assertEqual(report["comparison"]["duration_difference_s"], 0)

    def test_unknown_units(self):
        result = explore_file(self.write("a.csv", "Elapsed time\n0\n100\n200\n"))
        self.assertIsNone(result["sampling"]["duration_s"])
        self.assertIsNone(result["sampling"]["estimated_hz"])
        self.assertIn("uncertain", result["sampling"]["unit_inference"])

    def test_no_numeric_time(self):
        result = explore_file(self.write("a.csv", "Date,Sample period (seconds)\n2020-01-01,.1\n2020-01-02,.1\n"))
        self.assertIsNone(result["sampling"]["column"])

    def test_missing_timestamps_do_not_bridge(self):
        result = explore_file(self.write("a.csv", "Elapsed (s),x\n0,1\n,2\n1,3\n1.1,4\n"))
        self.assertAlmostEqual(result["sampling"]["median_sample_interval_s"], .1)
        self.assertEqual(result["sampling"]["invalid_or_missing_sample_count"], 1)

    def test_nonpositive_intervals(self):
        for sequence in ("0\n.1\n.1\n", "1\n.1\n.2\n"):
            with self.subTest(sequence=sequence):
                sampling = explore_file(self.write("a.csv", "Time (s)\n"+sequence))["sampling"]
                self.assertEqual(sampling["non_positive_differences"], 1)
                self.assertIsNone(sampling["estimated_hz"])
                self.assertIsNone(sampling["duration_s"])

    def test_large_gap(self):
        sampling = explore_file(self.write("a.csv", "Time (s)\n0\n.1\n.2\n2\n"))["sampling"]
        self.assertEqual(sampling["large_gap_count"], 1)
        self.assertAlmostEqual(sampling["max_interval_s"], 1.8)

    def test_equal_rows_not_synchronization(self):
        report = explore_pair(*self.pair())
        self.assertTrue(report["comparison"]["row_counts_match"])
        self.assertEqual(report["comparison"]["synchronization_note"], ALIGNMENT_NOTE)

    def test_unequal_rows(self):
        phone, vehicle = self.pair()
        vehicle.write_text("Time (s),Velocity\n0,1\n", encoding="utf-8")
        self.assertFalse(explore_pair(phone, vehicle)["comparison"]["row_counts_match"])

    def test_speed_discrepancy_and_no_wheel_comparison(self):
        comparison = explore_pair(*self.pair())["comparison"]["speed_comparisons"]
        self.assertEqual(len(comparison), 1)
        self.assertIn("differ substantially", comparison[0]["warning"])
        self.assertEqual(comparison[0]["smartphone_range"], [1, 3])

    def test_similar_speed_no_warning(self):
        phone, vehicle = self.pair()
        vehicle.write_text("Velocity\n1\n2\n3\n", encoding="utf-8")
        self.assertIsNone(explore_pair(phone, vehicle)["comparison"]["speed_comparisons"][0]["warning"])

    def test_encodings(self):
        for source, text, expected in (("utf-8", "GPS µT\n1\n", "utf-8-sig"),
                                       ("utf-8-sig", "GPS µT\n1\n", "utf-8-sig"),
                                       ("cp1252", "Orientation °\n1\n", "cp1252"),
                                       ("latin-1", "note\n\x81\n", "latin-1")):
            with self.subTest(source=source):
                self.assertEqual(explore_file(self.write("a.csv", text, source))["encoding"], expected)

    def test_empty_and_ambiguous_headers(self):
        for text in ("", "a,\n1,2\n", "A, a \n1,2\n"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                load_csv(self.write("a.csv", text))

    def test_header_only(self):
        result = explore_file(self.write("a.csv", "time,speed\n"))
        self.assertEqual(result["row_count"], 0)
        self.assertEqual(result["numeric_statistics"], {})
        self.assertIsNone(result["speed_statistics"]["speed"]["mean"])

    def test_malformed_quoting(self):
        with self.assertRaisesRegex(ValueError, "Malformed CSV"):
            load_csv(self.write("a.csv", 'value\n"unfinished\n'))

    def test_large_finite_time_intervals_remain_json_compatible(self):
        phone = self.write("S.csv", "Time (s),GPS Speed\n-1e308,0\n0,0\n1e308,0\n")
        vehicle = self.write("V.csv", "Time (s),Velocity\n0,0\n1,0\n")
        report = explore_pair(phone, vehicle)
        json.dumps(report, allow_nan=False)
        self.assertIsNone(report["smartphone"]["sampling"]["duration_s"])

    def test_ragged_rows_and_quoted_cells(self):
        result = explore_file(self.write("a.csv", 'a,b\n1\n2,3,extra\n\n4,"hello,world"\n'))
        self.assertEqual(result["row_count"], 3)
        self.assertEqual(result["missing_values"]["b"]["blank_count"], 1)
        self.assertEqual(len(result["warnings"]), 3)

    def test_case_insensitive_detection(self):
        result = explore_file(self.write("a.csv", "elapsed TIME (ms),acc_x,GYRO_y,MAG_z,gnss latitude,vehicle SPEED,azimuth\n0,1,2,3,4,5,6\n"))
        for group in ("timestamp", "accelerometer", "gyroscope", "magnetometer", "gps", "speed", "orientation"):
            self.assertTrue(result["groups"][group])

    def test_cli_required_arguments(self):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            main([])
        self.assertEqual(error.exception.code, 2)

    def test_cli_output_and_inputs_unchanged(self):
        phone, vehicle = self.pair()
        before = (phone.read_bytes(), vehicle.read_bytes())
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["--smartphone", str(phone), "--vehicle", str(vehicle)]), 0)
        self.assertIn("suitability", json.loads(output.getvalue()))
        self.assertEqual(before, (phone.read_bytes(), vehicle.read_bytes()))

    def test_cli_missing_file(self):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            main(["--smartphone", str(self.root / "missing"), "--vehicle", str(self.root)])
        self.assertEqual(error.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
