"""Held-out-run evaluation of the unchanged Issue #3 IMU speed baseline."""

import argparse
import csv
import hashlib
import json
import math
from numbers import Real
from pathlib import Path
import re
import statistics
import sys

import numpy as np
from sklearn.metrics import r2_score

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from preprocessing.imu_preprocessing import preprocess_pair
from ai.speed_estimation import create_windows, predict_speed, train_from_pairs

PREDICTION_FIELDS = ("run_id", "time_s", "reference_speed_mps", "predicted_speed_mps",
                     "error_mps", "absolute_error_mps")


def _values(values, name):
    try:
        array = np.asarray(values, dtype=object)
        if array.ndim != 1 or not len(array):
            raise ValueError(f"{name} must be a nonempty 1D sequence")
        if any(isinstance(v, (bool, np.bool_)) or not isinstance(v, Real) for v in array):
            raise ValueError(f"{name} must contain numbers, not strings/bools")
        result = np.asarray(array, dtype=float)
    except (TypeError, OverflowError) as exc:
        raise ValueError(f"Invalid {name}") from exc
    if not np.isfinite(result).all():
        raise ValueError(f"{name} must be finite")
    return result


def _prediction_arrays(y_true, y_pred):
    truth, pred = _values(y_true, "y_true"), _values(y_pred, "y_pred")
    if len(truth) != len(pred) or np.any(truth < 0):
        raise ValueError("Lengths must match and ground truth must be nonnegative")
    return truth, pred


def evaluate_predictions(y_true, y_pred) -> dict:
    """Unmodified predictions; signed error is prediction minus reference."""
    truth, pred = _prediction_arrays(y_true, y_pred)
    with np.errstate(over="ignore", invalid="ignore"):
        error = pred-truth
        absolute = np.abs(error)
        mae, rmse = float(np.mean(absolute)), float(np.sqrt(np.mean(error**2)))
        result = dict(sample_count=len(truth), mae_mps=mae, rmse_mps=rmse,
                      r2=float(r2_score(truth, pred)) if len(truth)>1 and np.ptp(truth)>0 else None,
                      bias_mps=float(np.mean(error)), median_absolute_error_mps=float(np.median(absolute)),
                      maximum_absolute_error_mps=float(np.max(absolute)), mae_kmh=mae*3.6, rmse_kmh=rmse*3.6)
    if any(value is not None and not math.isfinite(value) for value in result.values()):
        raise ValueError("Metric calculation overflow")
    return result


def summarize_speed_bands(y_true, y_pred) -> dict:
    """Ground-truth bands [0,5), [5,10), [10,15), [15,infinity)."""
    truth, pred = _prediction_arrays(y_true, y_pred)
    result = {}
    for name, low, high in (("0-5",0,5), ("5-10",5,10), ("10-15",10,15), ("15+",15,float("inf"))):
        mask = (truth >= low) & (truth < high)
        metrics = evaluate_predictions(truth[mask], pred[mask]) if mask.any() else None
        result[name] = {k: metrics[k] if metrics else (0 if k == "sample_count" else None)
                        for k in ("sample_count", "mae_mps", "rmse_mps", "bias_mps")}
    return result


def summarize_stationary_moving(y_true, y_pred) -> dict:
    """Stationary <=0.5 m/s; false motion when its prediction is >1.0 m/s."""
    truth, pred = _prediction_arrays(y_true, y_pred)
    stationary = truth <= .5
    moving = ~stationary
    stationary_metrics = evaluate_predictions(truth[stationary], pred[stationary]) if stationary.any() else None
    moving_metrics = evaluate_predictions(truth[moving], pred[moving]) if moving.any() else None
    return dict(stationary_sample_count=int(stationary.sum()),
                stationary_predicted_speed_mean_mps=float(np.mean(pred[stationary])) if stationary.any() else None,
                stationary_mae_mps=stationary_metrics["mae_mps"] if stationary_metrics else None,
                moving_sample_count=int(moving.sum()), moving_mae_mps=moving_metrics["mae_mps"] if moving_metrics else None,
                false_motion_rate=float(np.mean(pred[stationary] > 1.0)) if stationary.any() else None)


