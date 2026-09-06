# Phone-to-Vehicle Alignment

## Purpose

A phone may be mounted portrait, landscape, tilted, or rotated. Its raw sensor axes therefore need not correspond to vehicle forward, lateral, and vertical directions. Issue #5 supplies a deterministic vector transformation using a known mounting orientation, in Python 3.10+ with only the standard library.

**Orientation estimation/calibration is outside Issue #5. This module consumes an orientation transform.** Later calibration code can supply the same angle inputs.

## Phone Frame

The [Issue #8 contract](../../integration/interfaces/README.md) defines the fixed right-handed device frame:

- +X: screen right.
- +Y: screen top in the device's natural orientation.
- +Z: out of the screen.

Screen rotation must not silently reinterpret these axes. Platform normalization happens before this module.

## Vehicle Frame

- +X: vehicle forward (negative X backward).
- +Y: vehicle left (negative Y right).
- +Z: vehicle up (negative Z down).

This is right-handed: in a reference basis (forward, right, down), our axes are X=(1,0,0), Y=(0,-1,0), Z=(0,0,-1), and X cross Y=(0,0,-1)=Z. Equivalently, forward cross left equals up. All three sensor types use this same frame.

## Orientation Convention

Use radians, column vectors, and right-hand positive rotations. Roll is about X, pitch about Y, yaw about Z. The elementary matrices are:

```text
Rx(r) = [1, 0,       0      ]
        [0, cos(r), -sin(r) ]
        [0, sin(r),  cos(r) ]

Ry(p) = [ cos(p), 0, sin(p)]
        [ 0,      1, 0     ]
        [-sin(p), 0, cos(p)]

Rz(y) = [cos(y), -sin(y), 0]
        [sin(y),  cos(y), 0]
        [0,       0,      1]

R_phone_to_vehicle = Rz(yaw) @ Ry(pitch) @ Rx(roll)
v_vehicle = R_phone_to_vehicle @ v_phone
```

The product is written in Z-Y-X order; the rightmost operation acts first: roll, then pitch, then yaw about fixed reference axes. These elementary matrices use the standard active rotation signs. The supplied angles describe the active orientation of the phone basis relative to an initially coincident vehicle basis. The resulting matrix's columns are the phone unit axes expressed in vehicle coordinates. Applying it to measurements is a passive change of coordinates of the same physical vector; it does not physically rotate that vector. Do not transpose this matrix for the forward API. Its transpose maps vehicle coordinates back to phone coordinates.

**Zero roll/pitch/yaw assumes the phone frame already matches the vehicle frame.** That means screen right points forward, screen top points left, and the screen normal points up. A normally mounted portrait phone does not automatically satisfy this. Supply the full mounting transform, not just a display rotation or an unconverted platform attitude. Mounting yaw is not a geographic heading.

## Inputs

Public API in `phone_vehicle_alignment.py`:

| API | Purpose |
| --- | --- |
| `Vector3(x, y, z)` | Frozen dataclass for a validated sensor vector. |
| `Matrix3` | Type alias for an immutable tuple of three 3-element row tuples. |
| `build_phone_to_vehicle_rotation(roll_rad, pitch_rad, yaw_rad)` | Return the mounting rotation matrix. |
| `transform_phone_to_vehicle(vector, roll_rad, pitch_rad, yaw_rad)` | Return a rotated Vector3. |

Numeric components and angles accept built-in int/float values representable as finite Python floats, including zero and negatives. Strings, booleans, NaN, either infinity, lists, dictionaries, None, and other numeric types are rejected with `ValueError`. Integers exceeding float range also raise ValueError. Vector3 normalizes accepted components to floats. The transform requires a Vector3, not a raw list/tuple. Invalid inputs are never replaced with zero or parsed from strings.

Angles are not clamped or restricted to a single revolution: 4*pi and very large finite float angles are accepted. Supply all angles explicitly in radians; there is no implicit degree conversion.

## Outputs

The transform returns a new vehicle-frame Vector3 and leaves its input unchanged. Pure rotation preserves Euclidean magnitude within floating-point tolerance. Units do not change. Matrix output is immutable and represents a proper rotation: orthonormal rows/columns and determinant +1, within floating-point tolerance.

## Accelerometer

Rotate acceleration in m/s², including gravity, into the vehicle frame. Gravity remains present after rotation. No gravity estimation/removal, filtering, acceleration integration, or speed computation occurs.

## Gyroscope

Use the same transformation for angular velocity in rad/s. This only rotates rates; it does not integrate them, estimate orientation, calculate time-varying yaw, or compensate drift.

## Magnetometer

The generic vector API also rotates magnetic field in µT using the same matrix. It does not compute heading, calibrate magnetic effects, or correct declination. Call it separately if magnetic alignment is needed; no new optional-field contract or AlignedIMUData interface is introduced. Issue #8's required magnetometer fields remain required.

## Examples

These are synthetic mathematical examples, not real sensor measurements or calibration results. Run from the repository root:

```python
from math import pi
from navigation_engine.alignment.phone_vehicle_alignment import (
    Vector3, transform_phone_to_vehicle,
)

identity = transform_phone_to_vehicle(Vector3(1, 2, 3), 0, 0, 0)
# Vector3(x=1.0, y=2.0, z=3.0)

yaw = transform_phone_to_vehicle(Vector3(1, 0, 0), 0, 0, pi / 2)
# Approximately Vector3(x=0.0, y=1.0, z=0.0)
```

For +pi/2 yaw, cos=0 and sin=1, so Rz is `[[0,-1,0],[1,0,0],[0,0,1]]`. Its first column gives `(1,0,0) -> (0,1,0)`. The following results follow directly from the corresponding matrix columns:

| Rotation (other angles zero) | Phone vector | Vehicle vector |
| --- | --- | --- |
| Yaw +pi/2 | (1,0,0) | (0,1,0) |
| Yaw -pi/2 | (1,0,0) | (0,-1,0) |
| Roll +pi/2 | (0,1,0) | (0,0,1) |
| Roll -pi/2 | (0,1,0) | (0,0,-1) |
| Pitch +pi/2 | (1,0,0) | (0,0,-1) |
| Pitch -pi/2 | (1,0,0) | (0,0,1) |
| Yaw pi | (1,2,3) | (-1,-2,3) |

## Limitations

Mounting orientation must currently be supplied and must be updated if the phone moves relative to the vehicle. There is no automatic calibration, drift estimation, gravity removal, sensor fusion, heading estimation, or navigation logic. No sensor-position/lever-arm correction is applied. Euler representations are nonunique and have a singular parameterization at pitch +/-pi/2; forward matrix construction still works there, but this module does not recover Euler angles.

Floating-point rounding applies, including to very large angles whose stored value may lose intended angular precision. Extreme vector magnitudes can overflow; nonfinite output components raise ValueError rather than being returned. Test tolerances for the ordinary synthetic vectors are 1e-9, not a claim of physical alignment accuracy.

## Integration

Construct Vector3 from each SensorData accelerometer_x/y/z, gyroscope_x/y/z, or magnetometer_x/y/z group and supply the same mounting angles to each transform. Keep these vehicle-frame results separate from the original phone-frame SensorData fields, and preserve timestamp association in the caller. This module does not mutate or redefine SensorData.

The output is intended to feed Issue #6 Dead Reckoning later. Issue #6, INS, and Issue #10 GNSS switching are not implemented here; Issue #9 is independent. The team should review how the full mounting orientation is measured/provided, platform frame normalization, mount changes, and downstream gravity handling before vehicle testing.

## Tests

From the repository root:

```text
python -B -m unittest discover -s navigation_engine/alignment/tests -v
python -B -m unittest discover -s navigation_engine/gnss/tests -v
```

Alignment tests use only synthetic values and cover the rotations above, composition order, magnitude preservation, transpose inversion, matrix properties, validation, large angles, all three sensor uses, and compatibility with the existing Issue #8 mock sample.
