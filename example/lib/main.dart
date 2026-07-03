import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_connector_plus/wifi_connector_plus.dart';

void main() {
  // Ensure status bar style matches our dark design
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wi-Fi Connector Plus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F2FE), // Cyan
          secondary: Color(0xFF4FACFE), // Teal/Blue
          surface: Color(0xFF1E293B), // Slate 800
          onSurface: Color(0xFFF8FAFC), // Slate 50
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const WifiConnectorHomePage(),
    );
  }
}

class WifiConnectorHomePage extends StatefulWidget {
  const WifiConnectorHomePage({super.key});

  @override
  State<WifiConnectorHomePage> createState() => _WifiConnectorHomePageState();
}

class _WifiConnectorHomePageState extends State<WifiConnectorHomePage> {
  final _wifiConnector = WifiConnectorPlus();

  // QR Form
  final _qrController = TextEditingController(
    text: 'WIFI:S:securessid;T:WPA2;P:securePassword;H:false;;',
  );
  WifiCredentials? _parsedCredentials;

  // Manual Form
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  WifiSecurityType _securityType = WifiSecurityType.wpa;
  bool _isHidden = false;
  bool _obscurePassword = true;

  // Permission state
  PermissionStatus _cameraPermissionStatus = PermissionStatus.denied;
  bool _fillFieldsOnScan = true;

  bool _isConnecting = false;
  String _statusMessage = 'Idle';
  bool _lastConnectionSuccess = false;
  String? _currentSsid;

  @override
  void initState() {
    super.initState();
    _parseCurrentQr();
    _qrController.addListener(_parseCurrentQr);
    _checkCameraPermission();
    _requestLocationPermissionOnStartup().then((_) => _updateCurrentSsid());
  }

  /// Updates the currently connected Wi-Fi network's SSID.
  Future<void> _updateCurrentSsid() async {
    try {
      final ssid = await _wifiConnector.getCurrentSsid();
      setState(() {
        _currentSsid = ssid;
      });
    } catch (e) {
      developer.log(
        'Failed to get current SSID: $e',
        name: 'WifiConnectorExample',
      );
    }
  }

  /// Requests location permission when the app starts.
  Future<void> _requestLocationPermissionOnStartup() async {
    try {
      developer.log(
        'Requesting location permission on startup...',
        name: 'WifiConnectorExample',
      );
      final granted = await _wifiConnector.requestLocationPermission();
      developer.log(
        'Startup location permission status: $granted',
        name: 'WifiConnectorExample',
      );
      if (!granted) {
        setState(() {
          _statusMessage =
              'Location permission is required for Wi-Fi connection.';
        });
      }
    } catch (e, stackTrace) {
      developer.log(
        'Failed to request location permission on startup',
        error: e,
        stackTrace: stackTrace,
        name: 'WifiConnectorExample',
      );
      setState(() {
        _statusMessage = 'Error requesting location permission on startup: $e';
      });
    }
  }

