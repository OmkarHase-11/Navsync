import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Retrieve Google Maps API key from Info.plist (populated via Secrets.xcconfig)
    let rawApiKey = (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let apiKey = rawApiKey,
          !apiKey.isEmpty,
          !apiKey.contains("GOOGLE_MAPS_API_KEY"),
          !apiKey.contains("YOUR_RESTRICTED_GOOGLE_MAPS_IOS_API_KEY"),
          !apiKey.contains("YOUR_GOOGLE_MAPS_API_KEY_HERE") else {
      fatalError("""
        [NavSync Configuration Error] Google Maps API key is missing or unconfigured.
        Please create 'ios/Flutter/Secrets.xcconfig' by copying 'Secrets.xcconfig.example'
        and provide a valid Maps SDK for iOS API key.
        """)
    }

    GMSServices.provideAPIKey(apiKey)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
