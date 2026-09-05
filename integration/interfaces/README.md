# Navsync Module Interface Contract

## 1. Purpose

This contract addresses Issue #8 for Navsync, the SIH 2026 project for an “AI-ML based Intelligent Dead Reckoning system for seamless navigation.” It defines language-independent data interfaces so sensor collection, AI, navigation, maps, and Flutter UI development can proceed independently. It does not implement algorithms or prescribe a backend architecture.

## 2. System Data Flow

```text
Smartphone sensors -> Flutter Sensor Collection -> SensorData -> AI/ML -> AIOutput
                                                      |                    |
                                                      v                    v
                                                    Navigation Engine
                                                            |
                                                     NavigationOutput
                                                       /           \
                                                      v             v
                                             Map / Map Matching   Flutter UI
                                                      |
                                          Optional corrected coordinates
                                                      |
                                                      v
                                                  Flutter UI
```

The navigation engine consumes SensorData directly, including GNSS and inertial measurements, as well as AIOutput. Map matching is optional; the UI can display NavigationOutput directly.

## 3. SensorData

Measurements collected by the smartphone. All keys are required; only the three GNSS numeric fields are nullable.

| Field | Type | Unit/Format | Required | Description |
| --- | --- | --- | --- | --- |
| timestamp | integer | Unix milliseconds | Yes | Measurement epoch of this sensor snapshot. |
| accelerometer_x | number | m/s² | Yes | Acceleration on device X axis, including gravity. |
| accelerometer_y | number | m/s² | Yes | Acceleration on device Y axis, including gravity. |
| accelerometer_z | number | m/s² | Yes | Acceleration on device Z axis, including gravity. |
| gyroscope_x | number | rad/s | Yes | Angular velocity about device X axis. |
| gyroscope_y | number | rad/s | Yes | Angular velocity about device Y axis. |
| gyroscope_z | number | rad/s | Yes | Angular velocity about device Z axis. |
| magnetometer_x | number | µT | Yes | Magnetic field on device X axis. |
| magnetometer_y | number | µT | Yes | Magnetic field on device Y axis. |
| magnetometer_z | number | µT | Yes | Magnetic field on device Z axis. |
| latitude | number or null | WGS84 decimal degrees | Yes | Usable GNSS latitude, between -90 and +90 inclusive. |
| longitude | number or null | WGS84 decimal degrees | Yes | Usable GNSS longitude, between -180 and +180 inclusive. |
| gnss_accuracy | number or null | m | Yes | Nonnegative horizontal accuracy estimate reported by the GNSS API; not measured ground-truth error. |
| gnss_available | boolean | true / false | Yes | Whether GNSS is currently considered usable. |

When `gnss_available` is `true`, latitude, longitude, and gnss_accuracy must be numeric. When it is `false`, all three must be `null`, including when a fix is present but considered unusable. Do not substitute stale coordinates or zeroes.

## 4. AIOutput

Speed and motion estimates produced by the AI/ML module.

| Field | Type | Unit/Format | Required | Description |
| --- | --- | --- | --- | --- |
| timestamp | integer | Unix milliseconds | Yes | Epoch represented by the estimate. |
| estimated_speed | number | m/s | Yes | Nonnegative scalar vehicle speed estimate. |
| estimated_acceleration | number | m/s² | Yes | Signed rate of change of scalar speed: positive when speeding up, negative when slowing down. |
| motion_state | string | Enum below | Yes | Estimated motion classification. |

| motion_state | Meaning |
| --- | --- |
| MOVING | The module classifies the vehicle as moving. |
| STOPPED | The module classifies the vehicle as stationary. |
| UNKNOWN | The module cannot confidently classify motion. |

Classification thresholds belong to the AI implementation and must be agreed during integration. `UNKNOWN` does not make the required numeric estimates nullable. If valid numeric estimates cannot be produced, do not fabricate an AIOutput; the navigation engine must handle its absence.

## 5. NavigationOutput

The position/navigation estimate produced by the navigation engine, before optional map matching.

| Field | Type | Unit/Format | Required | Description |
| --- | --- | --- | --- | --- |
| timestamp | integer | Unix milliseconds | Yes | Epoch represented by the navigation estimate. |
| latitude | number | WGS84 decimal degrees | Yes | Estimated latitude, between -90 and +90 inclusive. |
| longitude | number | WGS84 decimal degrees | Yes | Estimated longitude, between -180 and +180 inclusive. |
| speed | number | m/s | Yes | Nonnegative scalar vehicle speed estimate. |
| heading | number | degrees, 0 <= heading < 360 | Yes | Vehicle heading clockwise from true north. |
| navigation_mode | string | GNSS_INS / DEAD_RECKONING | Yes | Active navigation mode. |
| gnss_status | string | AVAILABLE / UNAVAILABLE | Yes | Whether the navigation engine currently considers GNSS usable. |
| position_error | number or null | m | No | Nonnegative estimated horizontal position error, if available; not ground-truth error. |

