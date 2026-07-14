import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// A controller to manage camera operations for [WifiQrScannerView].
class WifiQrScannerController extends ChangeNotifier {
  MobileScannerController? _scannerController;
  bool _isDisposed = false;

  VoidCallback? _onResetProcessing;

  /// Internal method to bind the underlying [MobileScannerController].
  void bind(
    MobileScannerController scannerController, {
    VoidCallback? onResetProcessing,
  }) {
    _scannerController = scannerController;
    _onResetProcessing = onResetProcessing;
  }

  /// Internal method to unbind.
  void unbind() {
    _scannerController = null;
    _onResetProcessing = null;
  }

  /// Starts the camera scanning.
  Future<void> start() async {
    if (_isDisposed) return;
    _onResetProcessing?.call();
    await _scannerController?.start();
  }

  /// Stops the camera scanning.
  Future<void> stop() async {
    if (_isDisposed) return;
    await _scannerController?.stop();
  }

  /// Resumes the camera scanning.
  /// (Alias or helper to restart the scanner)
  Future<void> resume() async {
    if (_isDisposed) return;
    _onResetProcessing?.call();
    await _scannerController?.start();
  }

  /// Resets the processing state to allow scanning another QR code.
  void resetProcessing() {
    if (_isDisposed) return;
    _onResetProcessing?.call();
  }

  /// Controls the flash state of the camera.
  ///
  /// - Pass `true` to turn the torch on.
  /// - Pass `false` to turn the torch off.
  /// - Pass `null` to toggle the current torch state.
  Future<void> flash([bool? state]) async {
    if (_isDisposed || _scannerController == null) return;
    if (state == null) {
      await _scannerController!.toggleTorch();
    } else {
      final torchState = _scannerController!.value.torchState;
      if (state && torchState != TorchState.on) {
        await _scannerController!.toggleTorch();
      } else if (!state && torchState == TorchState.on) {
        await _scannerController!.toggleTorch();
      }
    }
    notifyListeners();
  }

  /// Gets the current camera facing direction.
  CameraFacing? get cameraFace => _scannerController?.facing;

  /// Sets the camera facing direction.
  set cameraFace(CameraFacing? face) {
    if (_isDisposed || _scannerController == null || face == null) return;
    if (_scannerController!.facing != face) {
      _scannerController!.switchCamera();
      notifyListeners();
    }
  }

  /// Switches the camera between front and back.
  Future<void> switchCamera() async {
    if (_isDisposed || _scannerController == null) return;
    await _scannerController!.switchCamera();
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scannerController = null;
    super.dispose();
  }
}
