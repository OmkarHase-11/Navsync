"""Synthetic model tests; no real IO-VNBD dependency or generalization claims."""

from contextlib import redirect_stdout, redirect_stderr
import csv
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import joblib
import numpy as np

from ai import speed_estimation as module
from ai.speed_estimation import (DEFAULT_FEATURES, validate_feature_columns, create_windows,
    create_feature_windows, train_speed_model, predict_speed, train_from_pairs,
    save_model, load_model, predict_from_records, main)


class SpeedEstimationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.records = [dict(time_s=i*.1, reference_speed=i*.5,
                             **{name:float(i+j) for j,name in enumerate(DEFAULT_FEATURES)}) for i in range(15)]

    def pair(self, name="one"):
        phone, vehicle = self.root / f"S-{name}.csv", self.root / f"V-{name}.csv"
        for path, header, rows in (
            (phone, ["Time (ms)"]+[f"{sensor} {axis}" for sensor in ("Accelerometer", "Gyroscope") for axis in "XYZ"],
             [[i*100]+[r[f] for f in DEFAULT_FEATURES] for i,r in enumerate(self.records)]),
            (vehicle, ["Time (seconds)", "Velocity (km/hr)"],
             [[r["time_s"], r["reference_speed"]*3.6] for r in self.records])):
            with path.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.writer(stream)
                writer.writerow(header)
                writer.writerows(rows)
        return str(phone), str(vehicle)

    def trained(self):
        return train_from_pairs([self.pair()], window_size=3, n_estimators=5)

    def test_default_features(self):
        self.assertEqual(validate_feature_columns(None), list(DEFAULT_FEATURES))

    def test_leakage_columns_rejected(self):
        for bad in ("reference_speed", "smartphone_gps_speed", "gps_latitude", "gps_longitude", "velocity",
                    "indicated_vehicle_speed", "wheel_speed", "vehicle_yaw_rate", "engine_rpm", "steering",
                    "vehicle_longitudinal_acceleration", "vehicle_lateral_acceleration", "brake", "accelerator"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                validate_feature_columns(["accel_x", bad])

    def test_bad_feature_collections(self):
        for bad in ([], "accel_x", [True], ["accel_x", "accel_x"], ["ACCEL_X"]):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                validate_feature_columns(bad)

    def test_window_count_step_and_statistics(self):
        windows = create_windows(self.records, window_size=3, step_size=2, run_id="run")
        self.assertEqual(windows["X"].shape, (7,24))
        self.assertEqual(windows["feature_names"][:4], ["accel_x_mean", "accel_x_std", "accel_x_min", "accel_x_max"])
        np.testing.assert_allclose(windows["X"][0,:4], [1, np.sqrt(2/3), 0, 2])
        self.assertEqual(windows["y"][0], self.records[2]["reference_speed"])
        self.assertEqual(windows["window_metadata"][0], dict(run_id="run", start_index=0, end_index=2,
                         target_index=2, start_time_s=0, end_time_s=.2, target_time_s=.2))
        self.assertEqual([m["target_index"] for m in windows["window_metadata"]], list(range(2,15,2)))

    def test_population_std_single_sample(self):
        windows = create_windows(self.records, 1)
        self.assertEqual(windows["X"][0,1], 0)

    def test_window_argument_validation(self):
        for option in ("window_size", "step_size"):
            for bad in (0, -1, True, 1.5, None, "2"):
                with self.subTest(option=option, bad=bad), self.assertRaises(ValueError):
                    create_windows(self.records, **{option:bad})
        with self.assertRaises(ValueError):
            create_windows(self.records, 16)

    def test_invalid_feature_values(self):
        for bad in (None, "1", True, float("nan"), float("inf"), -float("inf"), []):
            with self.subTest(bad=bad):
                rows = [dict(r) for r in self.records]
                rows[0]["accel_x"] = bad
                with self.assertRaises(ValueError):
                    create_windows(rows, 3)
        del rows[0]["accel_x"]
        with self.assertRaises(ValueError):
            create_windows(rows, 3)

    def test_invalid_targets(self):
        for bad in (None, "2", True, float("nan"), float("inf"), -1):
            with self.subTest(bad=bad):
                rows = [dict(r) for r in self.records]
                rows[0]["reference_speed"] = bad
                with self.assertRaises(ValueError):
                    create_windows(rows, 3)
        del rows[0]["reference_speed"]
        with self.assertRaises(ValueError):
            create_windows(rows, 3)

    def test_time_validation_and_gap(self):
        for bad in (0, -.1, None, float("inf"), "0.1", True):
            with self.subTest(bad=bad):
                rows = [dict(r) for r in self.records]
                rows[1]["time_s"] = bad
                with self.assertRaises(ValueError):
                    create_windows(rows, 3)
        rows = [dict(r) for r in self.records]
        for r in rows[5:]:
            r["time_s"] += 1
        with self.assertRaisesRegex(ValueError, "gap"):
            create_windows(rows, 3)
        self.assertEqual(len(create_windows(rows, 3, max_gap_s=2)["X"]), 13)

    def test_inference_no_label_and_same_schema(self):
        training = create_windows(self.records, 3)
        rows = [{k:v for k,v in r.items() if k != "reference_speed"} for r in self.records]
        inference = create_feature_windows(rows, 3)
        self.assertNotIn("y", inference)
        np.testing.assert_array_equal(training["X"], inference["X"])
        self.assertEqual(training["feature_names"], inference["feature_names"])

    def test_extra_fields_do_not_influence_features(self):
        original = create_windows(self.records, 3)["X"]
        rows = [dict(r, smartphone_gps_speed=999, vehicle_yaw_rate=-999, gps_latitude=99) for r in self.records]
        np.testing.assert_array_equal(original, create_windows(rows, 3)["X"])

    def test_small_training_metadata_metrics_and_determinism(self):
        windows = create_windows(self.records, 3)
        one = train_speed_model(windows["X"], windows["y"], n_estimators=5)
        two = train_speed_model(windows["X"], windows["y"], n_estimators=5)
        np.testing.assert_array_equal(predict_speed(one["model"], windows["X"]), predict_speed(two["model"], windows["X"]))
        self.assertEqual(one["training_metadata"]["training_windows"], 13)
        self.assertEqual(one["training_metadata"]["input_features"], 24)
        self.assertEqual(one["training_metadata"]["random_state"], 42)
        self.assertEqual(one["training_metadata"]["n_estimators"], 5)
        self.assertTrue(all(np.isfinite(v) for v in one["training_metrics"].values()))

    def test_bad_training_data(self):
        for X,y in (([],[]), ([[1],[2]],[1]), ([[float("nan")]],[1]), ([[1]],[float("inf")]),
                    ([[1]],[-1]), ([["1"]],[1]), ([[True]],[1]), ([[1]],[[1]]), ([[1e100]],[1])):
            with self.subTest(X=X,y=y), self.assertRaises(ValueError):
                train_speed_model(X,y,n_estimators=2)

    def test_bad_training_parameters(self):
        for changes in (dict(n_estimators=0), dict(n_estimators=True), dict(random_state=None),
                        dict(random_state=True), dict(random_state=-1)):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                train_speed_model([[1]],[1], **changes)

    def test_single_label_r2_is_null(self):
        result = train_speed_model([[1]], [1], n_estimators=2)
        self.assertIsNone(result["training_metrics"]["r2"])

    def test_prediction_validation_and_constraint(self):
        class Model:
            n_features_in_ = 1
            def predict(self, X):
                return [-.001]*len(X)
        np.testing.assert_array_equal(predict_speed(Model(), [[1],[2]]), [0,0])
        with self.assertRaises(ValueError):
            predict_speed(Model(), [[1,2]])
        with patch.object(Model, "predict", return_value=[float("nan")]):
            with self.assertRaises(ValueError):
                predict_speed(Model(), [[1]])

    def test_multirun_preprocessing_reuse(self):
        pairs = [self.pair("one"), self.pair("two")]
        with patch.object(module, "preprocess_pair", wraps=module.preprocess_pair) as preprocess:
            result = train_from_pairs(pairs, window_size=3, n_estimators=2)
            self.assertEqual(preprocess.call_count, 2)
            for call in preprocess.call_args_list:
                self.assertEqual(call.kwargs["speed_unit"], "mps")
        self.assertEqual(result["total_window_count"], 26)
        self.assertEqual(len({m["run_id"] for m in result["window_metadata"]}), 2)
        self.assertEqual(result["model_bundle"]["target_unit"], "m/s")
        self.assertEqual(result["model_bundle"]["training_metadata"]["training_windows"], 26)

    def test_bad_pair_fails_not_skipped(self):
        with self.assertRaises(ValueError):
            train_from_pairs([])
        pair = self.pair()
        with self.assertRaisesRegex(ValueError, "reused"):
            train_from_pairs([pair,pair], window_size=3, n_estimators=2)
        with self.assertRaisesRegex(ValueError, "Run"):
            train_from_pairs([pair,("missing", "missing2")], window_size=3, n_estimators=2)

    def test_predict_from_records_without_label(self):
        bundle = self.trained()["model_bundle"]
        rows = [{k:v for k,v in r.items() if k != "reference_speed"} for r in self.records]
        output = predict_from_records(bundle, rows, run_id="inference")
        self.assertEqual(len(output),13)
        self.assertEqual((output[0]["time_s"],output[0]["target_index"],output[0]["run_id"]), (.2,2,"inference"))
        self.assertTrue(all(np.isfinite(r["estimated_speed"]) and r["estimated_speed"] >= 0 for r in output))

    def test_serialization_roundtrip_and_no_overwrite(self):
        bundle = self.trained()["model_bundle"]
        path = self.root / "models" / "speed.joblib"
        save_model(bundle,path)
        loaded = load_model(path)
        self.assertEqual(predict_from_records(bundle,self.records), predict_from_records(loaded,self.records))
        before = path.read_bytes()
        with self.assertRaises(FileExistsError):
            save_model(bundle,path)
        self.assertEqual(before,path.read_bytes())
        self.assertNotIn("records", loaded)
        self.assertNotIn("X", loaded)

    def test_bad_artifacts(self):
        with self.assertRaises(FileNotFoundError):
            load_model(self.root / "missing")
        with self.assertRaises(ValueError):
            load_model(self.root)
        path = self.root / "bad.joblib"
        path.write_bytes(b"not a model")
        with self.assertRaises(ValueError):
            load_model(path)
        joblib.dump({},path)
        with self.assertRaises(ValueError):
            load_model(path)

    def test_bundle_schema_validation(self):
        bundle = self.trained()["model_bundle"]
        for key,value in (("schema_version",99), ("target_unit","km/h"), ("window_size",True),
                          ("raw_feature_columns",["reference_speed"]), ("engineered_feature_names",[]),
                          ("model",None), ("versions",{})):
            with self.subTest(key=key), self.assertRaises(ValueError):
                save_model(dict(bundle, **{key:value}), self.root / "bad.joblib")
        with self.assertRaises(ValueError):
            save_model(dict(bundle, records=self.records), self.root / "bad.joblib")

    def test_cli_required_arguments(self):
        for args in ([], ["train"], ["train","--pair","one"]):
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                main(args)
            self.assertEqual(error.exception.code,2)

    def test_cli_training_with_and_without_save(self):
        pair = self.pair()
        for save in (False,True):
            with self.subTest(save=save):
                path = self.root / "cli.joblib"
                args = ["train", "--pair", *pair, "--window-size", "3", "--n-estimators", "2"]
                if save:
                    args += ["--model-output",str(path)]
                stream = io.StringIO()
                with redirect_stdout(stream):
                    self.assertEqual(main(args),0)
                summary = json.loads(stream.getvalue())
                self.assertEqual(summary["total_window_count"],13)
                self.assertEqual(summary["metrics_scope"],"IN-SAMPLE TRAINING METRICS")
                self.assertEqual(path.exists(),save)


if __name__ == "__main__":
    unittest.main()
