"""Rotate phone-frame vectors into vehicle coordinates using a supplied mount."""

from dataclasses import dataclass
from math import cos, isfinite, sin

Matrix3 = tuple[tuple[float, float, float],
                tuple[float, float, float],
                tuple[float, float, float]]


def _finite_float(value: object, name: str) -> float:
    if type(value) not in (int, float):
        raise ValueError(f"{name} must be a finite int or float")
    try:
        result = float(value)
    except OverflowError as exc:
        raise ValueError(f"{name} exceeds floating-point range") from exc
    if not isfinite(result):
        raise ValueError(f"{name} must be finite")
    return result


@dataclass(frozen=True)
class Vector3:
    """Three finite components; units are retained by the rotation."""

    x: float
    y: float
    z: float

    def __post_init__(self) -> None:
        for name in ("x", "y", "z"):
            object.__setattr__(self, name, _finite_float(getattr(self, name), name))


def build_phone_to_vehicle_rotation(
    roll_rad: float, pitch_rad: float, yaw_rad: float,
) -> Matrix3:
    """Return Rz(yaw) @ Ry(pitch) @ Rx(roll), mapping phone to vehicle columns.

    Angles parameterize the full mounting transform, with right-hand positive
    rotations. Zero means coincident frames, not a generic portrait mount.
    """
    roll = _finite_float(roll_rad, "roll_rad")
    pitch = _finite_float(pitch_rad, "pitch_rad")
    yaw = _finite_float(yaw_rad, "yaw_rad")
    cr, sr = cos(roll), sin(roll)
    cp, sp = cos(pitch), sin(pitch)
    cy, sy = cos(yaw), sin(yaw)
    # Expanded product of the standard right-handed elementary matrices.
    return (
        (cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr),
        (sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr),
        (-sp, cp * sr, cp * cr),
    )


def transform_phone_to_vehicle(
    vector: Vector3, roll_rad: float, pitch_rad: float, yaw_rad: float,
) -> Vector3:
    """Apply v_vehicle = R_phone_to_vehicle @ v_phone; retain gravity and units.

    Invalid inputs or nonfinite output components raise ValueError.
    """
    if not isinstance(vector, Vector3):
        raise ValueError("vector must be a Vector3")
    rotation = build_phone_to_vehicle_rotation(roll_rad, pitch_rad, yaw_rad)
    components = (vector.x, vector.y, vector.z)
    return Vector3(*(sum(a * b for a, b in zip(row, components)) for row in rotation))
