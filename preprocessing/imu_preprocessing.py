"""Conservative, standard-library preprocessing of one IO-VNBD S/V pair."""

import argparse
from bisect import bisect_left
import csv
import json
import math
from pathlib import Path
import re
import statistics
import sys

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dataset.explore_io_vnbd import load_csv


def _pick(headers: list[str], pattern: str) -> str | None:
    matches = [h for h in headers if re.search(pattern, h, re.I)]
    if len(matches) > 1:
        raise ValueError(f"Ambiguous columns for {pattern}: {matches}")
    return matches[0] if matches else None


def _time_column(headers: list[str]) -> str | None:
    candidates = [h for h in headers if re.search(r"time|elapsed", h, re.I)
                  and not re.search(r"period|interval", h, re.I)]
    return _pick(candidates, r"time|elapsed")


def detect_smartphone_columns(headers: list[str]) -> dict:
    """Detect named axes independently of unit glyph encoding; reject ambiguity."""
    result = {"time": _time_column(headers)}
    for group, pattern in (("accelerometer", r"accel(?:erometer|eration)?"),
                           ("gravity", "gravity"), ("gyroscope", r"gyro(?:scope)?"),
                           ("magnetometer", r"magnet(?:ometer|ic\s*field)?")):
        for axis in "xyz":
            result[f"{group}_{axis}"] = _pick(headers, pattern + r"[\s_-]*" + axis + r"\b")
    for field, pattern in (("gps_speed", r"(?:gps|gnss).*speed"),
                           ("gps_latitude", r"(?:gps|gnss).*latitude"),
                           ("gps_longitude", r"(?:gps|gnss).*longitude")):
        result[field] = _pick(headers, pattern)
    return result


def detect_vehicle_columns(headers: list[str]) -> dict:
    """Identify linear-speed candidates, excluding wheel/engine/vertical rates."""
    candidates = [h for h in headers if not re.search(r"wheel|engine|vertical|rpm|rev/|rad/", h, re.I)]
    patterns = {"reference_velocity": r"^\s*(?:gps\s+)?velocity\b",
                "indicated_vehicle_speed": r"indicated\s+vehicle\s+speed",
                "latitude": r"latitude", "longitude": r"longitude", "yaw_rate": r"yaw\s*rate",
                "longitudinal_acceleration": r"longitudinal\s+acceleration",
                "lateral_acceleration": r"lateral\s+acceleration"}
    return {"time": _time_column(headers), **{k: _pick(candidates, p) for k, p in patterns.items()}}


def load_sensor_csv(path: str | Path) -> dict:
    """Reuse Issue #1 decoding; reject ragged rows rather than train on truncation."""
    headers, rows, encoding, warnings = load_csv(path)
    if not rows:
        raise ValueError("CSV contains no data rows")
    if any("short rows" in w or "extra fields" in w for w in warnings):
        raise ValueError(f"Ragged CSV rows are not accepted for preprocessing: {warnings}")
    return dict(file=str(Path(path).resolve()), encoding=encoding, headers=headers,
                rows=[dict(zip(headers, row)) for row in rows], warnings=warnings,
                timestamp_column=_time_column(headers),
                signals={"smartphone": detect_smartphone_columns(headers),
                         "vehicle": detect_vehicle_columns(headers)})


def _numeric(value: object) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    try:
        result = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return result if math.isfinite(result) else None


def parse_timestamps(rows: list[dict], column_name: str) -> dict:
    """Normalize explicit seconds/ms to first time; fail on invalid/reset clocks."""
    if not column_name:
        raise ValueError("Missing timestamp column")
    if re.search(r"\bms\b|milliseconds?", column_name, re.I):
        scale = .001
    elif re.search(r"\bseconds?\b|\bsecs?\b|\(s\)|\[s\]", column_name, re.I):
        scale = 1.0
    else:
        raise ValueError(f"Unknown timestamp unit: {column_name}")
    values = [_numeric(row.get(column_name)) for row in rows]
    invalid = [i for i, value in enumerate(values) if value is None]
    if invalid or not values:
        raise ValueError(f"Invalid or missing timestamps at zero-based rows {invalid}; count={len(values)}")
    timestamps = [(value-values[0])*scale for value in values]
    diagnostics = validate_sampling(timestamps)
    if diagnostics["nonpositive_interval_count"]:
        raise ValueError(f"Repeated/decreasing timestamps; no repair: {diagnostics}")
    return dict(timestamps=timestamps, origin_raw=values[0], scale_to_seconds=scale,
                column=column_name, diagnostics=diagnostics)