Producers should include `position_error: null` when no error estimate exists. Consumers must also accept an omitted position_error. Never use zero to mean unknown. The estimator and confidence interpretation of a numeric position_error must be agreed before producers populate it; the MVP sample uses null.

## 6. GNSS Status

| gnss_status | Meaning |
| --- | --- |
| AVAILABLE | GNSS data is currently considered usable. |
| UNAVAILABLE | GNSS data is currently considered unusable, including missing, stale, or rejected fixes. |

SensorData expresses collection-side usability with the boolean `gnss_available`; NavigationOutput expresses navigation-side usability with `gnss_status`. The engine may reject a collection-side usable fix after freshness or quality checks. Quality thresholds and freshness limits must be agreed by the team; this contract does not invent them.

## 7. Navigation Modes

| navigation_mode | Meaning | Required gnss_status |
| --- | --- | --- |
| GNSS_INS | GNSS information is available and is being used with the navigation/inertial system. | AVAILABLE |
| DEAD_RECKONING | GNSS is unavailable and vehicle position is estimated using the Dead Reckoning/navigation system. | UNAVAILABLE |

These are the only valid mode/status pairings in this MVP. GNSS loss must not stop navigation estimates after initialization. When usable GNSS returns, navigation can transition back to GNSS_INS.

## 8. Module Input/Output Contracts

| Module | Input | Output |
| --- | --- | --- |
| Flutter Sensor Collection | Smartphone accelerometer, gyroscope, magnetometer, and GNSS APIs | SensorData |
| AI/ML Module | Relevant IMU fields from SensorData, potentially as a time window | AIOutput |
| Navigation Engine | SensorData and AIOutput when available | NavigationOutput |
| Map / Map Matching Module | NavigationOutput | Optional map-matched/corrected coordinates |
| Flutter Navigation UI | NavigationOutput and map-matched coordinates when available | Visual navigation information shown to the user |

For the MVP, map matching returns an optional latitude/longitude pair in WGS84 decimal degrees, associated with the source NavigationOutput timestamp through the local call/result context. Both coordinates must be present and valid to use the correction. No formal MapOutput interface is introduced. The map module must preserve the original NavigationOutput; the UI uses corrected coordinates for display when available and otherwise uses the original estimate. Other navigation fields retain their original meanings. Reject corrections belonging to an older/different estimate rather than applying them to the current one. Feedback of corrections into the navigation engine is outside this contract.

## 9. Communication Format

JSON-compatible objects are the canonical interchange representation. Use the exact case-sensitive field names and enum strings defined here. Numbers must be finite JSON numbers, booleans must be JSON booleans, and missing values must use JSON `null` where permitted. Do not encode numbers as strings or use NaN/Infinity.

Implementations may use Dart classes, Python dataclasses/dictionaries, C++ structs, or equivalent in-memory structures. Their serialized field names, meanings, and units must remain consistent. Local calls, callbacks, or streams can carry these objects; actual JSON serialization is needed only at a boundary that requires it. No networking, REST APIs, WebSockets, databases, brokers, cloud services, or microservices are required.

## 10. Units and Conventions

| Quantity | Internal convention |
| --- | --- |
| Speed | m/s; nonnegative magnitude |
| Acceleration | m/s² |
| Gyroscope angular velocity | rad/s |
| Magnetic field | µT |
| Distance and accuracy/error estimates | m |
| Heading | degrees clockwise from true north |
| Geographic coordinates | WGS84 decimal degrees |
| Time | Unix milliseconds as integers |

For this proposed MVP convention, sensor axes use a fixed right-handed device frame: X toward the screen's right edge, Y toward its top edge in the device's natural orientation, and Z out of the screen. Positive gyroscope rotation follows the right-hand rule. Screen rotation must not silently rotate these axes. Collection adapters must normalize platform API conventions to this frame. Accelerometer values include gravity; any gravity removal or conversion into the vehicle/navigation frame belongs to downstream processing. Sensor mounting/orientation calibration remains an implementation responsibility. AI estimated_acceleration is a scalar speed derivative, not an individual device-axis acceleration.

