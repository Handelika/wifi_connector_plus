## 0.0.5

* Added `ssidStream` API to listen for Wi-Fi SSID updates.
  * On iOS, uses `NWPathMonitor` to detect path changes and fetch the active SSID.
  * Added `wifi_connector_plus/ssid_stream` event channel.
* Improved iOS connection request reliability:
  * Verifies the actual active SSID (via polling for up to 10 seconds) after `NEHotspotConfigurationManager.apply()` succeeds, preventing false success states on wrong credentials or out-of-range networks.
  * Returns `"ALREADY_CONNECTED"` if the target network is already active.
  * Changed internal platform channel `connect` return type from `bool` to `dynamic` to support detailed status responses.
* Optimized `example/lib/main.dart` UI:
  * Streamlined UI layout with clear instructions.
  * Replaced manual and QR connection logic with a unified helper.
  * Subscribed to `ssidStream` to display the active SSID in real-time.
* Added `com.apple.developer.networking.wifi-info` entitlement to iOS for retrieving SSIDs on iOS 14+.

## 0.0.4

* Added `getCurrentSsid()` API to retrieve the currently connected Wi-Fi network's SSID on Android and iOS.
* Improved connection validation by checking the active SSID post-connection to prevent false success states when connection fails.
* Added multi-language support (English and Turkish) to `WifiQrScannerView` via `WifiScannerLanguage`.
* Added customizable camera controls (toggle flashlight, switch camera direction) to `WifiQrScannerView`.
* Upgraded `permission_handler` dependency to `^12.0.3`.
* Upgraded Qr Scanner Camera view for better performance and user experience.
* Fixed `WifiQrScannerView` to resume camera scanning when connection fails, and verified scanner controller disposal on unmounting.


## 0.0.3

* Updated dependencies:
  * Upgraded `permission_handler` to `^11.4.0`.
  * Upgraded `plugin_platform_interface` to `^2.1.8`.
* Refactored the example app to remove redundant location permission checking logic, utilizing the plugin's internal check and request flow.

## 0.0.2

### Android

* Implemented system-wide Wi-Fi connection flow on Android 10+ using `WifiNetworkSuggestion` and `ActivityResultListener`, replacing the app-scoped `WifiNetworkSpecifier` approach.
* Fixed incorrect `WifiNetworkSuggestion` success status constant that prevented detecting successful connections.
* Added mandatory runtime location permission check and request APIs: `isLocationPermissionGranted()` and `requestLocationPermission()`.
* Added automatic pre-connection permission check inside the `connect()` API.
* Added `ACCESS_FINE_LOCATION` to the Android manifest for Wi-Fi scanning on Android 9+.
* Added consumer Proguard rules for ML Kit and `mobile_scanner` to prevent release-build crashes caused by R8/Proguard obfuscation.
* Upgraded `mobile_scanner` dependency to `7.2.0`.

### Dart / Core

* Improved `WifiQrParser` robustness: case-insensitive security type normalization, trimmed whitespace from parsed fields, and added support for `mobile_scanner` structured barcode data.
* Updated `WifiQrScannerView` to surface the raw QR string alongside parsed `WifiCredentials` via the `onQrScanned` callback.
* Fixed `WifiQrScannerView` crash caused by unhandled `CameraFacing.external` / `CameraFacing.unknown` enum values during camera initialization.

### Documentation

* Added `THIRD_PARTY_NOTICES.md` with license attributions for `permission_handler` and `mobile_scanner`.
* Updated `README.md` with pub.dev badges, platform support table, and collapsible Android/iOS setup guides.
* Fixed mockup image in `README.md` to use an absolute repository URL so it renders correctly on pub.dev.
* Applied `dart format` across all library and example source files.

## 0.0.1

* Initial release of `wifi_connector_plus`.
* Support for manual Wi-Fi connections (WPA, WPA2, WPA3, WEP, or Open/None).
* Standalone `WifiQrParser` to parse industry-standard Wi-Fi QR configurations (`WIFI:S:MyNetwork;T:WPA;P:SecretPassword;;`).
* Pre-built `WifiQrScannerView` widget for camera-based scanning and automatic connection parsing.
* Native Android integration using `WifiNetworkSpecifier` / `WifiNetworkSuggestion` on Android 10+ and legacy API fallback.
* Native iOS integration using `NEHotspotConfigurationManager`.
* **Android Location Permissions Support**:
  - Implemented runtime check and request APIs for location permission: `isLocationPermissionGranted()` and `requestLocationPermission()`.
  - Added automatic pre-connection permission checks inside the `connect()` API for Android.
  - Configured location permission requesting at application startup in the example project.
