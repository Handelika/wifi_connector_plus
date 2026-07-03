import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'wifi_connector_plus_method_channel.dart';

abstract class WifiConnectorPlusPlatform extends PlatformInterface {
  /// Constructs a WifiConnectorPlusPlatform.
  WifiConnectorPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static WifiConnectorPlusPlatform _instance = MethodChannelWifiConnectorPlus();

  /// The default instance of [WifiConnectorPlusPlatform] to use.
  ///
  /// Defaults to [MethodChannelWifiConnectorPlus].
  static WifiConnectorPlusPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [WifiConnectorPlusPlatform] when
  /// they register themselves.
  static set instance(WifiConnectorPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> connect(
    String ssid,
    String? password,
    String securityType,
    bool isHidden,
  ) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  Future<String?> getCurrentSsid() {
    throw UnimplementedError('getCurrentSsid() has not been implemented.');
  }
}
