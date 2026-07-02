import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_connector_plus/wifi_connector_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wi-Fi Connector Plus',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
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

  bool _isConnecting = false;
  String _statusMessage = 'Idle';
  bool _lastConnectionSuccess = false;

  @override
  void initState() {
    super.initState();
    _parseCurrentQr();
    _qrController.addListener(_parseCurrentQr);
    _checkCameraPermission();
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
  /// Logs the result and handles exceptions if they arise.
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
  /// Handles various status outputs, provides logging and displays appropriate UI dialogs/messages.
  Future<void> _requestAndScanQr() async {
    try {
      developer.log(
        'Requesting camera permission...',
        name: 'WifiConnectorExample',
      );

      // Check current permission state
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
        // Request the permission explicitly
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

  /// Prompts user with a dialog to open app settings if permission is permanently denied.
  void _showPermissionSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Camera Permission Required'),
          content: const Text(
            'Camera permission is required to scan QR codes. '
            'Please open application settings and grant camera access.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Open Settings'),
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

  Future<void> _connectWithQr() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting via QR...';
    });

    final result = await _wifiConnector.connectWithQr(_qrController.text);

    setState(() {
      _isConnecting = false;
      _lastConnectionSuccess = result.isSuccess;
      _statusMessage = result.message;
    });
  }

  /// Opens the self-contained WifiQrScannerView. Once a QR is scanned, parses credentials
  /// and updates the manual form input fields. It also asks the user if they wish to connect immediately.
  Future<void> _scanAndConnect() async {
    developer.log('Launching scanner view...', name: 'WifiConnectorExample');
    try {
      final result = await Navigator.push<WifiCredentials?>(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            body: WifiQrScannerView(
              onScanSuccess: (credentials) {
                developer.log(
                  'QR Code scanned successfully for SSID: ${credentials.ssid}',
                  name: 'WifiConnectorExample',
                );
                Navigator.pop(context, credentials);
              },
              onError: (error) {
                developer.log(
                  'QR Scanner encountered error: $error',
                  name: 'WifiConnectorExample',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Scanner Error: $error')),
                );
              },
            ),
          ),
        ),
      );

      if (result != null) {
        if (!mounted) return;
        developer.log(
          'Setting scanned credentials to UI controller fields.',
          name: 'WifiConnectorExample',
        );
        setState(() {
          _ssidController.text = result.ssid;
          _passwordController.text = result.password ?? '';
          _securityType = result.securityType;
          _isHidden = result.isHidden;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded scanned credentials for "${result.ssid}"'),
          ),
        );

        _showConnectionOptionDialog(result);
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
        return AlertDialog(
          title: const Text('Wi-Fi QR Scanned'),
          content: Text(
            'SSID: ${credentials.ssid}\n'
            'Security: ${credentials.securityType.name.toUpperCase()}\n\n'
            'Do you want to connect to this Wi-Fi network now?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Fill Fields Only'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Connect Now'),
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
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting to scanned Wi-Fi: ${credentials.ssid}...';
    });

    try {
      final connResult = await _wifiConnector.connect(
        ssid: credentials.ssid,
        password: credentials.password,
        securityType: credentials.securityType,
        isHidden: credentials.isHidden,
      );

      setState(() {
        _isConnecting = false;
        _lastConnectionSuccess = connResult.isSuccess;
        _statusMessage = connResult.message;
      });
    } catch (e, stackTrace) {
      developer.log(
        'Exception trying to connect via scanned QR credentials',
        error: e,
        stackTrace: stackTrace,
        name: 'WifiConnectorExample',
      );
      setState(() {
        _isConnecting = false;
        _lastConnectionSuccess = false;
        _statusMessage = 'Connection failed: $e';
      });
    }
  }

  Future<void> _connectManually() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    if (ssid.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter an SSID')));
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting manually to $ssid...';
    });

    final result = await _wifiConnector.connect(
      ssid: ssid,
      password: password.isEmpty ? null : password,
      securityType: _securityType,
      isHidden: _isHidden,
    );

    setState(() {
      _isConnecting = false;
      _lastConnectionSuccess = result.isSuccess;
      _statusMessage = result.message;
    });
  }

  void _fillManualFromParsed() {
    if (_parsedCredentials != null) {
      setState(() {
        _ssidController.text = _parsedCredentials!.ssid;
        _passwordController.text = _parsedCredentials!.password ?? '';
        _securityType = _parsedCredentials!.securityType;
        _isHidden = _parsedCredentials!.isHidden;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied QR details to manual form')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Connector Plus Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              color: _isConnecting
                  ? Colors.blue.shade50
                  : (_statusMessage == 'Idle'
                        ? Colors.grey.shade100
                        : (_lastConnectionSuccess
                              ? Colors.green.shade50
                              : Colors.red.shade50)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Connection Status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_isConnecting)
                      const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (_isConnecting) const SizedBox(height: 8),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isConnecting
                            ? Colors.blue
                            : (_lastConnectionSuccess
                                  ? Colors.green
                                  : Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // QR Section
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect via QR Code Raw String',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _qrController,
                      decoration: const InputDecoration(
                        labelText: 'QR Code String',
                        border: OutlineInputBorder(),
                        hintText: 'WIFI:S:SSID;T:WPA;P:Password;;',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    if (_parsedCredentials != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Parsed QR Credentials:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text('SSID: ${_parsedCredentials!.ssid}'),
                            Text(
                              'Security: ${_parsedCredentials!.securityType.name.toUpperCase()}',
                            ),
                            Text(
                              'Password: ${_parsedCredentials!.password ?? "None"}',
                            ),
                            Text(
                              'Hidden SSID: ${_parsedCredentials!.isHidden}',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      const Text(
                        'Invalid QR string format',
                        style: TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ElevatedButton.icon(
                      onPressed: !_isConnecting ? _requestAndScanQr : null,
                      icon: const Icon(Icons.camera_alt),
                      label: Text(
                        _cameraPermissionStatus.isGranted
                            ? 'Scan QR with Camera'
                            : 'Scan QR (Requires Camera Permission)',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _parsedCredentials != null && !_isConnecting
                                ? _connectWithQr
                                : null,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Connect via QR'),
                          ),
                        ),
                        if (_parsedCredentials != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _fillManualFromParsed,
                            icon: const Icon(Icons.copy),
                            tooltip: 'Copy details to Manual Connection form',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Manual Connection Section
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manual Connection',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ssidController,
                      decoration: const InputDecoration(
                        labelText: 'SSID (Network Name)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<WifiSecurityType>(
                      initialValue: _securityType,
                      decoration: const InputDecoration(
                        labelText: 'Security Type',
                        border: OutlineInputBorder(),
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
                    CheckboxListTile(
                      title: const Text('Is Hidden Network?'),
                      value: _isHidden,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _isHidden = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: !_isConnecting ? _connectManually : null,
                      icon: const Icon(Icons.wifi),
                      label: const Text('Connect Manually'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
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
}