  @override
  void dispose() {
    _qrController.removeListener(_parseCurrentQr);
    _qrController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Checks the current camera permission status.
  Future<void> _checkCameraPermission() async {
    try {
      developer.log(
        'Checking camera permission...',
        name: 'WifiConnectorExample',
      );
      final status = await Permission.camera.status;
      developer.log(
        'Camera permission status: $status',
        name: 'WifiConnectorExample',
      );
      setState(() {
        _cameraPermissionStatus = status;
      });
    } catch (e, stackTrace) {
      developer.log(
        'Failed to check camera permission status',
        error: e,
        stackTrace: stackTrace,
        name: 'WifiConnectorExample',
      );
      setState(() {
        _statusMessage = 'Error checking camera permission: $e';
      });
    }
  }

  /// Requests camera permission if not granted. If granted, opens the scanner widget.
  Future<void> _requestAndScanQr() async {
    try {
      developer.log(
        'Requesting camera permission...',
        name: 'WifiConnectorExample',
      );

      final status = await Permission.camera.status;

      if (status.isGranted) {
        developer.log(
          'Camera permission already granted. Proceeding to scanner...',
          name: 'WifiConnectorExample',
        );
        setState(() {
          _cameraPermissionStatus = PermissionStatus.granted;
        });
        await _scanAndConnect();
      } else if (status.isPermanentlyDenied) {
        developer.log(
          'Camera permission permanently denied by user.',
          name: 'WifiConnectorExample',
        );
        setState(() {
          _cameraPermissionStatus = PermissionStatus.permanentlyDenied;
          _statusMessage =
              'Camera permission permanently denied. Enable in Settings.';
        });
        _showPermissionSettingsDialog();
      } else {
        final result = await Permission.camera.request();
        developer.log(
          'Camera permission request result: $result',
          name: 'WifiConnectorExample',
        );
        setState(() {
          _cameraPermissionStatus = result;
        });

        if (result.isGranted) {
          developer.log(
            'Camera permission granted. Proceeding to scanner...',
            name: 'WifiConnectorExample',
          );
          await _scanAndConnect();
        } else {
          developer.log(
            'Camera permission denied by user after prompt.',
            name: 'WifiConnectorExample',
          );
          setState(() {
            _statusMessage = 'Camera permission denied. Cannot scan QR.';
          });
        }
      }
    } catch (e, stackTrace) {
      developer.log(
        'Exception raised during permission request flow',
        error: e,
        stackTrace: stackTrace,
        name: 'WifiConnectorExample',
      );
      setState(() {
        _statusMessage = 'Camera permission request exception: $e';
      });
    }
  }

  /// Prompts user with a styled dialog to open app settings if permission is permanently denied.
  void _showPermissionSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _buildModernDialog(
          title: 'Camera Permission Required',
          content:
              'Camera permission is required to scan QR codes. '
              'Please open application settings and grant camera access.',
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F2FE),
                foregroundColor: const Color(0xFF0F172A),
              ),
              child: const Text(
                'Open Settings',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  /// Prompts user with a styled dialog to open app settings if location permission is permanently denied.
  void _showLocationSettingsDialog({bool isPreciseRequired = false}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _buildModernDialog(
          title: isPreciseRequired
              ? 'Precise Location Required'
              : 'Location Permission Required',
          content: isPreciseRequired
              ? 'Precise location permission (ACCESS_FINE_LOCATION) is required on Android to verify and connect to Wi-Fi networks. Please open settings and ensure location access is set to "Precise" (or enabled).'
              : 'Location permission is required on Android to detect and connect to Wi-Fi networks. Please open application settings and grant location access.',
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F2FE),
                foregroundColor: const Color(0xFF0F172A),
              ),
              child: const Text(
                'Open Settings',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  void _parseCurrentQr() {
    setState(() {
      _parsedCredentials = _wifiConnector.parseWifiQr(_qrController.text);
    });
  }

  /// Unified method to handle Wi-Fi connection attempts.
  Future<void> _connect({
    required String ssid,
    String? password,
    WifiSecurityType securityType = WifiSecurityType.wpa,
    bool isHidden = false,
    String connectionTypeLabel = 'Wi-Fi',
  }) async {
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        _buildCustomSnackBar('Please enter an SSID', isError: true),
      );
      return;
    }

    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    setState(() {
      _isConnecting = true;
      _statusMessage = isAndroid
          ? 'Opening Wi-Fi dialog for $ssid... Please approve in the system prompt.'
          : 'Connecting to $connectionTypeLabel: $ssid...';
    });

    try {
      final result = await _wifiConnector.connect(
        ssid: ssid,
        password: password,
        securityType: securityType,
        isHidden: isHidden,
      );

      setState(() {
        _isConnecting = false;
        _lastConnectionSuccess = result.isSuccess;
        _statusMessage = result.message;
      });

      await _updateCurrentSsid();

      if (!result.isSuccess &&
          result.error == WifiConnectError.permissionDenied) {
        _showLocationSettingsDialog(isPreciseRequired: true);
      }
      if (!result.isSuccess && result.error == WifiConnectError.userCancelled) {
        setState(() {
          _statusMessage = 'Connection cancelled by user.';
        });
      }
    } catch (e, stackTrace) {
      developer.log(
        'Exception trying to connect to Wi-Fi',
        error: e,
        stackTrace: stackTrace,
        name: 'WifiConnectorExample',
      );
      setState(() {
        _isConnecting = false;
        _lastConnectionSuccess = false;
        _statusMessage = 'Connection failed: $e';
      });
      await _updateCurrentSsid();
    }
  }

