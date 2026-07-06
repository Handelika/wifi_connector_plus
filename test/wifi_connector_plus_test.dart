import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:wifi_connector_plus/wifi_connector_plus.dart';
import 'package:wifi_connector_plus/src/wifi_connector_plus_platform_interface.dart';
import 'package:wifi_connector_plus/src/wifi_connector_plus_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockWifiConnectorPlusPlatform
    with MockPlatformInterfaceMixin
    implements WifiConnectorPlusPlatform {
  bool shouldThrowInvalidCredentials = false;
  String? mockCurrentSsid;

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<bool> connect(
    String ssid,
    String? password,
    String securityType,
    bool isHidden,
  ) {
    if (shouldThrowInvalidCredentials) {
      throw PlatformException(
        code: 'INVALID_CREDENTIALS',
        message: 'Password is required for secured network type: $securityType',
      );
    }
    return Future.value(ssid == 'ValidSSID' && password == 'ValidPassword');
  }

  @override
  Future<String?> getCurrentSsid() => Future.value(mockCurrentSsid);

  @override
  // TODO: implement ssidStream
  Stream<String?> get ssidStream => throw UnimplementedError();
}

void main() {
  final WifiConnectorPlusPlatform initialPlatform =
      WifiConnectorPlusPlatform.instance;

  test('$MethodChannelWifiConnectorPlus is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelWifiConnectorPlus>());
  });

  group('WifiConnectorPlus', () {
    late WifiConnectorPlus wifiConnector;
    late MockWifiConnectorPlusPlatform fakePlatform;

    setUp(() {
      wifiConnector = WifiConnectorPlus();
      fakePlatform = MockWifiConnectorPlusPlatform();
      WifiConnectorPlusPlatform.instance = fakePlatform;
    });

    test('getPlatformVersion', () async {
      expect(await wifiConnector.getPlatformVersion(), '42');
    });

    test('connect manual - success', () async {
      final result = await wifiConnector.connect(
        ssid: 'ValidSSID',
        password: 'ValidPassword',
        securityType: WifiSecurityType.wpa,
      );
      expect(result.isSuccess, isTrue);
      expect(result.error, isNull);
    });

    test(
      'connect manual - failure when connected to a different SSID',
      () async {
        fakePlatform.mockCurrentSsid = 'DifferentSSID';
        final result = await wifiConnector.connect(
          ssid: 'ValidSSID',
          password: 'ValidPassword',
          securityType: WifiSecurityType.wpa,
        );
        expect(result.isSuccess, isFalse);
        expect(result.message, contains('Connected to a different network'));
      },
    );

    test('connect manual - failure', () async {
      final result = await wifiConnector.connect(
        ssid: 'InvalidSSID',
        password: 'WrongPassword',
        securityType: WifiSecurityType.wpa,
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, WifiConnectError.unknown);
    });

    test('connect manual - invalid credentials platform exception', () async {
      fakePlatform.shouldThrowInvalidCredentials = true;
      final result = await wifiConnector.connect(
        ssid: 'ValidSSID',
        password: '',
        securityType: WifiSecurityType.wpa,
      );
      expect(result.isSuccess, isFalse);
      expect(result.error, WifiConnectError.invalidCredentials);
      expect(result.message, contains('Password is required'));
    });

    test('connectWithQr - success', () async {
      final result = await wifiConnector.connectWithQr(
        'WIFI:S:ValidSSID;T:WPA;P:ValidPassword;;',
      );
      expect(result.isSuccess, isTrue);
    });
  });

  group('WifiQrParser', () {
    test('parses standard WPA wifi QR string', () {
      final creds = WifiQrParser.parse('WIFI:S:MyNetwork;T:WPA;P:SecretPass;;');
      expect(creds, isNotNull);
      expect(creds!.ssid, 'MyNetwork');
      expect(creds.password, 'SecretPass');
      expect(creds.securityType, WifiSecurityType.wpa);
      expect(creds.isHidden, isFalse);
    });

    test('parses WEP wifi QR string', () {
      final creds = WifiQrParser.parse('WIFI:S:HomeNet;T:WEP;P:12345;;');
      expect(creds, isNotNull);
      expect(creds!.ssid, 'HomeNet');
      expect(creds.password, '12345');
      expect(creds.securityType, WifiSecurityType.wep);
    });

    test('parses open wifi QR string', () {
      final creds = WifiQrParser.parse('WIFI:S:FreeWifi;T:nopass;;');
      expect(creds, isNotNull);
      expect(creds!.ssid, 'FreeWifi');
      expect(creds.password, isNull);
      expect(creds.securityType, WifiSecurityType.none);
    });

    test('parses hidden wifi QR string', () {
      final creds = WifiQrParser.parse('WIFI:S:HiddenAP;T:WPA;P:pass;H:true;;');
      expect(creds, isNotNull);
      expect(creds!.ssid, 'HiddenAP');
      expect(creds.isHidden, isTrue);
    });

    test('parses escaped characters correctly', () {
      final creds = WifiQrParser.parse(
        r'WIFI:S:My\;Network;T:WPA;P:P\@ss\:word;;',
      );
      expect(creds, isNotNull);
      expect(creds!.ssid, 'My;Network');
      expect(creds.password, r'P@ss:word');
    });

    test('returns null for invalid prefix', () {
      final creds = WifiQrParser.parse('NOTWIFI:S:MyNetwork;;');
      expect(creds, isNull);
    });

    test('returns null for missing SSID', () {
      final creds = WifiQrParser.parse('WIFI:T:WPA;P:Pass;;');
      expect(creds, isNull);
    });

    test('parses wifi QR with lowercase keys', () {
      final creds = WifiQrParser.parse('WIFI:s:lowercase;t:wpa;p:pass;;');
      expect(creds, isNotNull);
      expect(creds!.ssid, 'lowercase');
      expect(creds.password, 'pass');
      expect(creds.securityType, WifiSecurityType.wpa);
    });

    test('parses wifi QR with double semicolons robustly', () {
      final creds = WifiQrParser.parse(
        'WIFI:S:MyNetwork;;T:WPA;P:SecretPass;;',
      );
      expect(creds, isNotNull);
      expect(creds!.ssid, 'MyNetwork');
      expect(creds.password, 'SecretPass');
      expect(creds.securityType, WifiSecurityType.wpa);
    });

    test('parses wifi QR with surrounding quotes correctly', () {
      final creds = WifiQrParser.parse('WIFI:S:"MyNetwork";P:"SecretPass";;');
      expect(creds, isNotNull);
      expect(creds!.ssid, 'MyNetwork');
      expect(creds.password, 'SecretPass');
    });

    test(
      'defaults to WPA when security type is omitted but password is present',
      () {
        final creds = WifiQrParser.parse('WIFI:S:MyNetwork;P:SecretPass;;');
        expect(creds, isNotNull);
        expect(creds!.ssid, 'MyNetwork');
        expect(creds.password, 'SecretPass');
        expect(creds.securityType, WifiSecurityType.wpa);
      },
    );
  });
}
