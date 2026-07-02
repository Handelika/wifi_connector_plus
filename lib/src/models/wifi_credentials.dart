enum WifiSecurityType {
  wpa,
  wpa2,
  wpa3,
  wep,
  none;

  static WifiSecurityType fromString(String? type) {
    if (type == null) return WifiSecurityType.none;
    switch (type.toUpperCase()) {
      case 'WPA':
        return WifiSecurityType.wpa;
      case 'WPA2':
      case 'WPA/WPA2':
        return WifiSecurityType.wpa2;
      case 'WPA3':
        return WifiSecurityType.wpa3;
      case 'WEP':
        return WifiSecurityType.wep;
      case 'NOPASS':
      case 'NONE':
      default:
        return WifiSecurityType.none;
    }
  }

  String get valueString {
    switch (this) {
      case WifiSecurityType.wpa:
        return 'WPA';
      case WifiSecurityType.wpa2:
        return 'WPA2';
      case WifiSecurityType.wpa3:
        return 'WPA3';
      case WifiSecurityType.wep:
        return 'WEP';
      case WifiSecurityType.none:
        return 'nopass';
    }
  }
}

class WifiCredentials {
  final String ssid;
  final String? password;
  final WifiSecurityType securityType;
  final bool isHidden;

  const WifiCredentials({
    required this.ssid,
    this.password,
    this.securityType = WifiSecurityType.wpa,
    this.isHidden = false,
  });

  @override
  String toString() {
    return 'WifiCredentials(ssid: $ssid, securityType: ${securityType.name}, isHidden: $isHidden)';
  }
}
