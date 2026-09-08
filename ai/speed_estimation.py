"""IMU-only Random Forest speed baseline; metrics are in-sample diagnostics."""

import argparse
import json
import math
from numbers import Real
from pathlib import Path
import platform
import sys

try:
    import joblib
    import numpy as np
    import sklearn
    from sklearn.ensemble import RandomForestRegressor
    from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
except ImportError as exc:
    raise ImportError("Issue #3 requires numpy, scikit-learn, and joblib: python -m pip install -r requirements.txt") from exc

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from preprocessing.imu_preprocessing import preprocess_pair

DEFAULT_FEATURES = ("accel_x", "accel_y", "accel_z", "gyro_x", "gyro_y", "gyro_z")
STATISTICS = ("mean", "std", "min", "max")
SCHEMA_VERSION = 1
MODEL_TYPE = "RandomForestRegressor"
CONSTRAINT = "max(0, prediction)"


def validate_feature_columns(feature_columns=None) -> list[str]:
    """Only explicitly allowed IMU axes may enter the model, in supplied order."""
    columns = list(DEFAULT_FEATURES) if feature_columns is None else feature_columns
    if not isinstance(columns, (list, tuple)) or not columns:
        raise ValueError("feature_columns must be a nonempty list/tuple of allowed IMU axes")
    if any(type(c) is not str or c not in DEFAULT_FEATURES for c in columns):
        raise ValueError("Only accel_x/y/z and gyro_x/y/z are allowed; target/GNSS/vehicle leakage rejected")
    if len(set(columns)) != len(columns):
        raise ValueError("Duplicate feature columns")
    return list(columns)


def _positive_int(value, name):
    if type(value) is not int or value <= 0:
        raise ValueError(f"{name} must be a positive integer, not bool")


def _finite(value, name):
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, Real):
        raise ValueError(f"{name} must be numeric, not a string/bool/missing value")
    try:
        number = float(value)
    except (ValueError, OverflowError) as exc:
        raise ValueError(f"{name} is outside floating-point range") from exc
    if not math.isfinite(number):
        raise ValueError(f"{name} must be finite")
    return number


def _names(columns):
    return [f"{column}_{stat}" for column in columns for stat in STATISTICS]


def create_feature_windows(records, window_size=10, step_size=1, feature_columns=None,
                           run_id=None, *, max_gap_s=.25) -> dict:
    """Inference windows need only time_s plus selected IMU axes; never labels.

    Reject gaps over max_gap_s instead of aggregating across sensor outages.
    Caller must choose an appropriate limit for its acquisition cadence.
    """
    _positive_int(window_size, "window_size")
    _positive_int(step_size, "step_size")
    columns = validate_feature_columns(feature_columns)
    max_gap_s = _finite(max_gap_s, "max_gap_s")
    if max_gap_s <= 0:
        raise ValueError("max_gap_s must be positive")
    if run_id is not None and (type(run_id) is not str or not run_id):
        raise ValueError("run_id must be a nonempty string or None")
    if len(records) < window_size:
        raise ValueError("Fewer records than window_size")
    times, axes = [], []
    for i, row in enumerate(records):
        if not isinstance(row, dict):
            raise ValueError(f"Record {i} must be a dictionary")
        times.append(_finite(row.get("time_s"), f"time_s at {i}"))
        axes.append([_finite(row.get(c), f"{c} at {i}") for c in columns])
    if any(t < 0 for t in times):
        raise ValueError("time_s must be nonnegative")
    if any(b <= a for a, b in zip(times, times[1:])):
        raise ValueError("Records must be strictly chronological; no sorting or repair")
    if any(b-a > max_gap_s for a, b in zip(times, times[1:])):
        raise ValueError("Timestamp gap exceeds max_gap_s; segment the run before windowing")
    data = np.asarray(axes, dtype=float)
    features, metadata = [], []
    for start in range(0, len(records)-window_size+1, step_size):
        end = start+window_size-1
        window = data[start:end+1]
        with np.errstate(over="ignore", invalid="ignore"):
            features.append(np.stack((window.mean(axis=0), window.std(axis=0, ddof=0),
                                      window.min(axis=0), window.max(axis=0)), axis=1).ravel())
        metadata.append(dict(run_id=run_id, start_index=start, end_index=end, target_index=end,
                             start_time_s=times[start], end_time_s=times[end], target_time_s=times[end]))
    X = np.asarray(features)
    if not np.isfinite(X).all():
        raise ValueError("Feature statistics overflow")
    return dict(X=X, feature_names=_names(columns), window_metadata=metadata,
                window_size=window_size, step_size=step_size, raw_feature_columns=columns,
                max_gap_s=max_gap_s)


