"""Temporary synthetic CSV tests, independent of IO-VNBD installation."""

import csv
from contextlib import redirect_stdout, redirect_stderr
import io
import json
from pathlib import Path
import tempfile
import unittest

from preprocessing.imu_preprocessing import (
    load_sensor_csv, detect_smartphone_columns, detect_vehicle_columns,
    parse_timestamps, validate_sampling, synchronize_streams, preprocess_pair,
    export_preprocessed_csv, main,
)


class PreprocessingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sh = ["Time (ms)"] + [f" {s} {a.upper()} ({unit}) " for s,unit in
                   (("Accelerometer", "m/s²"), ("Gyroscope", "rad/s")) for a in "xyz"]
        self.sh += ["Gravity X (m/s²)", "Magnetic Field X (µT)", "GPS SPEED (Kmh)"]
        self.vh = ["Time (seconds)", "Velocity (km/hr)", "Indicated Vehicle Speed (km/hr)", "Wheel Speed (rad/sec)"]
        self.srows = [[1000+i*100, 1,2,3,4,5,6,9.8,20,11.54] for i in range(3)]
        self.vrows = [[40+i*.1, 36,40,50] for i in range(3)]

    def write(self, name, header, rows, encoding="utf-8"):
        path = self.root / name
        with path.open("w", encoding=encoding, newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(header)
            writer.writerows(rows)
        return path

    def pair(self):
        return (self.write("S.csv", self.sh, self.srows), self.write("V.csv", self.vh, self.vrows))

    def test_loading_errors(self):
        with self.assertRaises(FileNotFoundError):
            load_sensor_csv(self.root / "missing")
        with self.assertRaises(ValueError):
            load_sensor_csv(self.root)
        for text in ("", "a\n", "a,A\n1,2\n", 'a\n"unfinished', "a,b\n1\n", "a\n1,2\n"):
            with self.subTest(text=text):
                path = self.root / "bad.csv"
                path.write_text(text)
                with self.assertRaises(ValueError):
                    load_sensor_csv(path)

    def test_encodings_and_quoted_values(self):
        for encoding in ("cp1252", "utf-8-sig"):
            with self.subTest(encoding=encoding):
                path = self.write("a.csv", ["Angle °", "note"], [[1,"a,b"]], encoding)
                loaded = load_sensor_csv(path)
                self.assertEqual(loaded["encoding"], encoding)
                self.assertEqual(loaded["rows"][0]["note"], "a,b")

    def test_phone_detection(self):
        detected = detect_smartphone_columns(self.sh)
        for field in ("time", "accelerometer_x", "accelerometer_y", "accelerometer_z",
                      "gyroscope_x", "gyroscope_y", "gyroscope_z", "gravity_x", "magnetometer_x", "gps_speed"):
            self.assertIsNotNone(detected[field])
        self.assertEqual(detect_smartphone_columns(["  gYRoScOpE_z (RAD/S) "])["gyroscope_z"], "  gYRoScOpE_z (RAD/S) ")

    def test_vehicle_detection_excludes_nonlabels(self):
        columns = detect_vehicle_columns(self.vh+["Vertical velocity (km/hr)", "Engine RPM"])
        self.assertEqual(columns["reference_velocity"], "Velocity (km/hr)")
        self.assertIsNone(detect_vehicle_columns(["Wheel Speed (rad/sec)", "Engine Speed (rpm)", "Vertical velocity (km/hr)"])["reference_velocity"])

    def test_ambiguous_axes_rejected(self):
        with self.assertRaises(ValueError):
            detect_smartphone_columns(["Accelerometer X", "Accelerometer X (m/s²)"])

    def test_timestamp_units(self):
        for header, values in (("Elapsed (ms)", [914616,914716]), ("Time (sec)", [40,40.1])):
            with self.subTest(header=header):
                result = parse_timestamps([{header:str(v)} for v in values], header)
                self.assertEqual(result["timestamps"][0], 0)
                self.assertAlmostEqual(result["timestamps"][1], .1)
                self.assertAlmostEqual(result["diagnostics"]["estimated_hz"], 10)

    def test_bad_timestamps(self):
        for values in ((0,0), (1,0), (0,"bad"), (0,""), (0,"NaN"), (0,"inf")):
            with self.subTest(values=values), self.assertRaises(ValueError):
                parse_timestamps([{"Time (ms)":v} for v in values], "Time (ms)")
        with self.assertRaisesRegex(ValueError, "Unknown"):
            parse_timestamps([{"Time":0}], "Time")

    def test_sampling_diagnostics(self):
        stats = validate_sampling([0,.1,.2,2])
        self.assertEqual(stats["large_gap_count"], 1)
        self.assertAlmostEqual(stats["median_interval_s"], .1)
        self.assertEqual(validate_sampling([0,0])["nonpositive_interval_count"], 1)

    def test_perfect_match(self):
        result = synchronize_streams([0,.1,.2], [0,.1,.2])
        self.assertEqual(result["pairs"], [(0,0),(1,1),(2,2)])
        self.assertEqual(result["diagnostics"]["unmatched_vehicle_samples"], 0)

    def test_offset_match(self):
        result = synchronize_streams([0,.1], [.02,.12])
        self.assertEqual(len(result["pairs"]), 2)
        self.assertAlmostEqual(result["diagnostics"]["max_absolute_time_offset_s"], .02)

    def test_not_row_index_matching(self):
        result = synchronize_streams([0,.1,.2], [0,.2,.3], .01)
        self.assertEqual(result["pairs"], [(0,0),(2,1)])
        self.assertEqual(result["diagnostics"]["unmatched_smartphone_samples"], 1)
        self.assertEqual(result["diagnostics"]["unmatched_vehicle_samples"], 1)

    def test_nonreuse_unequal_and_ties(self):
        result = synchronize_streams([0,.01,.02], [0], .055)
        self.assertEqual(result["pairs"], [(0,0)])
        self.assertEqual(synchronize_streams([1], [0,2], 1)["pairs"], [(0,0)])

    def test_invalid_tolerance(self):
        for value in (-1, True, float("nan"), float("inf")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                synchronize_streams([0], [0], value)

    def test_features_optional_and_label(self):
        result = preprocess_pair(*self.pair())
        self.assertEqual(len(result["records"]), 3)
        row = result["records"][0]
        self.assertEqual([row[f"accel_{a}"] for a in "xyz"], [1,2,3])
        self.assertEqual(row["gyro_z"], 6)
        self.assertEqual(row["gravity_x"], 9.8)
        self.assertEqual(row["magnetometer_x"], 20)
        self.assertEqual(row["reference_speed"], 36)
        self.assertEqual(result["metadata"]["output_speed_unit"], "km/h")

    def test_explicit_conversion_only_vehicle(self):
        result = preprocess_pair(*self.pair(), speed_unit="mps")
        self.assertEqual(result["records"][0]["reference_speed"], 10)
        self.assertEqual(result["records"][0]["smartphone_gps_speed"], 11.54)

    def test_unknown_unit_rejected_and_fallback(self):
        self.vh = ["Time (seconds)", "Velocity (unknown)"]
        self.vrows = [[40,36],[40.1,36]]
        with self.assertRaisesRegex(ValueError, "No acceptable"):
            preprocess_pair(*self.pair())
        self.vh += ["Indicated Vehicle Speed (km/hr)"]
        self.vrows = [[40,36,40],[40.1,36,40]]
        result = preprocess_pair(*self.pair())
        self.assertEqual(result["records"][0]["reference_speed"], 40)

    def test_missing_required_drops(self):
        self.srows[0][1] = ""
        self.srows[1][4] = ""
        self.vrows[2][1] = ""
        result = preprocess_pair(*self.pair())
        self.assertEqual(result["records"], [])
        for key in ("dropped_missing_accel", "dropped_missing_gyro", "dropped_missing_label"):
            self.assertEqual(result["quality"][key], 1)

    def test_invalid_numeric_and_negative_label(self):
        self.srows[0][1] = "NaN"
        self.srows[1][4] = "bad"
        self.vrows[2][1] = -1
        result = preprocess_pair(*self.pair())
        self.assertEqual(result["quality"]["dropped_invalid_numeric"], 2)
        self.assertEqual(result["quality"]["dropped_negative_label"], 1)

    def test_optional_nulls(self):
        self.srows[0][7] = ""
        self.srows[0][8] = "bad"
        result = preprocess_pair(*self.pair())
        self.assertIsNone(result["records"][0]["gravity_x"])
        self.assertIsNone(result["records"][0]["magnetometer_x"])
        self.assertEqual(result["quality"]["optional_invalid_values"], 1)

    def test_missing_axis_fails(self):
        self.sh[1] = "unrelated"
        with self.assertRaisesRegex(ValueError, "Missing required"):
            preprocess_pair(*self.pair())

    def test_export_stable_and_sources_unchanged(self):
        paths = self.pair()
        before = [p.read_bytes() for p in paths]
        result = preprocess_pair(*paths)
        output = self.root / "out" / "clean.csv"
        export_preprocessed_csv(result, output)
        with output.open(encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream)
            self.assertEqual(reader.fieldnames, ["time_s"]+result["feature_names"]+["reference_speed"])
            self.assertEqual(len(list(reader)), 3)
        self.assertEqual(before, [p.read_bytes() for p in paths])
        for path in paths:
            with self.assertRaises(ValueError):
                export_preprocessed_csv(result, path)
        with self.assertRaises(FileExistsError):
            export_preprocessed_csv(result, output)

    def test_cli_arguments_and_missing_file(self):
        for args in ([], ["--smartphone", "missing", "--vehicle", "missing"]):
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                main(args)
            self.assertEqual(error.exception.code, 2)

    def test_cli_summary(self):
        phone, vehicle = self.pair()
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(main(["--smartphone", str(phone), "--vehicle", str(vehicle)]), 0)
        self.assertEqual(json.loads(output.getvalue())["quality"]["final_record_count"], 3)


if __name__ == "__main__":
    unittest.main()
