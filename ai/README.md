# IMU-Based Vehicle Speed Estimation

## Purpose and scope

Issue #3 provides a CPU Random Forest baseline that estimates vehicle speed from smartphone IMU. It prepares statistical windows, trains, predicts, persists a model, and reports basic **IN-SAMPLE TRAINING METRICS**. It is an SIH MVP, not formal evaluation or a demonstrated navigation solution.

Issue #2's `preprocess_pair()` is reused for every training pair with `speed_unit="mps"`. CSV loading, synchronization, cleaning, and label conversion are not reimplemented. Dataset and navigation modules remain unchanged.

## Dependencies

From the repository root, in your Python environment:

```text
python -m pip install -r requirements.txt
```

Direct dependencies are NumPy (matrices/statistics), scikit-learn (RandomForestRegressor/metrics), and joblib (persistence). There is no pandas, GPU framework, or alternate fallback algorithm. Missing dependencies produce an explicit installation message. Dependency versions are recorded in each bundle; reproduce that environment when using an artifact. Requirements are not arbitrarily pinned.

## Model inputs and leakage prevention

The baseline inputs, in order, are:

```text
accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z
```

`validate_feature_columns()` uses an exact allowlist. Nonempty subsets/reorderings of these six fields are supported and recorded; duplicates, misspellings, other sensors, reference_speed, GPS, and vehicle fields are rejected. GPS speed is NOT a model input. Vehicle speed is label-only during training. Vehicle-side acceleration, yaw, wheel speed, engine state, coordinates, and other vehicle signals are NOT model inputs. Extra fields in input records are ignored, not passed through to the model.

The low-level matrix API cannot determine whether a caller has disguised a forbidden signal as an allowed numeric column. Use the record/pair APIs to enforce provenance and do not rename ground-truth fields into IMU names.

Phone acceleration retains gravity in m/s²; gyroscope axes are rad/s under the supplied dataset conventions. No gravity subtraction, filtering, mounting calibration, or automatic alignment occurs. The intended signal source must match training at inference.

## Target and speed units

The target is `reference_speed` at the **end of the window**, explicitly in **m/s**. Issue #2 selects recognized vehicle velocity (preferred) or indicated speed and performs explicit km/h-to-m/s conversion when needed. Its header-based validation and relative-start synchronization assumptions remain limitations, not proof of calibrated ground truth.

Smartphone GPS speed's unresolved scale discrepancy is neither corrected nor used by the model. Direct `create_windows()` and `train_speed_model()` callers must supply already-converted m/s labels; those functions cannot infer a numeric array's unit. All training labels must be finite and nonnegative.

## Window generation and feature engineering

`create_windows(records, window_size=10, step_size=1, feature_columns=None, run_id=None, max_gap_s=0.25)` creates training windows. `create_feature_windows()` has the same parameters but does not read or require reference_speed.

Each axis contributes mean, population standard deviation (`ddof=0`), minimum, and maximum, in that order. Default output is 6 axes × 4 statistics = **24 engineered features**, named accel_x_mean, accel_x_std, accel_x_min, accel_x_max, through gyro_z_max. No labels, positions, time values, or run IDs enter X. No scaling/imputation is performed.

For N records, W window size, and S step, window count is `floor((N-W)/S)+1`. Defaults are 10 samples with step 1. At approximately 10 Hz this is roughly one second of samples, although first-to-last timestamp span is approximately 0.9 s. Window duration depends on actual cadence; 10 Hz is not assumed globally.

Records remain chronological and unshuffled. Window metadata records source run, start/end/target indices, and start/end/target times. Index positions refer to the cleaned input records, not necessarily original raw CSV rows. Every record, including any unused tail, is validated. Positive integer sizes reject booleans; insufficient records, missing/nonnumeric/nonfinite features, malformed targets, negative labels, nonfinite/negative time, repeated/decreasing times, and statistic overflow fail clearly. A one-sample window has standard deviation zero.

