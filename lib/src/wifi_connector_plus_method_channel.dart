import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'wifi_connector_plus_platform_interface.dart';

/// An implementation of [WifiConnectorPlusPlatform] that uses method channels.
class MethodChannelWifiConnectorPlus extends WifiConnectorPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('wifi_connector_plus');

  /// The event channel used to stream SSID changes.
  @visibleForTesting
  final eventChannel = const EventChannel('wifi_connector_plus/ssid_stream');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<dynamic> connect(
    String ssid,
    String? password,
    String securityType,
    bool isHidden,
  ) async {
    try {
      // Returns:
      //   true                → connected successfully (iOS: SSID verified)
      //   false               → connection failed
      //   "ALREADY_CONNECTED" → already on this SSID (iOS)
      final result = await methodChannel.invokeMethod<dynamic>('connect', {
        'ssid': ssid,
        'password': password,
        'securityType': securityType,
        'isHidden': isHidden,
      });
      return result;
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: e.message ?? 'Unknown WiFi connection error',
        details: e.details,
      );
    }
  }

  @override
  Future<String?> getCurrentSsid() async {
    try {
      final result = await methodChannel.invokeMethod<String>('getCurrentSsid');
      return result;
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: e.message ?? 'Unknown error getting current SSID',
        details: e.details,
      );
    }
  }

  @override
  Stream<String?> get ssidStream {
    return eventChannel.receiveBroadcastStream().map(
      (event) => event as String?,
    );
  }
}
