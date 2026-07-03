import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector_plus/src/wifi_connector_plus_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelWifiConnectorPlus platform = MethodChannelWifiConnectorPlus();
  const MethodChannel channel = MethodChannel('wifi_connector_plus');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'getPlatformVersion') {
            return '42';
          } else if (methodCall.method == 'connect') {
            return true;
          } else if (methodCall.method == 'getCurrentSsid') {
            return 'MockSSID';
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('connect', () async {
    expect(await platform.connect('Ssid', 'Pass', 'WPA', false), isTrue);
  });

  test('getCurrentSsid', () async {
    expect(await platform.getCurrentSsid(), 'MockSSID');
  });
}