The configurable max_gap_s defaults to 0.25 s to avoid windows silently spanning outages in roughly 10 Hz data. Any larger consecutive gap fails the supplied sequence; segment into independent runs/windows before calling, or explicitly choose a limit appropriate to acquisition cadence. There is no interpolation or gap repair. This conservative operational limit is not a validated model-performance threshold. Inference uses the stored limit.

The returned window dictionary contains X, feature_names, window_metadata, window_size, step_size, raw_feature_columns, and max_gap_s. Training additionally includes y. X and y are NumPy arrays, not JSON lists.

## Random Forest baseline and training

`train_speed_model(X, y, random_state=42, n_estimators=100)` returns model, training_metadata, and training_metrics. The estimator is scikit-learn RandomForestRegressor with 100 trees by default, bootstrap enabled, squared-error criterion, and n_jobs=1. Remaining parameters use recorded-library defaults (including unrestricted tree depth). Seed and tree count are validated and configurable. A fixed seed makes repeat runs deterministic in the same dependency environment.

X must be a nonempty finite 2D numeric matrix within the estimator's float32 input range, and y a matching nonempty finite 1D nonnegative vector. Strings and booleans are rejected. MAE and RMSE are in m/s; R² is unitless and null for fewer than two labels or a constant target where it is not informative. These metrics describe predictions on the training windows only. Metric overflow fails instead of presenting nonfinite results.

`train_from_pairs(pairs, ...)` calls Issue #2 and windows each run separately before combining training examples. No window crosses run boundaries. Run IDs combine pair index and smartphone filename; resolved sources, counts, label header, synchronization, and quality summaries remain in the returned training report. Reused files and invalid pairs fail; no run is silently skipped. No random sample-level split is made.

The return includes model_bundle, per_run_preprocessing, window_metadata, total_window_count, total_preprocessed_records, training_metrics, and training reference/prediction ranges. Model artifacts do not contain these raw records, X/y matrices, or per-window metadata. They contain only the fitted forest and inference/training summary metadata.

## Saving and loading

`save_model(model_bundle, output_path)` creates a new compressed joblib artifact, creating parents as needed. Existing files or links are never overwritten. `.gitignore` excludes `*.joblib`; keep artifacts and real CSVs out of commits.

The schema-version-1 bundle includes model, model_type, raw_feature_columns, engineered_feature_names, window_size, step_size, max_gap_s, target_name, target_unit, output_physical_constraint, training_metadata, training_metrics, and dependency/Python versions. Feature order, target unit, version, fitted forest shape, and required keys are validated on save/load/inference. Unknown bundle keys are rejected, helping prevent accidental storage of raw training arrays. The saved sklearn version must match the current one; changing schema or dependency versions may require retraining.