def validate_sampling(timestamps: list[float]) -> dict:
    """Describe finite timestamps; >5x median positive interval flags a gap."""
    if not timestamps or any(type(t) not in (int, float) or _numeric(t) is None for t in timestamps):
        raise ValueError("Timestamps must be a nonempty finite numeric sequence")
    diffs = [b-a for a, b in zip(timestamps, timestamps[1:])]
    duration = timestamps[-1]-timestamps[0]
    if not math.isfinite(duration) or any(not math.isfinite(d) for d in diffs):
        raise ValueError("Timestamp differences overflow")
    positive = [d for d in diffs if d > 0]
    median = (statistics.median_low(positive)/2 + statistics.median_high(positive)/2) if positive else None
    hz = 1/median if median else None
    return dict(sample_count=len(timestamps), duration_s=duration, median_interval_s=median,
                estimated_hz=hz if hz is not None and math.isfinite(hz) and all(d > 0 for d in diffs) else None,
                min_interval_s=min(diffs) if diffs else None, max_interval_s=max(diffs) if diffs else None,
                nonpositive_interval_count=sum(d <= 0 for d in diffs),
                large_gap_count=sum(d > 5*median for d in diffs) if median else 0)


def synchronize_streams(smartphone_timestamps: list[float], vehicle_timestamps: list[float],
                        tolerance_s: float = .055) -> dict:
    """Greedy chronological nearest unused vehicle sample; earlier wins ties."""
    if type(tolerance_s) not in (int, float) or _numeric(tolerance_s) is None or tolerance_s < 0:
        raise ValueError("tolerance_s must be finite and nonnegative")
    for times in (smartphone_timestamps, vehicle_timestamps):
        if validate_sampling(times)["nonpositive_interval_count"]:
            raise ValueError("Synchronization requires strictly increasing timestamps")
    pairs, offsets, start = [], [], 0
    for i, time in enumerate(smartphone_timestamps):
        k = bisect_left(vehicle_timestamps, time, lo=start)
        candidates = [j for j in (k-1, k) if start <= j < len(vehicle_timestamps)]
        if not candidates:
            continue
        j = min(candidates, key=lambda j: (abs(vehicle_timestamps[j]-time), j))
        offset = abs(vehicle_timestamps[j]-time)
        if offset <= tolerance_s:
            pairs.append((i, j))
            offsets.append(offset)
            start = j+1
    return dict(pairs=pairs, diagnostics=dict(smartphone_samples=len(smartphone_timestamps),
                vehicle_samples=len(vehicle_timestamps), matched_samples=len(pairs),
                unmatched_smartphone_samples=len(smartphone_timestamps)-len(pairs),
                unmatched_vehicle_samples=len(vehicle_timestamps)-len(pairs),
                mean_absolute_time_offset_s=statistics.mean(offsets) if offsets else None,
                max_absolute_time_offset_s=max(offsets) if offsets else None, tolerance_s=tolerance_s))


def _speed_unit(header: str) -> str | None:
    if re.search(r"km\s*/?\s*(?:hours?|hrs?|h)\b|\bkph\b", header, re.I):
        return "km/h"
    if re.search(r"\bm\s*/\s*s(?:ec(?:ond)?s?)?\b|\bmps\b", header, re.I):
        return "m/s"
    return None