def create_windows(records, window_size=10, step_size=1, feature_columns=None,
                   run_id=None, *, max_gap_s=.25) -> dict:
    """Training windows: nonnegative reference_speed at the END of each window."""
    result = create_feature_windows(records, window_size, step_size, feature_columns, run_id,
                                    max_gap_s=max_gap_s)
    labels = [_finite(row.get("reference_speed"), f"reference_speed at {i}") for i,row in enumerate(records)]
    if any(y < 0 for y in labels):
        raise ValueError("Negative reference speed")
    result["y"] = np.asarray([labels[m["end_index"]] for m in result["window_metadata"]])
    return result


def _array(values, ndim, name):
    try:
        raw = np.asarray(values, dtype=object)
        if raw.ndim != ndim or raw.size == 0:
            raise ValueError(f"{name} must be a nonempty {ndim}D array")
        array = np.asarray([_finite(v, name) for v in raw.flat]).reshape(raw.shape)
    except (TypeError, OverflowError) as exc:
        raise ValueError(f"Invalid {name}") from exc
    if name == "X" and np.any(np.abs(array) > np.finfo(np.float32).max):
        raise ValueError("X exceeds the estimator's float32 range")
    return array


def predict_speed(model, X) -> np.ndarray:
    """Predict finite m/s values; enforce a nonnegative output constraint."""
    X = _array(X, 2, "X")
    if not callable(getattr(model, "predict", None)):
        raise ValueError("Model must expose predict")
    if X.shape[1] != getattr(model, "n_features_in_", None):
        raise ValueError("Feature count differs from fitted model")
    predictions = np.asarray(model.predict(X), dtype=float)
    if predictions.shape != (len(X),) or not np.isfinite(predictions).all():
        raise ValueError("Model returned invalid predictions")
    return np.maximum(predictions, 0)


def train_speed_model(X, y, *, random_state=42, n_estimators=100) -> dict:
    """Fit RandomForestRegressor; no split or claim of held-out performance."""
    _positive_int(n_estimators, "n_estimators")
    if type(random_state) is not int or not 0 <= random_state <= 2**32-1:
        raise ValueError("random_state must be an integer in [0, 2**32-1]")
    X, y = _array(X, 2, "X"), _array(y, 1, "y")
    if len(X) != len(y) or np.any(y < 0):
        raise ValueError("X/y length mismatch or negative labels")
    model = RandomForestRegressor(n_estimators=n_estimators, random_state=random_state,
                                  n_jobs=1, criterion="squared_error", bootstrap=True)
    model.fit(X, y)
    predicted = predict_speed(model, X)
    with np.errstate(over="ignore", invalid="ignore"):
        metrics = dict(mae=float(mean_absolute_error(y, predicted)),
                       rmse=float(math.sqrt(mean_squared_error(y, predicted))),
                       r2=float(r2_score(y, predicted)) if len(y) > 1 and np.ptp(y) > 0 else None)
    if any(v is not None and not math.isfinite(v) for v in metrics.values()):
        raise ValueError("Training metrics overflow")
    return dict(model=model, training_metadata=dict(model_type=MODEL_TYPE, training_windows=len(y),
                input_features=X.shape[1], random_state=random_state, n_estimators=n_estimators,
                metrics_scope="IN-SAMPLE TRAINING METRICS"), training_metrics=metrics)


