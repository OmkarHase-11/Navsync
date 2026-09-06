"""Read-only IO-VNBD schema and quality exploration; no synchronization or conversion."""

import argparse
import csv
import io
import json
import math
from pathlib import Path
import re
import statistics

ALIGNMENT_NOTE = "Equal row counts do not guarantee sample-by-sample timestamp alignment."
SCALE_WARNING = "Observed speed ranges differ substantially. Verify units and synchronization before training or evaluation."


def _number(cell: str) -> float | None:
    try:
        value = float(cell)
    except ValueError:
        return None
    return value if math.isfinite(value) else None


def load_csv(path: str | Path) -> tuple[list[str], list[list[str]], str, list[str]]:
    """Load a comma-delimited CSV without mutation; reject ambiguous headers."""
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"CSV does not exist: {path}")
    if not path.is_file():
        raise ValueError(f"CSV path is not a file: {path}")
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            text = raw.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    reader = csv.reader(io.StringIO(text, newline=""), strict=True)
    try:
        header = next(reader, [])
        if not header or any(not name.strip() for name in header):
            raise ValueError(f"CSV has an empty or missing header: {path}")
        if len({name.strip().casefold() for name in header}) != len(header):
            raise ValueError(f"CSV has duplicate column names: {path}")
        rows, warnings = [], []
        short = extra = blank = 0
        for row in reader:
            if not row:
                blank += 1
                continue
            short += len(row) < len(header)
            extra += len(row) > len(header)
            rows.append([cell.strip() for cell in row[:len(header)]] + [""] * max(0, len(header)-len(row)))
        if short:
            warnings.append(f"{short} short rows padded with missing cells.")
        if extra:
            warnings.append(f"{extra} rows have extra fields excluded from header-based statistics.")
        if blank:
            warnings.append(f"{blank} empty physical records skipped.")
        return header, rows, encoding, warnings
    except csv.Error as exc:
        raise ValueError(f"Malformed CSV in {path}: {exc}") from exc


def detect_columns(columns: list[str]) -> dict[str, list[str]]:
    """Heuristic, case-insensitive candidates; groups may overlap."""
    patterns = {
        "timestamp": r"time|timestamp|elapsed|date",
        "gps": r"gps|gnss|latitude|longitude|altitude|satellite|\bheading\b|\bheight\b",
        "accelerometer": r"accelero|acceleration|\bacc[ _-]?[xyz]\b",
        "gravity": r"gravity",
        "gyroscope": r"gyro|yaw[ _-]*rate",
        "magnetometer": r"magnet|\bmag[ _-]?[xyz]\b",
        "speed": r"speed|velocity",
        "vehicle_wheel_speed": r"wheel.*speed|speed.*wheel|vehicle.*speed|speed.*vehicle",
        "orientation": r"orientation|azimuth|pitch|roll|heading|yaw|steering",
        "vehicle_motion": r"wheel|vehicle|yaw|longitudinal|lateral|steering|engine|gear|brake|clutch",
    }
    return {group: [name for name in columns if re.search(pattern, name, re.I)]
            for group, pattern in patterns.items()}


def _stats(cells: list[str]) -> dict:
    values = [n for cell in cells if (n := _number(cell)) is not None]
    missing = sum(not cell for cell in cells)
    # Scale before summing to avoid overflow for large but finite numeric cells.
    mean = math.fsum(value / len(values) for value in values) if values else None
    return dict(numeric_count=len(values), missing_count=missing,
                invalid_nonblank_count=len(cells)-missing-len(values),
                min=min(values) if values else None, max=max(values) if values else None, mean=mean)


def _time_unit(name: str) -> tuple[float | None, str]:
    lower = name.lower()
    if re.search(r"milliseconds?|\bms\b", lower):
        return .001, "Milliseconds inferred from explicit header; not independently verified."
    if re.search(r"seconds?|\bsecs?\b|\(s\)|\[s\]", lower):
        return 1.0, "Seconds inferred from explicit header; not independently verified."
    return None, "Time unit uncertain: value magnitude/cadence alone cannot establish seconds versus milliseconds. No Hz inferred."


def _sampling(columns: dict[str, list[str]], candidates: list[str]) -> dict:
    eligible = [name for name in candidates
                if not re.search(r"period|interval", name, re.I)
                and sum(_number(cell) is not None for cell in columns[name]) >= 2]
    if not eligible:
        return {"column": None, "duration_s": None, "estimated_hz": None,
                "note": "No numeric time coordinate with at least two finite samples; date strings are not parsed."}
    def score(name):
        return (bool(re.search(r"elapsed|since|timestamp", name, re.I)), _time_unit(name)[0] is not None)
    name = max(eligible, key=score)
    values = [_number(cell) for cell in columns[name]]
    finite = [value for value in values if value is not None]
    diffs = [b-a for a, b in zip(values, values[1:]) if a is not None and b is not None]
    overflow = sum(not math.isfinite(d) for d in diffs)
    diffs = [d for d in diffs if math.isfinite(d)]
    positive = [d for d in diffs if d > 0]
    median = (statistics.median_low(positive)/2 + statistics.median_high(positive)/2) if positive else None
    duration = finite[-1]-finite[0]
    duration = duration if math.isfinite(duration) else None
    factor, note = _time_unit(name)
    nonpositive = sum(d <= 0 for d in diffs)
    usable = factor is not None and nonpositive == 0 and not overflow and duration is not None and duration >= 0
    interval = median * factor if median is not None and factor is not None else None
    hz = 1/interval if usable and interval and math.isfinite(1/interval) else None
    return dict(column=name, candidates=eligible, unit_inference=note,
                sample_count=len(values), numeric_sample_count=len(finite),
                invalid_or_missing_sample_count=len(values)-len(finite),
                duration_raw=duration, duration_s=duration*factor if usable else None,
                median_positive_interval_raw=median,
                median_sample_interval_s=interval,
                min_interval_raw=min(diffs) if diffs else None,
                max_interval_raw=max(diffs) if diffs else None,
                min_interval_s=min(diffs)*factor if diffs and factor else None,
                max_interval_s=max(diffs)*factor if diffs and factor else None,
                non_positive_differences=nonpositive, overflow_differences=overflow,
                large_gap_count=sum(d > 5*median for d in positive) if median else 0,
                estimated_hz=hz,
                note="Adjacent valid rows only; no bridging across missing timestamps. Gaps >5 times median positive interval are heuristic flags. Duration spans first/last valid times. Non-positive differences suppress duration_s and Hz; no rollover/reset repair.")


