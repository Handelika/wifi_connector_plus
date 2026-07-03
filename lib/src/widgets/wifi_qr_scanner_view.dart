import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/wifi_credentials.dart';
import '../models/wifi_scanner_language.dart';
import '../wifi_qr_parser.dart';

/// A self-contained widget that handles camera permissions, opens the camera stream,
/// scans for a Wi-Fi QR code, and parses it into [WifiCredentials].
/// Configuration option for the camera settings controls overlay.
enum CameraOption {
  /// Display torch and camera flipping controls overlaid on the camera.
  show,

  /// Hide the camera controls overlay.
  hide,
}

/// A self-contained widget that handles camera permissions, opens the camera stream,
/// scans for a Wi-Fi QR code, and parses it into [WifiCredentials].
class WifiQrScannerView extends StatefulWidget {
  /// Callback triggered when a valid Wi-Fi QR code is successfully scanned.
  /// Receives the parsed [WifiCredentials] and the original raw scanned QR string.
  /// If it returns a [Future] that resolves to `false`, or a boolean `false`, the camera scanning will resume.
  final FutureOr<dynamic> Function(WifiCredentials credentials, String rawValue)
  onScanSuccess;

  /// Callback triggered when permission is denied or a scanned QR code cannot be parsed.
  final ValueChanged<String> onError;

  /// Custom widget to display while camera permission is being checked.
  final Widget? placeholder;

  /// Custom widget to display if camera permission is denied.
  final Widget? permissionDeniedPlaceholder;

  /// Option to show or hide camera settings controls (torch and flip camera).
  final CameraOption cameraOption;

  /// Instruction text shown overlaying the bottom portion of the camera feed.
  /// If null or empty, the overlay text container is hidden.
  final String? instructionText;

  /// Language used for warning and error alerts/messages.
  final WifiScannerLanguage language;

