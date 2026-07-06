import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_connector_plus/wifi_connector_plus.dart';

void main() {
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
          primary: Color(0xFF00F2FE),
          secondary: Color(0xFF4FACFE),
          surface: Color(0xFF1E293B),
          onSurface: Color(0xFFF8FAFC),
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
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
          labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
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

  final _qrController = TextEditingController(
    text: 'WIFI:S:securessid;T:WPA2;P:securePassword;H:false;;',
  );
  WifiCredentials? _parsedCredentials;

  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  WifiSecurityType _securityType = WifiSecurityType.wpa;
  bool _isHidden = false;
  bool _obscurePassword = true;

  bool _fillFieldsOnScan = true;
  bool _isConnecting = false;
  String _statusMessage = 'Idle';
  bool _lastConnectionSuccess = false;
  String? _currentSsid;

  StreamSubscription<String?>? _ssidSubscription;

  @override
  void initState() {
    super.initState();
    _parseCurrentQr();
    _qrController.addListener(_parseCurrentQr);
    _requestLocationPermissionOnStartup();
    _ssidSubscription = _wifiConnector.ssidStream.listen(
      (ssid) {
        if (mounted) setState(() => _currentSsid = ssid);
      },
      onError: (e) => developer.log('SSID stream error: $e', name: 'WifiConnectorPlus'),
    );
  }

  Future<void> _updateCurrentSsid() async {
    try {
      final ssid = await _wifiConnector.getCurrentSsid();
      setState(() => _currentSsid = ssid);
    } catch (e) {
      developer.log('Failed to get current SSID: $e', name: 'WifiConnectorPlus');
    }
  }

  Future<void> _requestLocationPermissionOnStartup() async {
    try {
      final granted = await _wifiConnector.requestLocationPermission();
      if (!granted) {
        setState(() => _statusMessage = 'Location permission is required for Wi-Fi connection.');
      }
    } catch (e) {
      setState(() => _statusMessage = 'Error requesting location permission on startup: $e');
    }
  }

  @override
  void dispose() {
    _ssidSubscription?.cancel();
    _qrController.removeListener(_parseCurrentQr);
    _qrController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }


  Future<void> _requestAndScanQr() async {
    try {
      final status = await Permission.camera.status;
      if (status.isGranted) {
        await _scanAndConnect();
      } else if (status.isPermanentlyDenied) {
        setState(() {
          _statusMessage = 'Camera permission permanently denied. Enable in Settings.';
        });
        _showSettingsDialog('Camera Permission Required', 'Camera permission is required to scan QR codes.');
      } else {
        final result = await Permission.camera.request();
        if (result.isGranted) {
          await _scanAndConnect();
        } else {
          setState(() => _statusMessage = 'Camera permission denied. Cannot scan QR.');
        }
      }
    } catch (e) {
      setState(() => _statusMessage = 'Camera permission request exception: $e');
    }
  }

  void _showSettingsDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text('Open Settings'),
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  void _parseCurrentQr() {
    setState(() => _parsedCredentials = _wifiConnector.parseWifiQr(_qrController.text));
  }

  Future<void> _connect({
    required String ssid,
    String? password,
    WifiSecurityType securityType = WifiSecurityType.wpa,
    bool isHidden = false,
  }) async {
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an SSID')));
      return;
    }

    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    setState(() {
      _isConnecting = true;
      _statusMessage = isAndroid
          ? 'Opening Wi-Fi dialog for $ssid... Please approve in prompt.'
          : 'Connecting to Wi-Fi: $ssid...';
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

      if (!result.isSuccess) {
        if (result.error == WifiConnectError.permissionDenied) {
          _showSettingsDialog('Location Required', 'Location permission is required to scan/connect.');
        } else if (result.error == WifiConnectError.userCancelled) {
          setState(() => _statusMessage = 'Connection cancelled by user.');
        }
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _lastConnectionSuccess = false;
        _statusMessage = 'Connection failed: $e';
      });
      await _updateCurrentSsid();
    }
  }

  Future<void> _scanAndConnect() async {
    try {
      final result = await showDialog<(WifiCredentials, String)?>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: const Color(0xFF1E293B),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('Scan QR Code'),
                automaticallyImplyLeading: false,
                actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))],
              ),
              SizedBox(
                height: 300,
                child: WifiQrScannerView(
                  language: WifiScannerLanguage.english,
                  onScanSuccess: (cred, raw) => Navigator.pop(context, (cred, raw)),
                  onError: (err) => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      );

      if (result != null) {
        final (credentials, rawValue) = result;
        setState(() => _qrController.text = rawValue);

        if (_fillFieldsOnScan) {
          setState(() {
            _ssidController.text = credentials.ssid;
            _passwordController.text = credentials.password ?? '';
            _securityType = credentials.securityType;
            _isHidden = credentials.isHidden;
          });
        }
        _showConnectionOptionDialog(credentials);
      }
    } catch (e) {
      setState(() => _statusMessage = 'Scanner failed: $e');
    }
  }

  void _showConnectionOptionDialog(WifiCredentials credentials) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wi-Fi QR Scanned'),
        content: Text('SSID: ${credentials.ssid}\nSecurity: ${credentials.securityType.name.toUpperCase()}\n\nConnect now?'),
        actions: [
          TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
          ElevatedButton(
            child: const Text('Connect Now'),
            onPressed: () {
              Navigator.of(context).pop();
              _connect(
                ssid: credentials.ssid,
                password: credentials.password,
                securityType: credentials.securityType,
                isHidden: credentials.isHidden,
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Connector Plus', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Status Card
            Card(
              color: const Color(0xFF1E293B),
              child: ListTile(
                leading: _isConnecting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        _lastConnectionSuccess ? Icons.check_circle : Icons.info,
                        color: _lastConnectionSuccess ? Colors.green : Colors.cyan,
                      ),
                title: Text(
                  _isConnecting ? 'CONNECTING' : (_lastConnectionSuccess ? 'CONNECTED' : 'STATUS'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(_statusMessage),
                trailing: _currentSsid != null ? Chip(label: Text(_currentSsid!)) : null,
              ),
            ),
            const SizedBox(height: 16),

            // How to Use Card
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('How to Connect to Wi-Fi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Divider(),
                    _buildStepRow('1', 'Grant location & camera permissions if asked.'),
                    _buildStepRow('2', 'Scan a Wi-Fi QR code or use the manual connection form.'),
                    _buildStepRow('3', 'Confirm the system prompt to join the network.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Scan QR Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F2FE), foregroundColor: Colors.black),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Wi-Fi QR Code', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: !_isConnecting ? _requestAndScanQr : null,
              ),
            ),
            const SizedBox(height: 16),

            // QR Raw String Card
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _qrController,
                      decoration: const InputDecoration(labelText: 'Raw QR String', hintText: 'WIFI:S:SSID;T:WPA;P:Password;;'),
                      maxLines: 2,
                    ),
                    if (_parsedCredentials != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Parsed: ${_parsedCredentials!.ssid} (${_parsedCredentials!.securityType.name.toUpperCase()})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, color: Color(0xFF00F2FE)),
                            onPressed: () {
                              setState(() {
                                _ssidController.text = _parsedCredentials!.ssid;
                                _passwordController.text = _parsedCredentials!.password ?? '';
                                _securityType = _parsedCredentials!.securityType;
                                _isHidden = _parsedCredentials!.isHidden;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                    SwitchListTile(
                      title: const Text('Autofill form fields on scan', style: TextStyle(fontSize: 13)),
                      value: _fillFieldsOnScan,
                      onChanged: (val) => setState(() => _fillFieldsOnScan = val),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _parsedCredentials != null && !_isConnecting
                            ? () => _connect(
                                  ssid: _parsedCredentials!.ssid,
                                  password: _parsedCredentials!.password,
                                  securityType: _parsedCredentials!.securityType,
                                  isHidden: _parsedCredentials!.isHidden,
                                )
                            : null,
                        child: const Text('Connect QR Credentials'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Manual Form Card
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Manual Connection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ssidController,
                      decoration: const InputDecoration(labelText: 'SSID (Network Name)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<WifiSecurityType>(
                      initialValue: _securityType,
                      decoration: const InputDecoration(labelText: 'Security Type'),
                      items: WifiSecurityType.values.map((type) {
                        return DropdownMenuItem(value: type, child: Text(type.name.toUpperCase()));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _securityType = val);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Is Hidden Network?', style: TextStyle(fontSize: 13)),
                      value: _isHidden,
                      onChanged: (val) => setState(() => _isHidden = val),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FACFE), foregroundColor: Colors.black),
                        onPressed: !_isConnecting
                            ? () => _connect(
                                  ssid: _ssidController.text.trim(),
                                  password: _passwordController.text.isEmpty ? null : _passwordController.text,
                                  securityType: _securityType,
                                  isHidden: _isHidden,
                                )
                            : null,
                        child: const Text('Connect Manually', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 10, backgroundColor: const Color(0xFF00F2FE), child: Text(num, style: const TextStyle(fontSize: 10, color: Colors.black))),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
