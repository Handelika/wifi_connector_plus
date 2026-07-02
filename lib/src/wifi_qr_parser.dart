import 'models/wifi_credentials.dart';

class WifiQrParser {
  /// Parses a standard Wi-Fi QR code string.
  /// Format: `WIFI:S:<SSID>;T:<WEP|WPA|nopass>;P:<PASSWORD>;H:<true|false>;;`
  /// Returns [WifiCredentials] if valid, or `null` if the string cannot be parsed.
  static WifiCredentials? parse(String qrString) {
    final trimmed = qrString.trim();
    if (!trimmed.toUpperCase().startsWith('WIFI:')) {
      return null;
    }

    // Strip "WIFI:" prefix
    final content = trimmed.substring(5);

    String? ssid;
    String? password;
    String? type;
    bool isHidden = false;

    int index = 0;
    while (index < content.length) {
      // Skip leading/consecutive semicolons and whitespace
      while (index < content.length &&
          (content[index] == ';' || content[index].trim().isEmpty)) {
        index++;
      }
      if (index >= content.length) break;

      // Find the next colon that is not escaped to locate key
      int colonIdx = -1;
      for (int i = index; i < content.length; i++) {
        if (content[i] == ':' && (i == index || content[i - 1] != '\\')) {
          colonIdx = i;
          break;
        }
      }
      if (colonIdx == -1) break;

      final key = content.substring(index, colonIdx).trim().toUpperCase();

      // Now find the next semicolon that is not escaped
      int semiIdx = -1;
      for (int i = colonIdx + 1; i < content.length; i++) {
        if (content[i] == ';' &&
            (i == colonIdx + 1 || content[i - 1] != '\\')) {
          semiIdx = i;
          break;
        }
      }
      if (semiIdx == -1) {
        // If no semicolon, take the rest of the string
        semiIdx = content.length;
      }

      final rawValue = content.substring(colonIdx + 1, semiIdx);
      final value = cleanValue(_unescape(rawValue));

      if (key == 'S') {
        ssid = value;
      } else if (key == 'P') {
        password = value;
      } else if (key == 'T') {
        type = value;
      } else if (key == 'H') {
        isHidden = value.toLowerCase() == 'true';
      }

      index = semiIdx + 1;
    }

    if (ssid == null || ssid.isEmpty) {
      return null;
    }

    final parsedType = WifiSecurityType.fromString(type);
    var securityType = parsedType;
    if (parsedType == WifiSecurityType.none &&
        password != null &&
        password.isNotEmpty) {
      securityType = WifiSecurityType
          .wpa; // Default to WPA if password is provided but type is unspecified or none
    }

    return WifiCredentials(
      ssid: ssid,
      password: password,
      securityType: securityType,
      isHidden: isHidden,
    );
  }

  static String cleanValue(String value) {
    var cleaned = value.trim();
    if (cleaned.startsWith('"') &&
        cleaned.endsWith('"') &&
        cleaned.length >= 2) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    return cleaned;
  }

  static String _unescape(String value) {
    final sb = StringBuffer();
    bool escaped = false;
    for (int i = 0; i < value.length; i++) {
      final char = value[i];
      if (escaped) {
        sb.write(char);
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else {
        sb.write(char);
      }
    }
    return sb.toString();
  }
}
