# Held-Out Run Evaluation of IMU Speed Estimation

## Purpose

Issue #4 evaluates whether the unchanged Issue #3 Random Forest transfers to complete driving runs absent from training. Issue #3's Vta25 R² of about 0.9976 and MAE of about 0.07923 m/s were **IN-SAMPLE TRAINING METRICS ONLY**. This module reports **HELD-OUT RUN PERFORMANCE** separately from training diagnostics.

No random sample-level train/test split is used. Neighboring windows overlap and are correlated; assigning them randomly to training and testing leaks temporal information. Whole runs are separated before any window construction. GPS is not a model feature; vehicle/reference speed is label-only. The six IMU axes, feature engineering, model architecture, and defaults remain in Issue #3.

## Methodology

`evaluate_holdout(training_pairs, test_pair, window_size=10, step_size=1, n_estimators=100, random_state=42, tolerance_s=0.055, max_gap_s=0.25)` validates all files jointly, trains only the training runs using `train_from_pairs()`, and independently calls Issue #2 `preprocess_pair(..., speed_unit="mps")` for the held-out run. Test windows use the trained bundle's exact raw feature columns, engineered feature order, window size, step, and gap limit. `predict_speed()` receives only the IMU feature matrix. Test labels are used only for error calculation. No fitting/tuning uses the held-out run.

`leave_one_run_out(pairs, **configuration)` requires at least two distinct runs. With N runs, it trains N fresh models: each fold holds out exactly one entire run and trains on every remaining run. Models are not reused from Issue #3 or previous folds. This is **Leave-One-Run-Out (LORO)**, not ordinary random k-fold validation. Every selected run contributes one held-out prediction sequence. No difficult fold or prediction is removed after scoring.

Overall metrics are calculated from the concatenated held-out predictions. Thus longer runs receive more weight. Mean and population standard deviation of fold MAE give a separate equally weighted per-run summary, alongside best/worst folds. Overall R² is calculated on the concatenated targets/predictions, never by averaging fold R².

## Pair validation and leakage boundaries

`validate_pairs(pairs)` accepts a nonempty list/tuple of two-path S/V pairs. It resolves paths and requires existing regular files. Run ID is the case-folded filename stem with an initial S-/V- removed; the two stems must agree. This enforces a stable run ID independent of fold order. Renaming files may be needed for other naming conventions; no fuzzy pairing is attempted.

Validation rejects duplicate pairs, reused paths across either role, physical file aliases (device/inode identity), byte-identical copied files (SHA-256), and repeated normalized run IDs. Holdout validates train and test together before training; LORO validates the entire collection. Content hashes and resolved sources are recorded in reports. These checks are conservative and cannot detect partially overlapping segments, re-encoded copies, or separate recordings of the same drive. Shared sessions, drivers, roads, or phone mounts may require stronger grouping than filenames. In particular s3a/s3c naming warrants session-provenance review; file-level separation does not establish driver/session independence.

Underlying preprocessing/windowing errors fail clearly; the API never silently skips runs. The real-data preflight exclusions below were made before any model scores, under a fixed data-quality rule. No model configuration was changed in response to held-out metrics.

## Metrics

`evaluate_predictions(y_true, y_pred)` requires nonempty equal-length one-dimensional finite numeric sequences; strings, booleans, NaN/Infinity, and negative reference speeds are rejected. Predictions may be negative for diagnostic purposes: the evaluator does not clip, retrain, or otherwise alter them. Issue #3's predictor applies its own documented nonnegative constraint. Overflow in metrics fails rather than producing invalid JSON.

- Error/bias convention: prediction minus reference. Positive bias means overestimation.
- MAE, RMSE, mean error/bias, median absolute error, and maximum absolute error are reported in m/s.
- MAE and RMSE are also reported in km/h by multiplying by 3.6.
- R² is unitless; it can be negative. It is null for a single sample or a constant reference where it is undefined/uninformative.
- Sample count refers to held-out windows, not necessarily independent observations.

Metrics must not be described as an accuracy percentage. R² is not a percentage of correct predictions. Poor held-out performance is reported rather than hidden.

## Speed bands and stationary behavior

`summarize_speed_bands()` groups by reference speed, using [0,5), [5,10), [10,15), and [15,infinity) m/s. Each band reports count, MAE, RMSE, and bias. Empty bands report zero count and null metrics.

`summarize_stationary_moving()` defines stationary as reference speed <=0.5 m/s and moving as >0.5 m/s. It reports stationary count, mean predicted speed, stationary MAE, moving count/MAE, and false-motion rate: fraction of stationary samples with predicted speed strictly >1.0 m/s. Empty groups produce null metrics. The rate is a fraction in [0,1]. These fixed diagnostic thresholds are not a deployed motion classifier or validated navigation acceptance limits.