UI conversion to km/h or other display units is allowed without changing the interchange values.

## 11. Timestamp Rules

Every structure requires an integer Unix timestamp in milliseconds, for example `1725552000123`, to synchronize sensor measurements, AI outputs, and navigation outputs. Do not use human-readable date strings as the primary internal timestamp format.

Timestamps represent measurement/estimate time, not serialization, arrival, or processing-completion time. For AI windows, use the final measurement epoch represented by the window. NavigationOutput uses the epoch to which the engine has propagated its state. All producers must use a common Unix time basis; adapters must convert monotonic sensor clocks appropriately. Do not apply a local timezone offset.

SensorData is an aligned snapshot at its timestamp, not a claim that all hardware APIs sample simultaneously. Collection must align readings and check GNSS freshness before marking it usable. Sampling rates, alignment tolerances, and stale-input limits require team agreement. Consumers must use timestamps to associate results and handle late/out-of-order inputs without silently treating them as current.

## 12. Coordinate and Heading Conventions

All geographic coordinates, including navigation and map-matched estimates, use WGS84 decimal degrees:

- Latitude: -90 to +90 inclusive; positive north, negative south.
- Longitude: -180 to +180 inclusive; positive east, negative west.
- Heading: `0 <= heading < 360`, clockwise from true north.
- 0° = North, 90° = East, 180° = South, 270° = West. Represent 360° as 0°.

Device-axis gyroscope readings and magnetic measurements are not already geographic headings. Producers are responsible for the appropriate frame conversion before emitting heading.

## 13. Handling Missing/Unavailable Data

- When GNSS is lost or unusable, retain every SensorData key, set gnss_available to false, and set latitude, longitude, and gnss_accuracy to null. For example, the GNSS portion becomes `"latitude": null, "longitude": null, "gnss_accuracy": null, "gnss_available": false`.
- Continue NavigationOutput generation in DEAD_RECKONING mode with UNAVAILABLE status and estimated numeric coordinates during GNSS loss. Navigation coordinates are not made null merely because GNSS is unavailable.
- Dead Reckoning requires an initialized position and heading. If no valid initial state exists, do not invent coordinates or emit an invalid NavigationOutput; the UI must represent a waiting/uninitialized state outside this position contract.
- Missing optional position_error or unavailable map corrections must not break consumers. Null/omission means unknown, not zero error.
- Required non-null sensor or estimate fields cannot be omitted or replaced with zero/null. If a required measurement cannot be supplied, do not emit a malformed record; report collection/processing unavailability through implementation-level handling. Hardware without a required sensor needs a team-agreed contract revision.
- Navigation must tolerate absent/delayed AI outputs according to its fallback policy. This contract defines payload validity, not a particular estimation algorithm.

## 14. Sample Data

**All JSON values are fictional MOCK DATA used only to demonstrate these interfaces. They are NOT experimental results, actual sensor measurements, model predictions, or SIH performance statistics. They imply no project accuracy or performance claims.**

| File | Demonstrates |
| --- | --- |
| [sensor_data.json](sample_data/sensor_data.json) | Complete SensorData with GNSS available. |
| [ai_output.json](sample_data/ai_output.json) | Valid speed/acceleration estimates and MOVING motion state. |
| [navigation_output.json](sample_data/navigation_output.json) | GNSS_INS mode with AVAILABLE GNSS and unknown position_error. |

Each file contains one JSON object. They share an illustrative epoch to demonstrate time association, not processing latency or a sampling-rate requirement.

## 15. Integration Rules

1. Do not rename interface fields without agreement from the technical team.
2. Do not silently change units between modules.
3. Represent speed internally in m/s.
4. Represent acceleration in m/s².
5. Represent gyroscope angular velocity in rad/s.
6. Represent heading in degrees.
7. Use WGS84 decimal degrees for latitude and longitude.
8. Use Unix milliseconds for timestamps.
9. GNSS loss must not stop NavigationOutput generation after initialization; continue position estimates in DEAD_RECKONING mode.
10. When GNSS becomes usable again, navigation can transition back to GNSS_INS mode.
11. Handle missing or unavailable optional data safely.
12. Follow the same field meanings and units in every implementation language.

Before accepting this contract, the team should review the proposed device frame and gravity convention, scalar acceleration meaning, time alignment/freshness policy, GNSS usability criteria, initialization/fallback behavior, position_error interpretation, and timestamp association at the map-matching boundary. Changes to these meanings require explicit agreement before integration.