def validate_pairs(pairs) -> list[dict]:
    """Resolve files, reject reused identities/content/run IDs, verify S/V stems."""
    if not isinstance(pairs, (list, tuple)) or not pairs:
        raise ValueError("Provide a nonempty list of S/V pairs")
    paths_seen, physical_seen, hashes_seen, runs_seen = set(), set(), set(), set()
    runs = []
    for pair in pairs:
        if not isinstance(pair, (list, tuple)) or len(pair) != 2:
            raise ValueError("Each pair must contain exactly two paths")
        paths, hashes = [], []
        for raw in pair:
            if not isinstance(raw, (str, Path)):
                raise ValueError("Pair entries must be file paths")
            path = Path(raw).resolve()
            if not path.exists():
                raise FileNotFoundError(f"Run file does not exist: {path}")
            if not path.is_file():
                raise ValueError(f"Run path is not a file: {path}")
            stat = path.stat()
            physical = (stat.st_dev, stat.st_ino)
            with path.open("rb") as stream:
                hasher = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1024*1024), b""):
                    hasher.update(chunk)
                digest = hasher.hexdigest()
            if path in paths_seen or physical in physical_seen or digest in hashes_seen:
                raise ValueError(f"Duplicate/overlapping file or identical content: {path}")
            paths_seen.add(path)
            physical_seen.add(physical)
            hashes_seen.add(digest)
            paths.append(str(path))
            hashes.append(digest)
        ids = [re.sub(r"^[sv]-", "", Path(p).stem, flags=re.I).casefold().strip() for p in paths]
        if not ids[0] or ids[0] != ids[1]:
            raise ValueError(f"S/V filenames must identify the same run: {paths}")
        if ids[0] in runs_seen:
            raise ValueError(f"Duplicate run ID: {ids[0]}")
        runs_seen.add(ids[0])
        runs.append(dict(run_id=ids[0], smartphone_path=paths[0], vehicle_path=paths[1],
                         smartphone_sha256=hashes[0], vehicle_sha256=hashes[1]))
    return runs


def _test_summary(clean):
    metadata = clean["metadata"]
    return dict(clean_records=len(clean["records"]), selected_label=metadata["selected_label_header"],
                target_unit=metadata["output_speed_unit"], synchronization=clean["synchronization"],
                quality=clean["quality"], smartphone_sampling=metadata["smartphone_time"]["diagnostics"],
                vehicle_sampling=metadata["vehicle_time"]["diagnostics"],
                alignment_assumption=metadata["alignment_assumption"])


def evaluate_holdout(training_pairs, test_pair, *, window_size=10, step_size=1,
                     n_estimators=100, random_state=42, tolerance_s=.055, max_gap_s=.25) -> dict:
    """Train only complete training runs; test independently with the bundle schema."""
    if not isinstance(training_pairs, (list,tuple)) or not training_pairs:
        raise ValueError("At least one training run is required")
    runs = validate_pairs([*training_pairs, test_pair])
    trained = train_from_pairs([(r["smartphone_path"],r["vehicle_path"]) for r in runs[:-1]],
                               window_size=window_size, step_size=step_size, n_estimators=n_estimators,
                               random_state=random_state, tolerance_s=tolerance_s, max_gap_s=max_gap_s)
    bundle, held = trained["model_bundle"], runs[-1]
    clean = preprocess_pair(held["smartphone_path"], held["vehicle_path"],
                            speed_unit="mps", tolerance_s=tolerance_s)
    if clean["metadata"]["output_speed_unit"] != bundle["target_unit"]:
        raise ValueError("Test label unit does not match trained model")
    windows = create_windows(clean["records"], bundle["window_size"], bundle["step_size"],
                             bundle["raw_feature_columns"], held["run_id"], max_gap_s=bundle["max_gap_s"])
    if windows["feature_names"] != bundle["engineered_feature_names"]:
        raise ValueError("Test feature order differs from trained model")
    predicted = predict_speed(bundle["model"], windows["X"])
    truth = windows["y"]
    metrics = evaluate_predictions(truth, predicted)
    rows = [dict(run_id=held["run_id"], time_s=m["target_time_s"], reference_speed_mps=float(y),
                 predicted_speed_mps=float(p), error_mps=float(p-y), absolute_error_mps=float(abs(p-y)))
            for m,y,p in zip(windows["window_metadata"], truth, predicted)]
    return dict(method="HOLDOUT-RUN", metrics_scope="HELD-OUT RUN PERFORMANCE",
                training_run_ids=[r["run_id"] for r in runs[:-1]], test_run_id=held["run_id"], run_files=runs,
                training_record_count=trained["total_preprocessed_records"], training_window_count=trained["total_window_count"],
                test_record_count=len(clean["records"]), test_window_count=len(truth),
                model_configuration={k:bundle[k] for k in ("model_type","raw_feature_columns","engineered_feature_names",
                    "window_size","step_size","max_gap_s","target_unit","versions")},
                training_metadata=bundle["training_metadata"], training_metrics=trained["training_metrics"],
                preprocessing=dict(training=trained["per_run_preprocessing"], test=_test_summary(clean)),
                metrics=metrics, speed_bands=summarize_speed_bands(truth,predicted),
                stationary_moving=summarize_stationary_moving(truth,predicted),
                reference_range_mps=[float(truth.min()),float(truth.max())],
                prediction_range_mps=[float(predicted.min()),float(predicted.max())], predictions=rows)