def train_from_pairs(pairs, *, window_size=10, step_size=1, feature_columns=None,
                     random_state=42, n_estimators=100, tolerance_s=.055, max_gap_s=.25) -> dict:
    """Reuse Issue #2 with explicit m/s labels; window each run independently."""
    if not isinstance(pairs, (list, tuple)) or not pairs:
        raise ValueError("At least one S/V pair is required")
    columns = validate_feature_columns(feature_columns)
    matrices, targets, summaries, metadata = [], [], [], []
    used = set()
    for index, pair in enumerate(pairs):
        if not isinstance(pair, (list, tuple)) or len(pair) != 2:
            raise ValueError("Each pair must contain smartphone and vehicle paths")
        paths = tuple(str(Path(p).resolve()) for p in pair)
        if any(p in used for p in paths):
            raise ValueError("Input file reused across training pairs")
        used.update(paths)
        run_id = f"{index}:{Path(pair[0]).stem}"
        try:
            clean = preprocess_pair(*pair, tolerance_s=tolerance_s, speed_unit="mps")
            if clean["metadata"]["output_speed_unit"] != "m/s":
                raise ValueError("Preprocessing did not produce m/s labels")
            windows = create_windows(clean["records"], window_size, step_size, columns, run_id,
                                     max_gap_s=max_gap_s)
        except (ValueError, OSError) as exc:
            raise ValueError(f"Run {run_id} failed: {exc}") from exc
        matrices.append(windows["X"])
        targets.append(windows["y"])
        metadata.extend(windows["window_metadata"])
        summaries.append(dict(run_id=run_id, smartphone_file=paths[0], vehicle_file=paths[1],
                              clean_records=len(clean["records"]), windows=len(windows["y"]),
                              label_header=clean["metadata"]["selected_label_header"],
                              synchronization=clean["synchronization"], quality=clean["quality"]))
    X, y = np.concatenate(matrices), np.concatenate(targets)
    trained = train_speed_model(X, y, random_state=random_state, n_estimators=n_estimators)
    bundle = dict(schema_version=SCHEMA_VERSION, model=trained["model"], model_type=MODEL_TYPE,
                  raw_feature_columns=columns, engineered_feature_names=_names(columns),
                  window_size=window_size, step_size=step_size, max_gap_s=max_gap_s,
                  target_name="reference_speed", target_unit="m/s", output_physical_constraint=CONSTRAINT,
                  training_metadata=trained["training_metadata"], training_metrics=trained["training_metrics"],
                  versions=dict(python=platform.python_version(), numpy=np.__version__,
                                sklearn=sklearn.__version__, joblib=joblib.__version__))
    return dict(model_bundle=bundle, per_run_preprocessing=summaries, window_metadata=metadata,
                total_window_count=len(y), total_preprocessed_records=sum(r["clean_records"] for r in summaries),
                training_metrics=trained["training_metrics"],
                training_reference_range_mps=[float(y.min()), float(y.max())],
                training_prediction_range_mps=[float(v) for v in (predict_speed(trained["model"], X).min(),
                                                                 predict_speed(trained["model"], X).max())])


