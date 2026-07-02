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