def explore_file(path: str | Path) -> dict:
    """Explore one recording independently; preserve original header spelling."""
    header, rows, encoding, warnings = load_csv(path)
    columns = {name: [row[i] for row in rows] for i, name in enumerate(header)}
    groups = detect_columns(header)
    all_stats = {name: _stats(cells) for name, cells in columns.items()}
    numeric = {name: stats for name, stats in all_stats.items()
               if stats["numeric_count"] and stats["numeric_count"] >= (len(rows)-stats["missing_count"])/2}
    missing = {name: dict(blank_count=stats["missing_count"],
                          blank_percentage=100*stats["missing_count"]/len(rows) if rows else 0)
               for name, stats in all_stats.items()}
    return dict(file=str(Path(path)), file_name=Path(path).name, encoding=encoding,
                row_count=len(rows), column_count=len(header), columns=header, groups=groups,
                numeric_statistics=numeric, missing_values=missing,
                columns_with_missing_values=[name for name, stat in missing.items() if stat["blank_count"]],
                sampling=_sampling(columns, groups["timestamp"]),
                speed_statistics={name: all_stats[name] for name in groups["speed"]}, warnings=warnings)


def explore_pair(smartphone_path: str | Path, vehicle_path: str | Path) -> dict:
    """Return a JSON-compatible report; no row alignment or unit conversion."""
    smartphone, vehicle = explore_file(smartphone_path), explore_file(vehicle_path)
    sd, vd = smartphone["sampling"].get("duration_s"), vehicle["sampling"].get("duration_s")
    speeds = []
    phone_candidates = [n for n in smartphone["groups"]["speed"] if re.search(r"gps|gnss", n, re.I)]
    vehicle_candidates = [n for n in vehicle["groups"]["speed"]
                          if not re.search(r"wheel|engine|vertical|rad/|rev/|rpm", n, re.I)]
    for phone in phone_candidates:
        for reference in vehicle_candidates:
            left, right = smartphone["speed_statistics"][phone], vehicle["speed_statistics"][reference]
            if not left["numeric_count"] or not right["numeric_count"]:
                continue
            a, b = max(abs(left["min"]), abs(left["max"])), max(abs(right["min"]), abs(right["max"]))
            discrepancy = max(a, b) > 0 and (min(a, b) == 0 or max(a, b)/min(a, b) >= 2)
            speeds.append(dict(smartphone_column=phone, vehicle_column=reference,
                               smartphone_range=[left["min"], left["max"]],
                               vehicle_range=[right["min"], right["max"]],
                               warning=SCALE_WARNING if discrepancy else None))
    comparison = dict(smartphone_row_count=smartphone["row_count"], vehicle_row_count=vehicle["row_count"],
                      row_counts_match=smartphone["row_count"] == vehicle["row_count"],
                      smartphone_duration_s=sd, vehicle_duration_s=vd,
                      duration_difference_s=abs(sd-vd) if sd is not None and vd is not None else None,
                      smartphone_estimated_hz=smartphone["sampling"].get("estimated_hz"),
                      vehicle_estimated_hz=vehicle["sampling"].get("estimated_hz"),
                      synchronization_note=ALIGNMENT_NOTE, speed_comparisons=speeds,
                      unit_warning="Headers report units, not verified truth. Speed values remain raw. A >=2x peak-magnitude difference (or zero versus nonzero) is a review heuristic, not proof of a unit error.")
    sg, vg = smartphone["groups"], vehicle["groups"]
    suitability = dict(smartphone_imu_candidates=bool(sg["accelerometer"] and sg["gyroscope"]),
                       smartphone_gnss_candidates=bool(sg["gps"]),
                       speed_reference_candidates=vehicle_candidates,
                       vehicle_motion_candidates=vg["vehicle_motion"],
                       issue2_candidate_signals=bool(sg["accelerometer"] and vehicle_candidates),
                       note="Based only on detected column names: candidates for review, not verified usable inputs or training labels. Issue #2 must verify units, synchronization, missingness, and feature/label selection.")
    return dict(smartphone=smartphone, vehicle=vehicle, comparison=comparison, suitability=suitability)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smartphone", required=True, type=Path)
    parser.add_argument("--vehicle", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        report = explore_pair(args.smartphone, args.vehicle)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    print(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
