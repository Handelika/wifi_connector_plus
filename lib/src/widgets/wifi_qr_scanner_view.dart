import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/wifi_credentials.dart';
import '../wifi_qr_parser.dart';

/// A self-contained widget that handles camera permissions, opens the camera stream,
/// scans for a Wi-Fi QR code, and parses it into [WifiCredentials].
class WifiQrScannerView extends StatefulWidget {
  /// Callback triggered when a valid Wi-Fi QR code is successfully scanned.
  /// Receives the parsed [WifiCredentials] and the original raw scanned QR string.
  final void Function(WifiCredentials credentials, String rawValue) onScanSuccess;

  /// Callback triggered when permission is denied or a scanned QR code cannot be parsed.
  final ValueChanged<String> onError;

  /// Custom widget to display while camera permission is being checked.
  final Widget? placeholder;

  /// Custom widget to display if camera permission is denied.
  final Widget? permissionDeniedPlaceholder;

  const WifiQrScannerView({
    super.key,
    required this.onScanSuccess,
    required this.onError,
    this.placeholder,
    this.permissionDeniedPlaceholder,
  });

  @override
  State<WifiQrScannerView> createState() => _WifiQrScannerViewState();
}

class _WifiQrScannerViewState extends State<WifiQrScannerView> {
  bool _hasPermission = false;
  bool _isChecking = true;
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    try {
      final status = await Permission.camera.status;
      if (status.isGranted) {
        setState(() {
          _hasPermission = true;
          _isChecking = false;
        });
      } else {
        final result = await Permission.camera.request();
        setState(() {
          _hasPermission = result.isGranted;
          _isChecking = false;
        });
        if (!result.isGranted) {
          widget.onError('Camera permission denied.');
        }
      }
    } catch (e, stack) {
      developer.log(
        'Exception while checking camera permission',
        error: e,
        stackTrace: stack,
        name: 'WifiQrScannerView',
      );
      widget.onError('Camera permission request failed: $e');
      setState(() {
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return widget.placeholder ??
          const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasPermission) {
      return widget.permissionDeniedPlaceholder ??
          Scaffold(
            appBar: AppBar(title: const Text('Camera Permission')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.camera_alt_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Camera permission is required to scan QR codes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _checkPermission,
                      child: const Text('Grant Camera Permission'),
                    ),
                  ],
                ),
              ),
            ),
          );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Wi-Fi QR Code'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                switch (state.torchState) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                  case TorchState.unavailable:
                  case TorchState.auto:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                }
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                switch (state.cameraDirection) {
                  case CameraFacing.front:
                    return const Icon(Icons.camera_front);
                  case CameraFacing.back:
                    return const Icon(Icons.camera_rear);
                }
              },
            ),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              try {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final code = barcodes.first.rawValue;
                  if (code != null && code.isNotEmpty) {
                    final credentials = WifiQrParser.parse(code);
                    if (credentials != null) {
                      _controller.stop();
                      widget.onScanSuccess(credentials, code);
                    } else {
                      developer.log(
                        'Scanned code is not a valid Wi-Fi configuration: $code',
                        name: 'WifiQrScannerView',
                      );
                      widget.onError('Invalid Wi-Fi QR Code format');
                    }
                  }
                }
              } catch (e, stack) {
                developer.log(
                  'Error parsing QR code',
                  error: e,
                  stackTrace: stack,
                  name: 'WifiQrScannerView',
                );
                widget.onError('Error reading QR code: $e');
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.deepPurple, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Align the Wi-Fi QR Code within the frame to scan',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