  const WifiQrScannerView({
    super.key,
    required this.onScanSuccess,
    required this.onError,
    this.placeholder,
    this.permissionDeniedPlaceholder,
    this.cameraOption = CameraOption.show,
    this.instructionText,
    this.language = WifiScannerLanguage.english,
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

  String get _permissionDeniedErrorText {
    return widget.language == WifiScannerLanguage.turkish
        ? 'Kamera izni reddedildi.'
        : 'Camera permission denied.';
  }

  String _permissionRequestFailedText(Object e) {
    return widget.language == WifiScannerLanguage.turkish
        ? 'Kamera izni talebi başarısız oldu: $e'
        : 'Camera permission request failed: $e';
  }

  String get _permissionRequiredTitle {
    return widget.language == WifiScannerLanguage.turkish
        ? 'QR kodları taramak için kamera izni gereklidir.'
        : 'Camera permission is required to scan QR codes.';
  }

  String get _grantPermissionBtnText {
    return widget.language == WifiScannerLanguage.turkish
        ? 'Kamera İzni Ver'
        : 'Grant Camera Permission';
  }

  String get _invalidQrErrorText {
    return widget.language == WifiScannerLanguage.turkish
        ? 'Geçersiz Wi-Fi QR Kodu formatı'
        : 'Invalid Wi-Fi QR Code format';
  }

  String _errorReadingQrText(Object e) {
    return widget.language == WifiScannerLanguage.turkish
        ? 'QR kodu okunurken hata oluştu: $e'
        : 'Error reading QR code: $e';
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
          widget.onError(_permissionDeniedErrorText);
        }
      }
    } catch (e, stack) {
      developer.log(
        'Exception while checking camera permission',
        error: e,
        stackTrace: stack,
        name: 'WifiQrScannerView',
      );
      widget.onError(_permissionRequestFailedText(e));
      setState(() {
        _isChecking = false;
      });
    }
  }

  Widget _buildSettingsButton({
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: icon,
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return widget.placeholder ??
          const Center(child: CircularProgressIndicator());
    }

    if (!_hasPermission) {
      return widget.permissionDeniedPlaceholder ??
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.camera_alt_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _permissionRequiredTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _checkPermission,
                    child: Text(_grantPermissionBtnText),
                  ),
                ],
              ),
            ),
          );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double size = (constraints.maxWidth * 0.7).clamp(150.0, 250.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: (capture) {
                  try {
                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final barcode = barcodes.first;
                      WifiCredentials? credentials;

                      // 1. Try accessing structured wifi properties parsed by mobile_scanner
                      if (barcode.type == BarcodeType.wifi &&
                          barcode.wifi != null) {
                        final wifi = barcode.wifi!;
                        final ssid = wifi.ssid;
                        if (ssid != null && ssid.isNotEmpty) {
                          WifiSecurityType secType = WifiSecurityType.none;
                          if (wifi.encryptionType == EncryptionType.wpa) {
                            secType = WifiSecurityType.wpa;
                          } else if (wifi.encryptionType ==
                              EncryptionType.wep) {
                            secType = WifiSecurityType.wep;
                          }

                          // Default to WPA if password is set but encryptionType is unknown/open
                          if (secType == WifiSecurityType.none &&
                              wifi.password != null &&
                              wifi.password!.isNotEmpty) {
                            secType = WifiSecurityType.wpa;
                          }

                          credentials = WifiCredentials(
                            ssid: WifiQrParser.cleanValue(ssid),
                            password: wifi.password != null
                                ? WifiQrParser.cleanValue(wifi.password!)
                                : null,
                            securityType: secType,
                            isHidden:
                                false, // mobile_scanner does not expose hidden SSID status, fallback to false
                          );
                        }
                      }

                      // 2. Fallback to raw string parsing if structured data isn't available or failed
                      if (credentials == null) {
                        final code = barcode.rawValue;
                        if (code != null && code.isNotEmpty) {
                          credentials = WifiQrParser.parse(code);
                        }
                      }

                      if (credentials != null) {
                        _controller.stop();
                        final result = widget.onScanSuccess(
                          credentials,
                          barcode.rawValue ?? '',
                        );
                        if (result is Future) {
                          result.then((res) {
                            if (mounted && res == false) {
                              _controller.start();
                            }
                          });
                        } else if (result == false) {
                          if (mounted) {
                            _controller.start();
                          }
                        }
                      } else {
                        developer.log(
                          'Scanned code is not a valid Wi-Fi configuration: ${barcode.rawValue}',
                          name: 'WifiQrScannerView',
                        );
                        widget.onError(_invalidQrErrorText);
                      }
                    }
                  } catch (e, stack) {
                    developer.log(
                      'Error parsing QR code',
                      error: e,
                      stackTrace: stack,
                      name: 'WifiQrScannerView',
                    );
                    widget.onError(_errorReadingQrText(e));
                  }
                },
              ),
              Center(
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.deepPurple, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (widget.instructionText != null &&
                  widget.instructionText!.isNotEmpty)
                Positioned(
                  bottom: 20,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.instructionText!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              if (widget.cameraOption == CameraOption.show)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSettingsButton(
                        icon: ValueListenableBuilder<MobileScannerState>(
                          valueListenable: _controller,
                          builder: (context, state, child) {
                            switch (state.torchState) {
                              case TorchState.off:
                                return const Icon(
                                  Icons.flash_off,
                                  color: Colors.white,
                                  size: 20,
                                );
                              case TorchState.on:
                                return const Icon(
                                  Icons.flash_on,
                                  color: Colors.yellow,
                                  size: 20,
                                );
                              case TorchState.unavailable:
                              case TorchState.auto:
                                return const Icon(
                                  Icons.flash_off,
                                  color: Colors.white30,
                                  size: 20,
                                );
                            }
                          },
                        ),
                        onPressed: () => _controller.toggleTorch(),
                      ),
                      const SizedBox(width: 8),
                      _buildSettingsButton(
                        icon: ValueListenableBuilder<MobileScannerState>(
                          valueListenable: _controller,
                          builder: (context, state, child) {
                            switch (state.cameraDirection) {
                              case CameraFacing.front:
                                return const Icon(
                                  Icons.camera_front,
                                  color: Colors.white,
                                  size: 20,
                                );
                              case CameraFacing.back:
                                return const Icon(
                                  Icons.camera_rear,
                                  color: Colors.white,
                                  size: 20,
                                );
                              case CameraFacing.external:
                              case CameraFacing.unknown:
                                return const Icon(
                                  Icons.camera,
                                  color: Colors.white,
                                  size: 20,
                                );
                            }
                          },
                        ),
                        onPressed: () => _controller.switchCamera(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