**Only load trusted joblib artifacts.** Deserialization can execute code before metadata validation. Validation is not a sandbox or proof that a model is safe. Missing files, directories, malformed artifacts, unsupported schema, and incompatible metadata fail clearly. See the official [scikit-learn persistence guidance](https://scikit-learn.org/stable/model_persistence.html).

## Inference API and Issue #14

```python
from ai.speed_estimation import load_model, predict_from_records

bundle = load_model("models/speed_model.joblib")  # Trusted local artifact only.
# Each record needs time_s plus the bundle's allowed IMU axes; no reference_speed.
predictions = predict_from_records(bundle, imu_records, run_id="drive-session")
```

`predict_speed(model, X)` returns finite predictions clipped to >=0 as an output physical constraint; training labels are never clipped or altered. `predict_from_records()` validates the bundle and uses precisely its window configuration and feature ordering. Each returned record has time_s (window-end time), estimated_speed (m/s), target_index, and run_id. It requires no GPS or vehicle reference fields.

This is a batch API without a hidden rolling buffer. Issue #14 will supply ordered IMU windows, manage buffering/stride and warm-up, map the relative window-end epoch to Unix milliseconds, and connect estimated speed to Dead Reckoning. This local output is not the full Issue #8 AIOutput: estimated_acceleration and motion_state are not implemented here. No navigation integration, Android/Flutter code, ONNX conversion, or mobile deployment is included.

## CLI

PowerShell, from the repository root (paths are examples):

```powershell
python -B ai/speed_estimation.py train `
  --pair "C:\data\S-run1.csv" "C:\data\V-run1.csv" `
  --pair "C:\data\S-run2.csv" "C:\data\V-run2.csv" `
  --window-size 10 --step-size 1 --n-estimators 100 --random-state 42 `
  --tolerance 0.055 --max-gap 0.25 `
  --model-output "models/speed_model.joblib"
```

Omit --model-output to train without saving. JSON output includes run/record/window counts, preprocessing summaries, feature schema, m/s unit, model type, training metrics, and optional artifact path. Inference is provided as a Python API; there is no separate inference CLI or duplicate preprocessed-CSV loader.

## Tests

Tests use synthetic records and temporary S/V CSVs/artifacts, without requiring IO-VNBD:

```text
python -B -m unittest discover -s ai/tests -v
python -B -m unittest discover -s dataset/tests -v
python -B -m unittest discover -s preprocessing/tests -v
python -B -m unittest discover -s navigation_engine/dead_reckoning/tests -v
python -B -m unittest discover -s navigation_engine/alignment/tests -v
python -B -m unittest discover -s navigation_engine/gnss/tests -v
python -B -m unittest discover -s navigation_engine/mode_switching/tests -v
```

## Limitations and Issue #4

**Training metrics are NOT proof of generalization. A single Vta25 run is insufficient to claim model accuracy or the SIH drift target.** Proper evaluation on different complete runs belongs to Issue #4. Split by run/driver before constructing train/held-out windows, and never randomly split neighboring windows from a shared sequence. Review duplicated recordings across folder collections, input quality, speed-label provenance, synchronization, and held-out leakage. No validation/test split or formal evaluation is implemented here.

Short IMU windows do not uniquely determine absolute vehicle speed; the model can learn correlations with motion/vibration rather than a universal physical speed estimator. Performance depends on phone mounting, vehicle, road conditions, driver behavior, sampling cadence, dataset quality, and synchronization. Issue #5 alignment may later improve mounting robustness but is not applied automatically. Random Forest cannot reliably extrapolate beyond its training target range. Unbounded trees may yield large artifacts as data grows; review memory, batch/window latency, and mobile conversion in later integration. Local desktop measurements are not smartphone performance guarantees.

The baseline choice and parameters follow the official [RandomForestRegressor documentation](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.RandomForestRegressor.html).

## Local Vta25 smoke check

The supplied local synchronized S-Vta25.csv / V-vta25.csv pair was processed through Issue #2 with mps labels and used for training and prediction on the same run. **IN-SAMPLE TRAINING METRICS ONLY:**

| Item | Observed value |
| --- | --- |
| Clean records | 646 |
| Window size / step | 10 / 1 |
| Training windows / engineered features | 637 / 24 |
| Forest | 100 trees, random_state=42, n_jobs=1 |
| Target | reference_speed at window end, m/s |
| Training MAE | 0.0792299145 m/s |
| Training RMSE | 0.1801897665 m/s |
| Training R² | 0.9976394846 |
| Predicted speed range | 0.0037916667–13.4757111111 m/s |
| Reference window-target range | 0–13.4961111111 m/s |
| Compressed serialized bundle | 1,473,695 bytes (approximately 1.47 MB) |
| Median one-window inference | Approximately 4.63 ms on this desktop |

Latency was measured after warm-up over 20 calls to predict_from_records with 10 IMU-only samples, including bundle validation, feature extraction, and prediction. It excludes file loading and sensor collection and is not a mobile benchmark. Artifact size was measured using save_model; load_model reproduced identical predictions. The temporary artifact was removed; neither raw nor preprocessed real CSVs were exported into Navsync. SHA-256 hashes of both raw inputs were unchanged.

Environment: Python 3.14.7, NumPy 2.5.3, scikit-learn 1.9.0, joblib 1.6.0. Exact timings and serialized sizes can vary with environment. These results do not demonstrate generalization, held-out test accuracy, or achievement of the SIH drift target. Issue #4 must evaluate different complete runs.
