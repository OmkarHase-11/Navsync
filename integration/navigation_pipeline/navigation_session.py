"""Issue #15 Python adapter. One session per trip; no on-device execution claim."""

import copy
import json
import sys

from integration.ai_dead_reckoning.ai_dead_reckoning import AISpeedDeadReckoningIntegrator
from navigation_engine.alignment.phone_vehicle_alignment import Vector3, transform_phone_to_vehicle
from navigation_engine.gnss.gnss_availability import detect_gnss_availability
from navigation_engine.mode_switching.mode_switching import NavigationModeController


class NavigationSession:
    def __init__(self, *, max_gap_ms=None, max_speed_mps=None):
        if max_gap_ms is not None and (type(max_gap_ms) is not int or max_gap_ms <= 0):
            raise ValueError('max_gap_ms must be None or a positive integer')
        self.max_gap_ms = max_gap_ms
        self.max_speed_mps = max_speed_mps
        self.reset()

    def reset(self):
        self.dr = AISpeedDeadReckoningIntegrator(max_speed_mps=self.max_speed_mps)
        self.switch = NavigationModeController()
        self.last_timestamp = None
        self.origin_ms = None

    def handle(self, request):
        if not isinstance(request, dict):
            raise ValueError('request must be a JSON object')
        if request.get('operation') == 'reset':
            self.reset()
            return {'reset': True}
        sensor, motion = request['sensor'], request['motion']
        timestamp = sensor['timestamp']
        if type(timestamp) is not int or timestamp < 0:
            raise ValueError('timestamp must be Unix milliseconds')
        if self.last_timestamp is not None and timestamp <= self.last_timestamp:
            raise ValueError('timestamp must strictly increase')
        if type(motion['timestamp']) is not int or motion['timestamp'] != timestamp:
            raise ValueError('motion must correspond to the sensor snapshot')
        heading, speed = motion['heading_deg'], motion['speed_mps']
        stationary = motion.get('stationary_override', False)
        if type(sensor['gnss_available']) is not bool:
            raise ValueError('gnss_available must be boolean')
        # SensorDataAssembler already validates actual fix age before emitting
        # gnss_available. Snapshot time is NOT claimed to be the original fix epoch.
        fix_time = request.get('fix_timestamp_ms')
        if sensor['gnss_available']:
            if fix_time is None:
                if request.get('gnss_prevalidated') is not True:
                    raise ValueError('original fix timestamp or assembler validation required')
                fix_time = timestamp
            status = detect_gnss_availability(sensor['latitude'], sensor['longitude'],
                sensor['gnss_accuracy'], fix_time, timestamp)
        else:
            status = detect_gnss_availability(None, None, None, None, timestamp)

        # Validate/rotate only when an explicit calibrated mount is supplied.
        # Keep phone-frame values separate: Issue #3 was trained in that frame.
        aligned = None
        mount = request.get('mount_radians')
        vectors = {name: Vector3(*(sensor[f'{name}_{axis}'] for axis in 'xyz'))
                   for name in ('accelerometer', 'gyroscope', 'magnetometer')}
        if mount is not None:
            if len(mount) != 3:
                raise ValueError('mount_radians must contain roll, pitch, yaw')
            aligned = {name: vars(transform_phone_to_vehicle(vector, *mount))
                       for name, vector in vectors.items()}

        origin = timestamp if self.origin_ms is None else self.origin_ms
        time_s = (timestamp - origin) / 1000.0
        # Validate speed/stationary/heading with Issue #14 even on a GNSS fix.
        validator = AISpeedDeadReckoningIntegrator(max_speed_mps=self.max_speed_mps)
        validator.initialize(0, 0, heading, 0)
        validated = validator.update(1, speed, heading, stationary)
        used = validated['speed']
        dr, switch = copy.deepcopy(self.dr), copy.deepcopy(self.switch)
        if status.status == 'AVAILABLE':
            raw = switch.update('AVAILABLE', sensor['latitude'], sensor['longitude'])
            dr.initialize(raw.latitude, raw.longitude, heading, time_s)
        else:
            if not dr.initialized:
                raise ValueError('waiting for first valid GNSS position')
            elapsed_ms = timestamp - self.last_timestamp
            if self.max_gap_ms is not None and elapsed_ms > self.max_gap_ms:
                raise ValueError('DR gap too large; wait for a valid GNSS re-anchor')
            dr.update(time_s, speed, heading, stationary)
            # Issue #10 owns source selection; Issue #14 owns speed policy. Both
            # delegate to the same Issue #6 propagation API, with identical inputs.
            raw = switch.update('UNAVAILABLE', speed_mps=used, heading_deg=heading,
                                elapsed_time_s=elapsed_ms / 1000.0)
        output = dict(timestamp=timestamp, latitude=raw.latitude, longitude=raw.longitude,
                      speed=used, heading=float(heading), navigation_mode=raw.navigation_mode,
                      gnss_status=raw.gnss_status, position_error=None)
        result = dict(raw=output, aligned_imu=aligned, gnss_reason=status.reason,
                      speed_source='AI_IMU', raw_speed_mps=speed,
                      stationary_override_applied=stationary)
        json.dumps(result, allow_nan=False)
        self.dr, self.switch = dr, switch
        self.last_timestamp, self.origin_ms = timestamp, origin
        return result


def main():
    """Newline JSON harness for an explicitly supplied host transport, not a server."""
    session = NavigationSession()
    for line in sys.stdin:
        try:
            response = session.handle(json.loads(line))
        except (ValueError, KeyError, TypeError, OverflowError) as error:
            response = {'error': str(error)}
        print(json.dumps(response, allow_nan=False), flush=True)


if __name__ == '__main__':
    main()