  Future<void> _connectWithQr() async {
    final credentials = _wifiConnector.parseWifiQr(_qrController.text);
    if (credentials == null) {
      setState(() {
        _statusMessage = 'Invalid Wi-Fi QR code format';
      });
      return;
    }

    await _connect(
      ssid: credentials.ssid,
      password: credentials.password,
      securityType: credentials.securityType,
      isHidden: credentials.isHidden,
      connectionTypeLabel: 'QR Wi-Fi',
    );
  }

  /// Opens the self-contained WifiQrScannerView. Once a QR is scanned, parses credentials
  /// and updates the manual form input fields. It also asks the user if they wish to connect immediately.
  Future<void> _scanAndConnect() async {
    developer.log('Launching scanner view...', name: 'WifiConnectorExample');
    try {
      final result = await showDialog<(WifiCredentials, String)?>(
        context: context,
        builder: (context) {
          return Dialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0xFF334155)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: 320,
                height: 420,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      color: const Color(0xFF0F172A),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Scan Wi-Fi QR Code',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: WifiQrScannerView(
                          onScanSuccess: (credentials, rawValue) {
                            developer.log(
                              'QR Code scanned successfully for SSID: ${credentials.ssid}',
                              name: 'WifiConnectorExample',
                            );
                            Navigator.pop(context, (credentials, rawValue));
                          },
                          onError: (error) {
                            developer.log(
                              'QR Scanner encountered error: $error',
                              name: 'WifiConnectorExample',
                            );
                            Navigator.pop(context); // close dialog
                            ScaffoldMessenger.of(context).showSnackBar(
                              _buildCustomSnackBar(
                                'Scanner Error: $error',
                                isError: true,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      if (result != null) {
        final (credentials, rawValue) = result;
        if (!mounted) return;

        setState(() {
          _qrController.text = rawValue;
        });

        if (_fillFieldsOnScan) {
          developer.log(
            'Setting scanned credentials to UI controller fields.',
            name: 'WifiConnectorExample',
          );
          setState(() {
            _ssidController.text = credentials.ssid;
            _passwordController.text = credentials.password ?? '';
            _securityType = credentials.securityType;
            _isHidden = credentials.isHidden;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            _buildCustomSnackBar(
              'Loaded scanned credentials for "${credentials.ssid}"',
            ),
          );
        } else {
          developer.log(
            'Scanned credentials parsed but not written to manual fields.',
            name: 'WifiConnectorExample',
          );
        }

        _showConnectionOptionDialog(credentials);
      }
    } catch (e, stackTrace) {
      developer.log(
        'Exception in scanning/listening sequence',
        error: e,
        stackTrace: stackTrace,
        name: 'WifiConnectorExample',
      );
      setState(() {
        _statusMessage = 'Scanner initialization failed: $e';
      });
    }
  }

  /// Prompts user to ask if they want to connect automatically or just parse the info.
  void _showConnectionOptionDialog(WifiCredentials credentials) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _buildModernDialog(
          title: 'Wi-Fi QR Scanned',
          content:
              'SSID: ${credentials.ssid}\n'
              'Security: ${credentials.securityType.name.toUpperCase()}\n\n'
              'Do you want to connect to this Wi-Fi network now?',
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text(
                'Fill Fields Only',
                style: TextStyle(color: Color(0xFF00F2FE)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _ssidController.text = credentials.ssid;
                  _passwordController.text = credentials.password ?? '';
                  _securityType = credentials.securityType;
                  _isHidden = credentials.isHidden;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  _buildCustomSnackBar(
                    'Loaded scanned credentials for "${credentials.ssid}"',
                  ),
                );
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F2FE),
                foregroundColor: const Color(0xFF0F172A),
              ),
              child: const Text(
                'Connect Now',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _connectWithScannedCredentials(credentials);
              },
            ),
          ],
        );
      },
    );
  }

  /// Establishes Wi-Fi connection utilizing scanned credentials.
  Future<void> _connectWithScannedCredentials(
    WifiCredentials credentials,
  ) async {
    await _connect(
      ssid: credentials.ssid,
      password: credentials.password,
      securityType: credentials.securityType,
      isHidden: credentials.isHidden,
      connectionTypeLabel: 'scanned QR Wi-Fi',
    );
  }

  Future<void> _connectManually() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    await _connect(
      ssid: ssid,
      password: password.isEmpty ? null : password,
      securityType: _securityType,
      isHidden: _isHidden,
      connectionTypeLabel: 'manually configured Wi-Fi',
    );
  }

  void _fillManualFromParsed() {
    if (_parsedCredentials != null) {
      setState(() {
        _ssidController.text = _parsedCredentials!.ssid;
        _passwordController.text = _parsedCredentials!.password ?? '';
        _securityType = _parsedCredentials!.securityType;
        _isHidden = _parsedCredentials!.isHidden;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(_buildCustomSnackBar('Copied QR details to manual form'));
    }
  }

  // --- UI Helpers ---

  SnackBar _buildCustomSnackBar(String message, {bool isError = false}) {
    return SnackBar(
      backgroundColor: isError
          ? const Color(0xFFE94057)
          : const Color(0xFF1E293B),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.white : const Color(0xFF00F2FE),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white,
                fontWeight: isError ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDialog({
    required String title,
    required String content,
    required List<Widget> actions,
  }) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      content: Text(
        content,
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
      ),
      actions: actions,
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF00F2FE), size: 24),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    required VoidCallback? onPressed,
    required String label,
    required IconData icon,
    bool isSecondary = false,
  }) {
    final gradient = isSecondary
        ? const LinearGradient(colors: [Color(0xFF8A2387), Color(0xFFE94057)])
        : const LinearGradient(colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)]);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: onPressed != null ? gradient : null,
        color: onPressed == null ? const Color(0xFF334155) : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: isSecondary
                      ? const Color(0x4DE94057)
                      : const Color(0x4D00F2FE),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: onPressed == null
                      ? const Color(0xFF64748B)
                      : Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: onPressed == null
                        ? const Color(0xFF64748B)
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    String? hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      suffixIcon: suffixIcon,
      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine dynamic background and colors for the connection status card
    Color statusBorderColor = const Color(0xFF334155);
    Color statusBgColor = const Color(0xFF1E293B);
    Color statusTextGradientColor = const Color(0xFF94A3B8);
    IconData statusIcon = Icons.info_outline;

    if (_isConnecting) {
      statusBorderColor = const Color(0x8000F2FE);
      statusBgColor = const Color(0x0D00F2FE);
      statusTextGradientColor = const Color(0xFF00F2FE);
      statusIcon = Icons.sync;
    } else if (_statusMessage != 'Idle') {
      if (_lastConnectionSuccess) {
        statusBorderColor = const Color(0x8010B981);
        statusBgColor = const Color(0x0D10B981);
        statusTextGradientColor = const Color(0xFF10B981);
        statusIcon = Icons.check_circle_outline;
      } else {
        statusBorderColor = const Color(0x80EF4444);
        statusBgColor = const Color(0x0DEF4444);
        statusTextGradientColor = const Color(0xFFEF4444);
        statusIcon = Icons.error_outline;
      }
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Elegant Header / App Bar
          SliverAppBar(
            expandedHeight: 120.0,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF0F172A),
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Wi-Fi Connector Plus',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              centerTitle: true,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0B0F19), Color(0xFF0F172A)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),

          // Main body content
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Connection Status Panel
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusBorderColor),
                  ),
                  child: Row(
                    children: [
                      if (_isConnecting)
                        const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF00F2FE),
                            ),
                          ),
                        )
                      else
                        Icon(
                          statusIcon,
                          color: statusTextGradientColor,
                          size: 28,
                        ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isConnecting
                                  ? 'STATUS: CONNECTING'
                                  : 'STATUS: ${_statusMessage == 'Idle' ? 'IDLE' : (_lastConnectionSuccess ? 'CONNECTED' : 'DISCONNECTED')}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                                color: statusTextGradientColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _statusMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (_currentSsid != null &&
                                _currentSsid!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.wifi,
                                    size: 14,
                                    color: statusTextGradientColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Active SSID: $_currentSsid',
                                    style: TextStyle(
                                      color: statusTextGradientColor.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Quick Launch Scanner widget
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x4D00F2FE),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: !_isConnecting ? _requestAndScanQr : null,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 24,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.qr_code_scanner,
                              color: Color(0xFF0F172A),
                              size: 28,
                            ),
                            const SizedBox(width: 14),
                            Text(
                              _cameraPermissionStatus.isGranted
                                  ? 'Scan Wi-Fi QR Code'
                                  : 'Launch QR Scanner',
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // QR Section
                _buildSectionCard(
                  title: 'Connect via QR Raw String',
                  icon: Icons.code,
                  children: [
                    TextField(
                      controller: _qrController,
                      decoration: _buildInputDecoration(
                        labelText: 'Raw QR String',
                        hintText: 'WIFI:S:SSID;T:WPA;P:Password;;',
                      ),
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    if (_parsedCredentials != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PARSED CREDENTIALS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                                color: Color(0xFF00F2FE),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow('SSID:', _parsedCredentials!.ssid),
                            _buildInfoRow(
                              'Security:',
                              _parsedCredentials!.securityType.name
                                  .toUpperCase(),
                            ),
                            _buildInfoRow(
                              'Password:',
                              _parsedCredentials!.password ?? 'None',
                            ),
                            _buildInfoRow(
                              'Hidden SSID:',
                              _parsedCredentials!.isHidden.toString(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0x337F1D1D),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x4DEF4444)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Color(0xFFF87171),
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Invalid Wi-Fi QR format detected',
                              style: TextStyle(
                                color: Color(0xFFF87171),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SwitchListTile(
                      title: const Text(
                        'Autofill manual connection fields on scan',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      value: _fillFieldsOnScan,
                      activeThumbColor: const Color(0xFF00F2FE),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onChanged: (val) {
                        setState(() {
                          _fillFieldsOnScan = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildGradientButton(
                            onPressed:
                                _parsedCredentials != null && !_isConnecting
                                ? _connectWithQr
                                : null,
                            icon: Icons.bolt,
                            label: 'Connect QR',
                          ),
                        ),
                        if (_parsedCredentials != null) ...[
                          const SizedBox(width: 12),
                          Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF334155),
                              ),
                            ),
                            child: IconButton(
                              onPressed: _fillManualFromParsed,
                              icon: const Icon(
                                Icons.copy,
                                color: Color(0xFF00F2FE),
                              ),
                              tooltip: 'Copy details to Manual Connection form',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),

                // Manual Connection Section
                _buildSectionCard(
                  title: 'Manual Connection',
                  icon: Icons.wifi,
                  children: [
                    TextField(
                      controller: _ssidController,
                      decoration: _buildInputDecoration(
                        labelText: 'SSID (Network Name)',
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: _buildInputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF94A3B8),
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<WifiSecurityType>(
                      initialValue: _securityType,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: _buildInputDecoration(
                        labelText: 'Security Type',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      items: WifiSecurityType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.name.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _securityType = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text(
                        'Is Hidden Network?',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      value: _isHidden,
                      activeThumbColor: const Color(0xFF00F2FE),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      onChanged: (val) {
                        setState(() {
                          _isHidden = val;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildGradientButton(
                      onPressed: !_isConnecting ? _connectManually : null,
                      icon: Icons.wifi,
                      label: 'Connect Manually',
                      isSecondary: true,
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
