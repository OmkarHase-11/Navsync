"""Experimental AI speed to DR integration; no training or heading estimation."""

from dataclasses import dataclass
from math import isfinite

from navigation_engine.dead_reckoning.dead_reckoning import propagate_position


def _finite(value, name):
    if type(value) not in (int, float):
        raise ValueError(f"{name} must be a finite int or float")
    try:
        value = float(value)
    except OverflowError as exc:
        raise ValueError(f"{name} exceeds floating-point range") from exc
    if not isfinite(value):
        raise ValueError(f"{name} must be finite")
    return value


@dataclass(frozen=True)
class IntegrationState:
    latitude: float
    longitude: float
    heading_deg: float
    timestamp: float


class AISpeedDeadReckoningIntegrator:
    """Atomic sequential updates on one caller-defined seconds clock."""

    def __init__(self, *, max_speed_mps=None):
        if max_speed_mps is not None:
            max_speed_mps = _finite(max_speed_mps, "max_speed_mps")
            if max_speed_mps <= 0:
                raise ValueError("max_speed_mps must be positive")
        self._max_speed_mps = max_speed_mps
        self._state = None

    @property
    def state(self):
        return self._state

    @property
    def initialized(self):
        return self._state is not None

    def reset(self):
        self._state = None

    def initialize(self, latitude, longitude, heading_deg, timestamp):
        timestamp = _finite(timestamp, "timestamp")
        # Reuse the DR API's geographic and heading validation, including +180.
        position = propagate_position(latitude, longitude, 0.0, heading_deg, 0.0)
        state = IntegrationState(position.latitude, position.longitude,
                                 float(heading_deg), timestamp)
        self._state = state
        return state

    def update(self, timestamp, estimated_speed_mps, heading_deg=None,
               stationary_override=False):
        """Apply the current speed/heading over the entire preceding interval.

        Validate raw speed and optional maximum before stationary override.
        No state changes occur until validation and propagation succeed.
        """
        state = self._state
        if state is None:
            raise ValueError("initialize with a known position before updating")
        timestamp = _finite(timestamp, "timestamp")
        elapsed = _finite(timestamp - state.timestamp, "elapsed_time_s")
        if elapsed <= 0:
            raise ValueError("timestamp must strictly increase")
        speed = _finite(estimated_speed_mps, "estimated_speed_mps")
        if speed < 0:
            raise ValueError("estimated_speed_mps must be nonnegative")
        if self._max_speed_mps is not None and speed > self._max_speed_mps:
            raise ValueError("estimated_speed_mps exceeds max_speed_mps")
        if type(stationary_override) is not bool:
            raise ValueError("stationary_override must be a bool")
        heading = state.heading_deg if heading_deg is None else heading_deg
        used = 0.0 if stationary_override else speed
        position = propagate_position(state.latitude, state.longitude, used, heading, elapsed)
        heading = float(heading)
        result = dict(timestamp=timestamp, timestamp_unit="seconds",
                      latitude=position.latitude, longitude=position.longitude,
                      speed=used, heading=heading, navigation_mode="DEAD_RECKONING",
                      gnss_status="UNAVAILABLE", position_error=None,
                      metadata=dict(raw_estimated_speed_mps=speed, used_speed_mps=used,
                                    stationary_override_applied=stationary_override,
                                    elapsed_time_s=elapsed, speed_source="AI_IMU"))
        self._state = IntegrationState(position.latitude, position.longitude, heading, timestamp)
        return result


def integrate_speed_predictions(initial_latitude, initial_longitude, initial_heading_deg,
                                predictions, *, initial_timestamp, max_speed_mps=None):
    """Integrate Issue #3 time_s/estimated_speed rows from exactly one run.

    The known initial position must belong to initial_timestamp, strictly before
    every prediction. Each current window-end estimate covers the preceding
    interval by explicit caller agreement. No implicit initialization at zero.
    """
    if not isinstance(predictions, (list, tuple)) or not predictions:
        raise ValueError("predictions must be a nonempty list or tuple")
    integrator = AISpeedDeadReckoningIntegrator(max_speed_mps=max_speed_mps)
    integrator.initialize(initial_latitude, initial_longitude, initial_heading_deg,
                          initial_timestamp)
    trajectory = []
    run_id = None
    for index, row in enumerate(predictions):
        if not isinstance(row, dict) or not {"time_s", "estimated_speed"} <= row.keys():
            raise ValueError("each prediction requires time_s and estimated_speed")
        current_run = row.get("run_id")
        if current_run is not None and (not isinstance(current_run, str) or not current_run):
            raise ValueError("run_id must be a nonempty string or None")
        if index == 0:
            run_id = current_run
        elif current_run != run_id:
            raise ValueError("mixed run IDs require separate initializations")
        point = integrator.update(row["time_s"], row["estimated_speed"])
        if "run_id" in row:
            point["run_id"] = current_run
        trajectory.append(point)
    return trajectory


def predict_and_integrate(model_bundle, records, initial_latitude, initial_longitude,
                          initial_heading_deg, *, initial_timestamp, run_id=None,
                          max_speed_mps=None):
    """Inference only; lazy AI import keeps the core independent of ML packages."""
    from ai.speed_estimation import predict_from_records

    predictions = predict_from_records(model_bundle, records, run_id=run_id)
    trajectory = integrate_speed_predictions(
        initial_latitude, initial_longitude, initial_heading_deg, predictions,
        initial_timestamp=initial_timestamp, max_speed_mps=max_speed_mps)
    return dict(predictions=predictions, trajectory=trajectory)


def to_navigation_output(result, *, unix_origin_ms):
    """Explicit Issue #8 boundary: Unix origin of this clock's zero, in ms.

    Round seconds to the nearest millisecond (Python ties-to-even). The origin
    must be independently known; relative dataset time does not establish it.
    """
    if type(unix_origin_ms) is not int:
        raise ValueError("unix_origin_ms must be an integer")
    if result.get("timestamp_unit") != "seconds":
        raise ValueError("expected a seconds-based integration result")
    milliseconds = _finite(_finite(result["timestamp"], "timestamp") * 1000,
                           "timestamp milliseconds")
    output = {key: result[key] for key in (
        "latitude", "longitude", "speed", "heading", "navigation_mode",
        "gnss_status", "position_error")}
    output["timestamp"] = unix_origin_ms + round(milliseconds)
    return output
