# wifi_connector_plus

A comprehensive Flutter plugin to scan Wi-Fi QR codes, parse connection settings, and connect directly to Wi-Fi networks on Android and iOS.

## Features

- **Built-in Scanner Widget**: `WifiQrScannerView` handles camera permission requests, displays the camera view with an overlay, and parses Wi-Fi configurations automatically.
- **Manual Connections**: Establish connections manually using SSID, password, and security types (WPA, WEP, or Open/None).
- **QR Code Parser**: Standalone utility `WifiQrParser` to parse industry-standard Wi-Fi QR configurations (e.g., `WIFI:S:MyNetwork;T:WPA;P:SecretPassword;;`).
- **Comprehensive Platform APIs**: Uses modern native connection APIs (`WifiNetworkSpecifier` and `WifiNetworkSuggestion` on Android 10+, and `NEHotspotConfigurationManager` on iOS 11+).

---

## Getting Started

### 1. Platform Setup & Permissions

#### Android

Add the following permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Camera permission for the QR Scanner -->
    <uses-permission android:name="android.permission.CAMERA" />
    
    <!-- Location and Wi-Fi state permissions for connecting to networks -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    
    <application ...>
        ...
    </application>
</manifest>
```

#### iOS

Add the following keys to your `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to scan QR codes for Wi-Fi connections.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to detect nearby Wi-Fi networks.</string>
```

Also, ensure that **Hotspot Configuration** capability is enabled for your iOS App Bundle ID in the Apple Developer Portal.

---

## Usage

### 1. Connecting to Wi-Fi Manually

```dart
import 'package:wifi_connector_plus/wifi_connector_plus.dart';

final wifiConnector = WifiConnectorPlus();

// Connect manually to a WPA network
WifiConnectResult result = await wifiConnector.connect(
  ssid: 'MyHomeWiFi',
  password: 'myPassword123',
  securityType: WifiSecurityType.wpa, // WPA, WEP, or None
  isHidden: false,
);

if (result.isSuccess) {
  print('Connected successfully: ${result.message}');
} else {
  print('Connection failed: ${result.message} (Error: ${result.error})');
}
```

### 2. Parsing a raw Wi-Fi QR Code String

```dart
import 'package:wifi_connector_plus/wifi_connector_plus.dart';

final rawQrString = 'WIFI:S:OfficeWiFi;T:WPA;P:Secret123;;';
WifiCredentials? credentials = WifiQrParser.parse(rawQrString);

if (credentials != null) {
  print('SSID: ${credentials.ssid}');
  print('Password: ${credentials.password}');
  print('Security: ${credentials.securityType}');
}
```

### 3. Using the built-in Camera QR Scanner Widget

Push `WifiQrScannerView` to display a camera view that requests permissions and parses Wi-Fi configurations automatically.

```dart
import 'package:flutter/material.dart';
import 'package:wifi_connector_plus/wifi_connector_plus.dart';

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WifiQrScannerView(
        onScanSuccess: (WifiCredentials credentials) async {
          // Triggered when a valid Wi-Fi QR code is scanned
          Navigator.pop(context);
          
          final connector = WifiConnectorPlus();
          final result = await connector.connect(
            ssid: credentials.ssid,
            password: credentials.password,
            securityType: credentials.securityType,
            isHidden: credentials.isHidden,
          );
          
          print('Connection Result: ${result.message}');
        },
        onError: (String error) {
          // Triggered if permissions are denied or scanning fails
          print('Scanner Error: $error');
        },
      ),
    );
  }
}
```
