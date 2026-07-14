import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'src/models/wifi_connect_result.dart';
import 'src/models/wifi_credentials.dart';
import 'src/wifi_connector_plus_platform_interface.dart';
import 'src/wifi_qr_parser.dart';

export 'src/models/wifi_connect_result.dart';
export 'src/models/wifi_credentials.dart';
export 'src/wifi_qr_parser.dart';
export 'src/widgets/wifi_qr_scanner_view.dart';
export 'src/widgets/wifi_qr_scanner_controller.dart';

class WifiConnectorPlus {
  /// Get the current platform version.
  Future<String?> getPlatformVersion() {
    return WifiConnectorPlusPlatform.instance.getPlatformVersion();
  }

  /// Checks if the location permission is granted on the device.
  ///
  /// On Android 9+, this permission is required to verify or establish Wi-Fi connections.
  Future<bool> isLocationPermissionGranted() async {
    if (!Platform.isAndroid) return true;
    return Permission.location.isGranted;
  }

  /// Requests the location permission on the device.
  ///
  /// Returns `true` if the permission was granted.
  Future<bool> requestLocationPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.location.request();
    return status.isGranted;
  }

  /// Connects to a Wi-Fi network manually using SSID, password, and security type.
  ///
  /// [ssid] The network name.
  /// [password] The security password/key.
  /// [securityType] The type of security (WPA, WEP, or none).
  /// [isHidden] Set to true if the network SSID is hidden.
  Future<WifiConnectResult> connect({
    required String ssid,
    String? password,
    WifiSecurityType securityType = WifiSecurityType.wpa,
    bool isHidden = false,
  }) async {
    if (ssid.isEmpty) {
      return WifiConnectResult.failure(
        message: 'SSID cannot be empty',
        error: WifiConnectError.invalidCredentials,
      );
    }

    try {
      // Native layer handles the full connection flow and fires the result
      // only after the attempt completes (event-driven, not polled):
      //
      //   iOS   : NEHotspotConfigurationManager.apply() callback
      //             → true             : joined successfully
      //             → "ALREADY_CONNECTED" : already on this SSID
      //             → FlutterError     : failed (wrong password, out of range…)
      //
      //   Android 10+ : ACTION_WIFI_ADD_NETWORKS + NetworkCallback
      //   Android <10 : WifiManager legacy + polling
      final nativeResult = await WifiConnectorPlusPlatform.instance.connect(
        ssid,
        password,
        securityType.valueString,
        isHidden,
      );

      if (nativeResult == 'ALREADY_CONNECTED') {
        return WifiConnectResult.success(message: 'Already connected to $ssid');
      }

      if (nativeResult == true) {
        return WifiConnectResult.success(
          message: 'Successfully connected to $ssid',
        );
      }

      return WifiConnectResult.failure(
        message:
            'Failed to connect to $ssid. Check credentials or network state.',
        error: WifiConnectError.unknown,
      );
    } on PlatformException catch (e) {
      WifiConnectError errorType = WifiConnectError.unknown;
      if (e.code == 'PERMISSION_DENIED') {
        errorType = WifiConnectError.permissionDenied;
      } else if (e.code == 'LOCATION_SERVICES_DISABLED') {
        errorType = WifiConnectError.permissionDenied;
      } else if (e.code == 'INVALID_CREDENTIALS') {
        errorType = WifiConnectError.invalidCredentials;
      } else if (e.code == 'CONNECTION_TIMEOUT') {
        errorType = WifiConnectError.timeout;
      } else if (e.code == 'NETWORK_UNAVAILABLE') {
        errorType = WifiConnectError.invalidCredentials;
      } else if (e.code == 'USER_CANCELLED') {
        errorType = WifiConnectError.userCancelled;
      } else if (e.code == 'WIFI_ERROR') {
        errorType = WifiConnectError.unknown;
      }
      return WifiConnectResult.failure(
        message: e.message ?? 'An error occurred: $e',
        error: errorType,
      );
    } on Exception catch (e) {
      return WifiConnectResult.failure(
        message: 'An error occurred: $e',
        error: WifiConnectError.unknown,
      );
    }
  }

  /// Connects to a Wi-Fi network using a standard Wi-Fi QR code string.
  ///
  /// [qrString] The Wi-Fi QR code string.
  Future<WifiConnectResult> connectWithQr(String qrString) async {
    final credentials = parseWifiQr(qrString);
    if (credentials == null) {
      return WifiConnectResult.failure(
        message: 'Invalid Wi-Fi QR code format',
        error: WifiConnectError.invalidCredentials,
      );
    }

    return connect(
      ssid: credentials.ssid,
      password: credentials.password,
      securityType: credentials.securityType,
      isHidden: credentials.isHidden,
    );
  }

  /// Parses a Wi-Fi QR code string into [WifiCredentials].
  ///
  /// Returns null if the format is invalid.
  WifiCredentials? parseWifiQr(String qrString) {
    return WifiQrParser.parse(qrString);
  }

  /// Gets the currently connected Wi-Fi network's SSID.
  ///
  /// Returns `null` if not connected or if location permission is not granted.
  Future<String?> getCurrentSsid() async {
    return WifiConnectorPlusPlatform.instance.getCurrentSsid();
  }

  /// A stream that continuously emits the currently connected Wi-Fi SSID.
  ///
  /// - Emits a [String] with the SSID when connected to a Wi-Fi network.
  /// - Emits `null` when disconnected or Wi-Fi is off.
  /// - On iOS, uses [NWPathMonitor] to detect network path changes.
  /// - On Android, uses [ConnectivityManager.NetworkCallback].
  ///
  /// Requires the `com.apple.developer.networking.wifi-info` entitlement on iOS.
  Stream<String?> get ssidStream {
    return WifiConnectorPlusPlatform.instance.ssidStream;
  }
}
