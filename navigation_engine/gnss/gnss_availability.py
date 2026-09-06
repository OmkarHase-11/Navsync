"""Deterministic GNSS usability checks; no clock access or navigation switching."""

from dataclasses import dataclass
from math import isfinite
from typing import Literal

MAX_GNSS_AGE_MS = 3000
MAX_GNSS_ACCURACY_M = 30.0

GNSSStatus = Literal["AVAILABLE", "UNAVAILABLE"]
GNSSReason = Literal[
    "NO_FIX", "MISSING_LATITUDE", "MISSING_LONGITUDE", "MISSING_ACCURACY",
    "INVALID_LATITUDE", "INVALID_LONGITUDE", "INVALID_ACCURACY",
    "INVALID_TIMESTAMP", "STALE_FIX", "POOR_ACCURACY", "OK",
]


@dataclass(frozen=True)
class GNSSStatusResult:
    """Local detector result; fix_age_ms is null until timestamps are validated."""

    status: GNSSStatus
    reason: GNSSReason
    fix_age_ms: int | None


def _finite_number(value: object) -> bool:
    # JSON numeric types only; bool is an int subclass but is not a measurement.
    return type(value) is int or (type(value) is float and isfinite(value))


def _timestamp(value: object) -> bool:
    return type(value) is int and value >= 0


def detect_gnss_availability(
    latitude: float | int | None,
    longitude: float | int | None,
    accuracy: float | int | None,
    fix_timestamp_ms: int | None,
    current_timestamp_ms: int,
    max_fix_age_ms: int = MAX_GNSS_AGE_MS,
    max_accuracy_m: float = MAX_GNSS_ACCURACY_M,
) -> GNSSStatusResult:
    """Check a raw fix; all four fix fields None means no fix exists.

    Invalid measurements return UNAVAILABLE. Invalid threshold configuration
    raises ValueError. Age/accuracy thresholds are inclusive. See README for
    failure precedence and the distinction between fix and snapshot timestamps.
    """
    if not _timestamp(max_fix_age_ms):
        raise ValueError("max_fix_age_ms must be a nonnegative integer")
    if not _finite_number(max_accuracy_m) or max_accuracy_m < 0:
        raise ValueError("max_accuracy_m must be a finite nonnegative number")

    def unavailable(reason: GNSSReason, age: int | None = None) -> GNSSStatusResult:
        return GNSSStatusResult("UNAVAILABLE", reason, age)

    if all(value is None for value in (latitude, longitude, accuracy, fix_timestamp_ms)):
        return unavailable("NO_FIX")
    if latitude is None:
        return unavailable("MISSING_LATITUDE")
    if longitude is None:
        return unavailable("MISSING_LONGITUDE")
    if accuracy is None:
        return unavailable("MISSING_ACCURACY")
    if not _finite_number(latitude) or not -90 <= latitude <= 90:
        return unavailable("INVALID_LATITUDE")
    if not _finite_number(longitude) or not -180 <= longitude <= 180:
        return unavailable("INVALID_LONGITUDE")
    if not _finite_number(accuracy) or accuracy < 0:
        return unavailable("INVALID_ACCURACY")
    if (
        not _timestamp(fix_timestamp_ms)
        or not _timestamp(current_timestamp_ms)
        or current_timestamp_ms < fix_timestamp_ms
    ):
        return unavailable("INVALID_TIMESTAMP")

    age = current_timestamp_ms - fix_timestamp_ms
    if age > max_fix_age_ms:
        return unavailable("STALE_FIX", age)
    if accuracy > max_accuracy_m:
        return unavailable("POOR_ACCURACY", age)
    return GNSSStatusResult("AVAILABLE", "OK", age)