def preprocess_pair(smartphone_path: str | Path, vehicle_path: str | Path,
                    tolerance_s: float = .055, speed_unit: str = "original") -> dict:
    """Extract finite IMU axes and explicitly unit-labeled vehicle speed."""
    if speed_unit not in ("original", "mps"):
        raise ValueError("speed_unit must be original or mps")
    phone, vehicle = load_sensor_csv(smartphone_path), load_sensor_csv(vehicle_path)
    sc, vc = phone["signals"]["smartphone"], vehicle["signals"]["vehicle"]
    required = {**{f"accel_{a}": sc[f"accelerometer_{a}"] for a in "xyz"},
                **{f"gyro_{a}": sc[f"gyroscope_{a}"] for a in "xyz"}}
    if not all(required.values()):
        raise ValueError(f"Missing required smartphone axes: {[k for k,v in required.items() if v is None]}")
    candidates = [vc[k] for k in ("reference_velocity", "indicated_vehicle_speed") if vc[k]]
    label = next((h for h in candidates if _speed_unit(h)), None)
    if label is None:
        raise ValueError(f"No acceptable reference speed with known linear unit: {candidates}")
    source_unit = _speed_unit(label)
    st, vt = parse_timestamps(phone["rows"], sc["time"]), parse_timestamps(vehicle["rows"], vc["time"])
    aligned = synchronize_streams(st["timestamps"], vt["timestamps"], tolerance_s)
    optional_phone = {**{f"{g}_{a}": sc[f"{g}_{a}"] for g in ("gravity", "magnetometer") for a in "xyz"},
                      "gps_latitude": sc["gps_latitude"], "gps_longitude": sc["gps_longitude"],
                      "smartphone_gps_speed": sc["gps_speed"]}
    optional_vehicle = {f"vehicle_{k}": vc[k] for k in
                        ("yaw_rate", "longitudinal_acceleration", "lateral_acceleration")}
    optional_phone = {k:v for k,v in optional_phone.items() if v}
    optional_vehicle = {k:v for k,v in optional_vehicle.items() if v}
    counts = dict(dropped_missing_accel=0, dropped_missing_gyro=0, dropped_missing_label=0,
                  dropped_invalid_numeric=0, dropped_negative_label=0, dropped_rows=0,
                  optional_invalid_values=0)
    records = []
    for i, j in aligned["pairs"]:
        sr, vr = phone["rows"][i], vehicle["rows"][j]
        raw = {k: sr[h] for k,h in required.items()}
        raw["reference_speed"] = vr[label]
        values = {k: _numeric(v) for k,v in raw.items()}
        reasons = set()
        for k, value in values.items():
            if value is None:
                reasons.add("dropped_invalid_numeric" if raw[k].strip() else
                            "dropped_missing_label" if k == "reference_speed" else
                            "dropped_missing_accel" if k.startswith("accel") else "dropped_missing_gyro")
        if values["reference_speed"] is not None and values["reference_speed"] < 0:
            reasons.add("dropped_negative_label")
        if reasons:
            counts["dropped_rows"] += 1
            for reason in reasons:
                counts[reason] += 1
            continue
        if speed_unit == "mps" and source_unit == "km/h":
            values["reference_speed"] /= 3.6
        record = {"time_s": st["timestamps"][i], **{k: values[k] for k in required}}
        for fields, row in ((optional_phone, sr), (optional_vehicle, vr)):
            for key, header in fields.items():
                record[key] = _numeric(row[header])
                counts["optional_invalid_values"] += bool(row[header].strip()) and record[key] is None
        record["reference_speed"] = values["reference_speed"]
        records.append(record)
    counts["final_record_count"] = len(records)
    feature_names = list(required) + list(optional_phone) + list(optional_vehicle)
    return dict(metadata=dict(smartphone_file=phone["file"], vehicle_file=vehicle["file"],
                smartphone_encoding=phone["encoding"], vehicle_encoding=vehicle["encoding"],
                smartphone_columns=sc, vehicle_columns=vc, selected_label_header=label,
                source_speed_unit=source_unit, output_speed_unit="m/s" if speed_unit == "mps" else source_unit,
                smartphone_time=st, vehicle_time=vt,
                optional_unit_policy="Raw values; source headers retained. Smartphone GPS speed unit unresolved.",
                alignment_assumption="First samples assumed co-temporal; relative matching does not establish absolute synchronization.",
                loader_warnings=phone["warnings"]+vehicle["warnings"]),
                synchronization=aligned["diagnostics"], quality=counts,
                feature_names=feature_names, label_name="reference_speed", records=records)


def export_preprocessed_csv(result: dict, output_path: str | Path) -> None:
    """Write a new UTF-8 CSV only; refuse input aliases and any existing target."""
    path = Path(output_path)
    sources = [Path(result["metadata"][key]).resolve() for key in ("smartphone_file", "vehicle_file")]
    if path.resolve() in sources:
        raise ValueError("Output must not overwrite a raw input")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=["time_s"]+result["feature_names"]+[result["label_name"]])
        writer.writeheader()
        writer.writerows(result["records"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smartphone", required=True)
    parser.add_argument("--vehicle", required=True)
    parser.add_argument("--output")
    parser.add_argument("--tolerance", type=float, default=.055)
    parser.add_argument("--speed-unit", choices=("original", "mps"), default="original")
    args = parser.parse_args(argv)
    try:
        result = preprocess_pair(args.smartphone, args.vehicle, args.tolerance, args.speed_unit)
        if args.output:
            export_preprocessed_csv(result, args.output)
    except (ValueError, OSError) as exc:
        parser.error(str(exc))
    metadata = result["metadata"]
    print(json.dumps(dict(synchronization=result["synchronization"], quality=result["quality"],
          label=metadata["selected_label_header"], unit=metadata["output_speed_unit"],
          smartphone_sampling=metadata["smartphone_time"]["diagnostics"],
          vehicle_sampling=metadata["vehicle_time"]["diagnostics"],
          warning=metadata["alignment_assumption"], output=args.output), indent=2, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
