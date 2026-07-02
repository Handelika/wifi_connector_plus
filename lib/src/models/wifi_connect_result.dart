enum WifiConnectError {
  invalidCredentials,
  permissionDenied,
  userCancelled,
  timeout,
  unknown,
  notSupported,
}

class WifiConnectResult {
  final bool isSuccess;
  final String message;
  final WifiConnectError? error;

  const WifiConnectResult({
    required this.isSuccess,
    required this.message,
    this.error,
  });

  factory WifiConnectResult.success({
    String message = 'Connected successfully',
  }) {
    return WifiConnectResult(isSuccess: true, message: message);
  }

  factory WifiConnectResult.failure({
    required String message,
    required WifiConnectError error,
  }) {
    return WifiConnectResult(isSuccess: false, message: message, error: error);
  }

  @override
  String toString() {
    return 'WifiConnectResult(isSuccess: $isSuccess, message: $message, error: ${error?.name})';
  }
}