def _validate_bundle(bundle):
    expected = {"schema_version", "model", "model_type", "raw_feature_columns", "engineered_feature_names",
                "window_size", "step_size", "max_gap_s", "target_name", "target_unit",
                "output_physical_constraint", "training_metadata", "training_metrics", "versions"}
    if not isinstance(bundle, dict) or set(bundle) != expected:
        raise ValueError("Invalid model bundle fields (raw training data must not be stored)")
    if type(bundle["schema_version"]) is not int or bundle["schema_version"] != SCHEMA_VERSION:
        raise ValueError("Unsupported model schema version")
    if (bundle["model_type"] != MODEL_TYPE or bundle["target_name"] != "reference_speed"
            or bundle["target_unit"] != "m/s" or bundle["output_physical_constraint"] != CONSTRAINT):
        raise ValueError("Invalid model type, target, units, or prediction constraint")
    columns = validate_feature_columns(bundle["raw_feature_columns"])
    if bundle["engineered_feature_names"] != _names(columns):
        raise ValueError("Engineered feature order/schema mismatch")
    for key in ("window_size", "step_size"):
        _positive_int(bundle[key], key)
    if _finite(bundle["max_gap_s"], "max_gap_s") <= 0:
        raise ValueError("Invalid max_gap_s")
    if not isinstance(bundle["versions"], dict) or bundle["versions"].get("sklearn") != sklearn.__version__:
        raise ValueError("Model requires its recorded scikit-learn version; retrain or use matching environment")
    model = bundle["model"]
    if not isinstance(model, RandomForestRegressor) or not hasattr(model, "estimators_"):
        raise ValueError("Expected a fitted RandomForestRegressor")
    if model.n_features_in_ != len(_names(columns)) or model.n_outputs_ != 1:
        raise ValueError("Model feature count/output shape mismatch")
    if not isinstance(bundle["training_metadata"], dict) or not isinstance(bundle["training_metrics"], dict):
        raise ValueError("Invalid training metadata")


def save_model(model_bundle: dict, output_path: str | Path) -> None:
    """Save metadata and forest only; exclusively create a new trusted artifact."""
    _validate_bundle(model_bundle)
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        joblib.dump(model_bundle, stream, compress=3)


def load_model(path: str | Path) -> dict:
    """Load TRUSTED joblib only: deserialization executes code before validation."""
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"Model does not exist: {path}")
    if not path.is_file():
        raise ValueError(f"Model path is not a file: {path}")
    try:
        bundle = joblib.load(path)
        _validate_bundle(bundle)
    except Exception as exc:
        raise ValueError(f"Malformed or incompatible model artifact: {exc}") from exc
    return bundle


def predict_from_records(model_bundle: dict, records, *, run_id=None) -> list[dict]:
    """Predict m/s at window end using only time_s and IMU; no reference_speed."""
    _validate_bundle(model_bundle)
    windows = create_feature_windows(records, model_bundle["window_size"], model_bundle["step_size"],
                                     model_bundle["raw_feature_columns"], run_id,
                                     max_gap_s=model_bundle["max_gap_s"])
    predictions = predict_speed(model_bundle["model"], windows["X"])
    return [dict(time_s=meta["target_time_s"], estimated_speed=float(speed),
                 target_index=meta["target_index"], run_id=meta["run_id"])
            for meta, speed in zip(windows["window_metadata"], predictions)]


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    train = commands.add_parser("train")
    train.add_argument("--pair", nargs=2, action="append", required=True, metavar=("SMARTPHONE", "VEHICLE"))
    train.add_argument("--model-output")
    for name, default in (("window-size", 10), ("step-size", 1), ("n-estimators", 100), ("random-state", 42)):
        train.add_argument("--"+name, type=int, default=default)
    train.add_argument("--tolerance", type=float, default=.055)
    train.add_argument("--max-gap", type=float, default=.25)
    args = parser.parse_args(argv)
    try:
        result = train_from_pairs(args.pair, window_size=args.window_size, step_size=args.step_size,
                                  n_estimators=args.n_estimators, random_state=args.random_state,
                                  tolerance_s=args.tolerance, max_gap_s=args.max_gap)
        bundle = result["model_bundle"]
        if args.model_output:
            save_model(bundle, args.model_output)
        summary = {k:v for k,v in result.items() if k not in ("model_bundle", "window_metadata")}
        summary.update(number_of_runs=len(args.pair), window_size=args.window_size, step_size=args.step_size,
                       raw_feature_columns=bundle["raw_feature_columns"],
                       engineered_feature_count=len(bundle["engineered_feature_names"]), target_unit="m/s",
                       model_type=MODEL_TYPE, metrics_scope="IN-SAMPLE TRAINING METRICS",
                       model_output=args.model_output)
        print(json.dumps(summary, indent=2, allow_nan=False))
    except (ValueError, OSError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
