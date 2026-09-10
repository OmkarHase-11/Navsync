# NavSync Mobile

NavSync mobile client for consumer navigation with inertial dead reckoning fallback.

## Google Maps iOS Setup

To enable Google Maps road tiles on iOS:

1. Copy the secrets template to create your local configuration:
   ```bash
   cp ios/Flutter/Secrets.xcconfig.example ios/Flutter/Secrets.xcconfig
   ```
2. Open `ios/Flutter/Secrets.xcconfig` and set your Google Cloud Maps API key:
   ```properties
   GOOGLE_MAPS_API_KEY=your_actual_key_here
   ```
3. **Never commit `Secrets.xcconfig`**. It is ignored in `.gitignore` to prevent credential exposure.
4. Restrict the API key in the [Google Cloud Console](https://console.cloud.google.com/apis/credentials) to the iOS application bundle identifier (`com.navsync.app`).
5. Ensure the **Maps SDK for iOS** is enabled and billing is activated in your Google Cloud project.

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