def leave_one_run_out(pairs, **configuration) -> dict:
    """Fresh forest per run; overall metrics computed from concatenated predictions."""
    runs = validate_pairs(pairs)
    if len(runs) < 2:
        raise ValueError("Leave-One-Run-Out requires at least two runs")
    normalized = [(r["smartphone_path"],r["vehicle_path"]) for r in runs]
    folds = [evaluate_holdout(normalized[:i]+normalized[i+1:], pair, **configuration)
             for i,pair in enumerate(normalized)]
    rows = [row for fold in folds for row in fold["predictions"]]
    truth, predicted = [r["reference_speed_mps"] for r in rows], [r["predicted_speed_mps"] for r in rows]
    maes = [fold["metrics"]["mae_mps"] for fold in folds]
    best, worst = min(folds,key=lambda f:f["metrics"]["mae_mps"]), max(folds,key=lambda f:f["metrics"]["mae_mps"])
    return dict(method="Leave-One-Run-Out (LORO)", metrics_scope="HELD-OUT RUN PERFORMANCE",
                number_of_runs=len(runs), number_of_folds=len(folds), folds=folds,
                total_held_out_prediction_count=len(rows), aggregate_metrics=evaluate_predictions(truth,predicted),
                speed_bands=summarize_speed_bands(truth,predicted),
                stationary_moving=summarize_stationary_moving(truth,predicted),
                fold_mae_summary=dict(mean_mps=statistics.mean(maes), std_mps=statistics.pstdev(maes),
                    best_fold=best["test_run_id"], best_mae_mps=min(maes),
                    worst_fold=worst["test_run_id"], worst_mae_mps=max(maes)))


def export_results(result: dict, *, json_output=None, predictions_output=None) -> None:
    """Exclusive-create reports; no overwrite of any existing raw/report file."""
    outputs = [Path(p) for p in (json_output,predictions_output) if p is not None]
    if len({p.resolve() for p in outputs}) != len(outputs):
        raise ValueError("JSON and CSV outputs must be distinct")
    if any(p.exists() or p.is_symlink() for p in outputs):
        raise FileExistsError("Evaluation output already exists")
    for path in outputs:
        path.parent.mkdir(parents=True,exist_ok=True)
    if json_output is not None:
        text = json.dumps(result,indent=2,allow_nan=False)
        with Path(json_output).open("x",encoding="utf-8") as stream:
            stream.write(text+"\n")
    if predictions_output is not None:
        rows = result["predictions"] if "predictions" in result else [r for f in result["folds"] for r in f["predictions"]]
        with Path(predictions_output).open("x",encoding="utf-8",newline="") as stream:
            writer = csv.DictWriter(stream,fieldnames=PREDICTION_FIELDS)
            writer.writeheader()
            writer.writerows(rows)


def _summary(result):
    summary = {k:v for k,v in result.items() if k not in ("predictions","folds")}
    if "folds" in result:
        summary["folds"] = [{k:f[k] for k in ("test_run_id","training_run_ids","training_window_count",
                                             "test_window_count","metrics","stationary_moving")} for f in result["folds"]]
    return summary


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode",required=True)
    for mode in ("holdout","loro"):
        cmd = commands.add_parser(mode)
        if mode == "holdout":
            cmd.add_argument("--train-pair",nargs=2,action="append",required=True)
            cmd.add_argument("--test-pair",nargs=2,required=True)
        else:
            cmd.add_argument("--pair",nargs=2,action="append",required=True)
        for name,default in (("window-size",10),("step-size",1),("n-estimators",100),("random-state",42)):
            cmd.add_argument("--"+name,type=int,default=default)
        cmd.add_argument("--tolerance",type=float,default=.055)
        cmd.add_argument("--max-gap",type=float,default=.25)
        cmd.add_argument("--json-output")
        cmd.add_argument("--predictions-output")
    args = parser.parse_args(argv)
    config = dict(window_size=args.window_size,step_size=args.step_size,n_estimators=args.n_estimators,
                  random_state=args.random_state,tolerance_s=args.tolerance,max_gap_s=args.max_gap)
    try:
        result = (evaluate_holdout(args.train_pair,args.test_pair,**config) if args.mode == "holdout"
                  else leave_one_run_out(args.pair,**config))
        export_results(result,json_output=args.json_output,predictions_output=args.predictions_output)
        print(json.dumps(_summary(result),indent=2,allow_nan=False))
    except (OSError,ValueError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
