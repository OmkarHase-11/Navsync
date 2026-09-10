# NavSync Mobile

NavSync mobile client for consumer navigation with inertial dead reckoning fallback.

## OpenStreetMap map layer (Issue #12)

The existing Pune simulation uses flutter_map and latlong2 with standard HTTPS
OpenStreetMap street tiles. No map API key is needed. Location and IMU collection
remain separate and unchanged. The tile user-agent identifies NavSync as com.navsync.app (an application identifier,
not a change to platform bundle IDs). flutter_map's SimpleAttributionWidget remains
visible above the trip card and opens the OSM copyright page using url_launcher.
Follow https://operations.osmfoundation.org/policies/tiles/; this implementation
adds no bulk downloads or offline prefetching.

Vehicle heading, destination tooltip, remaining/travelled routes, dashed DR trail,
auto-follow and recenter are retained. Camera rotation uses negative heading for
heading-up; the vehicle arrow rotates by heading in radians within the map.
Only gesture-originated camera changes disable follow. flutter_map is a 2D map:
the previous perspective tilt and hybrid satellite imagery are replaced by a
normal street map. The constructor and simulation behavior remain unchanged.

On macOS, run `flutter pub get` and `cd ios && pod install` before an iOS build.
The existing CocoaPods lockfile is stale and must be regenerated there; CocoaPods
is not available in this Windows workspace. Local ignored Secrets.xcconfig files
are no longer included and need not be edited or disclosed.

## Sensor & Location Dependencies (Issue #11)

NavSync uses two Flutter plugins for sensor collection:

| Package | Purpose |
|---|---|
| `sensors_plus` | Accelerometer, gyroscope, and magnetometer event streams |
| `geolocator` | Foreground GNSS/location data and permission management |

### Platform Permissions

**iOS** (`ios/Runner/Info.plist`):
- `NSLocationWhenInUseUsageDescription` — foreground location for navigation
- `NSMotionUsageDescription` — motion sensors for dead reckoning

**Android** (`android/app/src/main/AndroidManifest.xml`):
- `ACCESS_FINE_LOCATION` — high-accuracy GPS
- `ACCESS_COARSE_LOCATION` — network-based location fallback

Background location collection is **not enabled**. Real sensor collection will be implemented in Issue #11C. All internal sensor units follow [integration/interfaces/README.md](../integration/interfaces/README.md) §10.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