## CLI and outputs

Install the existing root requirements and run from the repository root:

```powershell
python -B evaluation/evaluate_speed_model.py holdout `
  --train-pair "C:\data\S-run1.csv" "C:\data\V-run1.csv" `
  --test-pair "C:\data\S-run2.csv" "C:\data\V-run2.csv"

python -B evaluation/evaluate_speed_model.py loro `
  --pair "C:\data\S-run1.csv" "C:\data\V-run1.csv" `
  --pair "C:\data\S-run2.csv" "C:\data\V-run2.csv" `
  --pair "C:\data\S-run3.csv" "C:\data\V-run3.csv" `
  --window-size 10 --step-size 1 --n-estimators 100 --random-state 42 `
  --tolerance 0.055 --max-gap 0.25 `
  --json-output "evaluation/results/loro.generated.json" `
  --predictions-output "evaluation/results/predictions.csv"
```

CLI stdout is a JSON summary without thousands of prediction rows. Input errors and overlap fail with exit code 2. No model artifacts are saved. `export_results(result, json_output=..., predictions_output=...)` optionally writes full JSON and/or UTF-8 prediction CSV, creating parent folders. Existing outputs, raw files, and links are never overwritten; JSON/CSV destinations must be distinct. The two exports are not an atomic transaction: a later write error may leave an earlier file. Generated outputs under `evaluation/results/` are ignored by Git.

Holdout output includes training/test run IDs, source hashes, record/window counts, model feature schema/versions, separate training and held-out metrics, per-window rows, ranges, and preprocessing diagnostics. LORO contains per-fold holdout results, overall metrics, fold-MAE summary, speed bands, stationary behavior, and total held-out count. CSV fields are run_id, time_s, reference_speed_mps, predicted_speed_mps, error_mps, absolute_error_mps. Time is relative window-end time, not Unix time.

Public APIs: `validate_pairs`, `evaluate_predictions`, `evaluate_holdout`, `leave_one_run_out`, `summarize_speed_bands`, `summarize_stationary_moving`, `export_results`, and `main`.

## Real-data selection and preprocessing

Only the local `IO-VNBD/Synchronised V abd S datasets/Uncategorised IOVNB Dataset/` S-Dataset and V-Dataset collections were considered. Candidate S files were sorted lexicographically by case-folded run ID and matched to V files by the same ID. Stop after the first five eligible pairs. Eligibility was set before model scoring:

1. Issue #2 preprocessing succeeds with m/s labels and 0.055 s tolerance.
2. At least 100 clean records.
3. At least 95% of samples in each stream are matched, and mean absolute relative offset <=0.025 s.
4. Issue #3's default 10-sample, step-1 windows pass with max_gap_s=0.25.
5. Duplicate/overlap checks pass.

These are transparent preflight heuristics, not proof of absolute synchronization. Both streams still assume their first sample is co-temporal. All five selected runs use `Velocity (km/hr)`, explicitly converted to m/s. No missing/invalid feature rows were dropped in these runs. Median cadence is approximately 10 Hz throughout; no nonpositive intervals or large gaps were found in accepted streams.

| Run | Smartphone / vehicle filename | Clean records = matches | Windows | S / V duration (s) | Unmatched S / V | Mean / max offset (ms) |
| --- | --- | ---: | ---: | --- | --- | --- |
| s1 | S-S1.csv / V-S1.csv | 51,746 | 51,737 | 5174.499 / 5174.500 | 0 / 0 | 0.585 / 10.000 |
| s3a | S-S3a.csv / V-S3a.csv | 24,621 | 24,612 | 2462.000 / 2462.000 | 0 / 0 | 0.519 / 12.000 |
| s3c | S-S3c.csv / V-S3c.csv | 37,183 | 37,174 | 3718.199 / 3718.200 | 0 / 0 | 0.407 / 21.000 |
| vfa01 | S-Vfa01.csv / V-Vfa01.csv | 11,486 | 11,477 | 1148.500 / 1153.400 | 0 / 49 | 0.534 / 14.000 |
| vfa02 | S-Vfa02.csv / V-Vfa02.csv | 67,523 | 67,514 | 6752.201 / 6775.400 | 0 / 232 | 0.505 / 42.000 |

The vfa runs have unmatched vehicle samples, including longer vehicle recording durations; only timestamp-matched smartphone records generate windows. Small relative offsets do not validate a common absolute epoch.

Excluded candidates, in discovery order (before scoring):

| Run | Reason |
| --- | --- |
| m | One nonpositive timestamp interval, minimum -4426.717 s; one large gap; Issue #2 refuses clock repair. |
| s2 | One nonpositive interval, minimum -186.301 s. |
| s3b | One nonpositive interval, minimum -2707.512 s; negative first-to-last duration. |
| s4 | Two nonpositive intervals, minimum -5578.000 s. |

Selection stopped at vfa02, so later IDs, including Vta25, were not evaluated or excluded for performance. Vta25 could be evaluated in a later fresh fold, but was not manually inserted into this deterministic selection. No unsynchronized collection was used.

The local ignored selection manifest retains exact source paths, diagnostics, and exclusion messages. The categorized collection places s1/s3a/s3c under `S (Driver A)` and vfa01/vfa02 under `Vf (Driver E)`. These are observed folder labels; this file-level LORO includes other runs from the held-out run's driver in training and is not leave-one-driver-out evaluation. Whether s3a/s3c are segments of the same underlying drive still requires provenance review.

Real evaluation uses the unchanged defaults: 100 trees, random_state=42, n_jobs=1, window size 10, step 1, 24 IMU features, m/s target. No random seeds or configurations were tried to improve reported scores.

The real run was resumed after an interrupted session. The completed s1 checkpoint was reused only after verifying its complete source-file identities/hashes, model/window settings, dependency versions, and metrics recomputed from its saved predictions. The remaining folds were trained sequentially from fresh models and saved individually. Resuming does not retrain or discard the poor s1 result. Generated checkpoints remain local under the ignored results directory.

## Final real-data results

The completed evaluation contains all five fold checkpoints, `loro.generated.json`, `predictions.csv`, `completion.generated.json`, and `selection.generated.json` in the ignored local results directory. The completion marker records `raw_hashes_unchanged: true` and elapsed time 2163.431 s for the resumed process (not total original training time). It has no explicit status field; successful completion was corroborated by all five checkpoint/aggregate identities, recomputing aggregate metrics and diagnostic groups from saved predictions, and checking every CSV row against JSON. There are **192,514 held-out windows**. This final verification did not retrain or rerun LORO.

Each fold trains on the other four selected runs. All results below are held out; errors are in m/s unless specified.

| Held-out run | Training windows | Test windows | MAE | RMSE | R² | Bias |
| --- | --- | --- | --- | --- | --- | --- |
| s1 | 140,777 | 51,737 | 6.15372 | 7.51621 | -1.77717 | 5.84481 |
| s3a | 167,902 | 24,612 | 4.47725 | 5.76449 | 0.08843 | 0.26143 |
| s3c | 155,340 | 37,174 | 5.40519 | 7.54778 | 0.16440 | -3.41026 |
| vfa01 | 181,037 | 11,477 | 5.42702 | 6.95184 | 0.04957 | 2.75007 |
| vfa02 | 125,000 | 67,514 | 9.40579 | 10.21481 | -1.37567 | -7.99799 |

| Held-out run | Median absolute error | Maximum absolute error | MAE (km/h) | RMSE (km/h) |
| --- | --- | --- | --- | --- |
| s1 | 5.25177 | 24.95256 | 22.15340 | 27.05837 |
| s3a | 3.54080 | 24.92903 | 16.11811 | 20.75217 |
| s3c | 3.59722 | 29.26104 | 19.45870 | 27.17202 |
| vfa01 | 4.34117 | 23.16914 | 19.53728 | 25.02661 |
| vfa02 | 9.33593 | 24.31192 | 33.86086 | 36.77333 |

Aggregate metrics are computed across all held-out windows, with longer runs contributing more weight.

| Aggregate metric | Value |
| --- | --- |
| sample_count | 192,514 |
| mae_mps | 6.89202 |
| rmse_mps | 8.36091 |
| r2 | 0.23694 |
| bias_mps | -1.69525 |
| median_absolute_error_mps | 6.31130 |
| maximum_absolute_error_mps | 29.26104 |
| mae_kmh | 24.81128 |
| rmse_kmh | 30.09926 |

Equally weighted fold MAE: mean **6.17380 m/s**, population standard deviation **1.70135 m/s**. Best fold by MAE: **s3a (4.47725 m/s)**. Worst: **vfa02 (9.40579 m/s)**.

| Reference speed band (m/s) | Windows | MAE | RMSE | Bias |
| --- | --- | --- | --- | --- |
| 0-5 | 30,561 | 4.70900 | 6.05319 | 4.61294 |
| 5-10 | 42,220 | 5.16455 | 6.81512 | 4.13414 |
| 10-15 | 35,412 | 5.29032 | 6.59435 | 2.41542 |
| 15+ | 84,321 | 9.22084 | 10.23728 | -8.62672 |

Stationary means reference <=0.5 m/s; moving means >0.5 m/s. False motion is predicted speed >1.0 m/s among stationary windows.

| Run | Stationary windows | Mean stationary prediction | Stationary MAE | Moving windows | Moving MAE | False-motion rate |
| --- | --- | --- | --- | --- | --- | --- |
| s1 | 5,725 | 4.29696 | 4.23413 | 46,012 | 6.39257 | 90.69% |
| s3a | 2,179 | 3.76621 | 3.72015 | 22,433 | 4.55079 | 91.01% |
| s3c | 2,956 | 2.63569 | 2.57254 | 34,218 | 5.64990 | 84.30% |
| vfa01 | 699 | 4.23131 | 4.17273 | 10,778 | 5.50837 | 74.82% |
| vfa02 | 1,032 | 7.40544 | 7.34140 | 66,482 | 9.43784 | 81.69% |
| Aggregate | 12,591 | 4.06623 | 4.00636 | 179,923 | 7.09396 | 87.63% |

### Comparison with Issue #3

| Evaluation | MAE (m/s) | RMSE (m/s) | R² |
| --- | --- | --- | --- |
| Issue #3 Vta25 IN-SAMPLE | ~0.07923 | ~0.18019 | ~0.99764 |
| Issue #4 five-run HELD-OUT LORO | 6.89202 | 8.36091 | 0.23694 |

The near-perfect Vta25 training fit does not demonstrate generalization. Held-out performance is **weak**: MAE is 6.89202 m/s (24.81128 km/h), two folds have negative R², and even the best fold has MAE 4.47725 m/s. Negative fold R² means worse squared error than predicting that test fold's reference mean, a diagnostic benchmark rather than a deployable training-only baseline. These evaluations use different run populations and training sets, so their contrast is not a controlled estimate of a single generalization penalty.

The positive aggregate R² of 0.23694 does not establish navigation readiness and can conceal poor within-run performance. Predictions overestimate the lower speed bands and underestimate the >=15 m/s band by 8.62672 m/s on average. Stationary windows have mean predicted speed 4.06623 m/s and false-motion rate 87.63%. Opposing run-level biases partly cancel in aggregate; the aggregate bias alone understates these failures. Correlation with run-specific vibration/mounting conditions and distribution shift are plausible explanations, not causes established by this evaluation.

Only five files and overlapping windows are represented; 192,514 windows are not 192,514 independent trials. Shared drivers and possibly shared sessions further limit claims. No unseen-driver, universal-speed, or production-navigation claim is supported. The model and configuration were not tuned or modified in response to these results.

## Limitations, interpretation, and Issue #14

A short IMU window may not uniquely identify absolute vehicle speed. Steady driving at substantially different speeds can have similar longitudinal acceleration. This Random Forest can learn correlations with vibration, road texture, mounting, vehicle characteristics, driver behavior, and sensor noise. Their transfer across runs is what this evaluation probes; it does not establish a universal physical speed estimator.

Only five deterministically selected files are evaluated, with no proof of independent drivers/sessions, no absolute-time verification, and no confidence intervals accounting for correlated windows. The selection excludes clock-reset data and therefore does not represent that failure regime. Ground-truth unit correctness and reference quality remain dependent on upstream dataset validation. Overall metrics weight long runs heavily; use the per-fold and stationary breakdowns too. This is a benchmark of an existing baseline, not hyperparameter optimization.

Future work should verify session/driver grouping and absolute synchronization, compare simple training-only baselines, investigate mounting normalization through Issue #5, and collect additional diverse held-out drives. Any tuning motivated by these results requires a separate untouched final test set. Do not reuse the same held-out scores as unbiased evidence after tuning.

The current baseline should not be accepted as a validated standalone speed input for Issue #14. Issue #14 must not assume low in-sample speed error means low position drift. False motion while stationary and sustained signed speed bias can accumulate navigation errors. Integration needs independently evaluated uncertainty/fallback behavior, timestamp handling, and full trajectory-level testing. This issue implements none of those policies, no navigation changes, and no SIH drift-target claim.

## Tests

Synthetic CSVs and exports use temporary directories; automated tests do not require IO-VNBD. Run:

```text
python -B -m unittest discover -s evaluation/tests -v
python -B -m unittest discover -s ai/tests -v
python -B -m unittest discover -s preprocessing/tests -v
python -B -m unittest discover -s dataset/tests -v
python -B -m unittest discover -s navigation_engine/dead_reckoning/tests -v
python -B -m unittest discover -s navigation_engine/alignment/tests -v
python -B -m unittest discover -s navigation_engine/gnss/tests -v
python -B -m unittest discover -s navigation_engine/mode_switching/tests -v
```

Verification after completion: all eight suites above passed, totaling 182 tests (evaluation 17, AI 24, preprocessing 23, dataset 24, dead reckoning 24, alignment 27, GNSS 20, mode switching 23). No expensive real-data evaluation was rerun.
