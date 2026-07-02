import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'wifi_connector_plus_platform_interface.dart';

/// An implementation of [WifiConnectorPlusPlatform] that uses method channels.
class MethodChannelWifiConnectorPlus extends WifiConnectorPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('wifi_connector_plus');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<bool> connect(
    String ssid,
    String? password,
    String securityType,
    bool isHidden,
  ) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('connect', {
        'ssid': ssid,
        'password': password,
        'securityType': securityType,
        'isHidden': isHidden,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      // Re-throw with descriptive message so callers can show it in the UI
      throw PlatformException(
        code: e.code,
        message: e.message ?? 'Unknown WiFi connection error',
        details: e.details,
      );
    }
  }
}
