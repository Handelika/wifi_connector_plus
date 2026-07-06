import Flutter
import UIKit
import NetworkExtension
import Network
import SystemConfiguration.CaptiveNetwork

public class WifiConnectorPlusPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  // MARK: - SSID Stream

  private var eventSink: FlutterEventSink?
  private var pathMonitor: NWPathMonitor?
  private let streamQueue = DispatchQueue(label: "com.handelika.wifi_connector_plus.stream", qos: .utility)

  // MARK: - Registration

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: "wifi_connector_plus",
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: "wifi_connector_plus/ssid_stream",
      binaryMessenger: registrar.messenger()
    )
    let instance = WifiConnectorPlusPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  // MARK: - FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    startSsidMonitor()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopSsidMonitor()
    eventSink = nil
    return nil
  }

  private func startSsidMonitor() {
    stopSsidMonitor()
    let monitor = NWPathMonitor()
    pathMonitor = monitor
    monitor.pathUpdateHandler = { [weak self] _ in
      self?.emitCurrentSsid()
    }
    monitor.start(queue: streamQueue)
    // Emit immediately on subscribe
    emitCurrentSsid()
  }

  private func stopSsidMonitor() {
    pathMonitor?.cancel()
    pathMonitor = nil
  }

  private func emitCurrentSsid() {
    fetchCurrentSsid { [weak self] ssid in
      DispatchQueue.main.async {
        self?.eventSink?(ssid)
      }
    }
  }

  // MARK: - Method Handler

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "connect":
      guard let args = call.arguments as? [String: Any],
            let ssid = args["ssid"] as? String else {
        result(false)
        return
      }
      let password = args["password"] as? String
      let securityType = (args["securityType"] as? String ?? "WPA").uppercased()
      let isHidden = args["isHidden"] as? Bool ?? false
      connectToWifi(ssid: ssid, password: password, securityType: securityType, isHidden: isHidden, result: result)
    case "getCurrentSsid":
      fetchCurrentSsid { ssid in result(ssid) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Fetch Current SSID

  /// Fetches the current connected Wi-Fi SSID.
  /// Requires com.apple.developer.networking.wifi-info entitlement on iOS 14+.
  private func fetchCurrentSsid(completion: @escaping (String?) -> Void) {
    if #available(iOS 14.0, *) {
      NEHotspotNetwork.fetchCurrent { network in
        completion(network?.ssid)
      }
    } else {
      #if targetEnvironment(simulator)
      completion(nil)
      #else
      var ssid: String? = nil
      if let interfaces = CNCopySupportedInterfaces() as? [String] {
        for interface in interfaces {
          if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: AnyObject] {
            ssid = info[kCNNetworkInfoKeySSID as String] as? String
            break
          }
        }
      }
      completion(ssid)
      #endif
    }
  }

  // MARK: - Connect to Wi-Fi

  private func connectToWifi(
    ssid: String,
    password: String?,
    securityType: String,
    isHidden: Bool,
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 11.0, *) else {
      result(FlutterError(code: "UNSUPPORTED", message: "iOS 11.0 or later is required", details: nil))
      return
    }

    let configuration: NEHotspotConfiguration
    if (securityType == "WPA" || securityType == "WPA2" || securityType == "WPA3") && password != nil {
      configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password!, isWEP: false)
    } else if securityType == "WEP" && password != nil {
      configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password!, isWEP: true)
    } else {
      configuration = NEHotspotConfiguration(ssid: ssid)
    }
    configuration.joinOnce = false

    // apply() is the connection request to iOS.
    // It does NOT guarantee connection — it only submits the configuration.
    // We must verify the actual SSID after apply() succeeds.
    NEHotspotConfigurationManager.shared.apply(configuration) { [weak self] error in
      guard let self = self else { return }

      if let error = error {
        let nsError = error as NSError
        if nsError.domain == NEHotspotConfigurationErrorDomain && nsError.code == 13 {
          // Already associated with this SSID — verify to be sure
          self.verifyConnection(ssid: ssid, isAlreadyConnected: true, attempt: 0, result: result)
        } else {
          print("[WifiConnectorPlus] apply error: \(nsError.domain) code=\(nsError.code) — \(nsError.localizedDescription)")
          DispatchQueue.main.async {
            result(FlutterError(
              code: "WIFI_ERROR",
              message: nsError.localizedDescription,
              details: "domain=\(nsError.domain) code=\(nsError.code)"
            ))
          }
        }
      } else {
        // apply succeeded → now confirm we're actually on the network
        self.verifyConnection(ssid: ssid, isAlreadyConnected: false, attempt: 0, result: result)
      }
    }
  }

  // MARK: - Verify Connection

  /// Polls fetchCurrentSsid until the connected SSID matches the expected one.
  /// Max 20 attempts × 500 ms = 10 seconds.
  private func verifyConnection(ssid: String, isAlreadyConnected: Bool, attempt: Int, result: @escaping FlutterResult) {
    let maxAttempts = 20
    let intervalMs = 500

    fetchCurrentSsid { [weak self] currentSsid in
      guard let self = self else { return }

      if currentSsid == ssid {
        DispatchQueue.main.async {
          result(isAlreadyConnected ? "ALREADY_CONNECTED" : true)
        }
      } else if attempt < maxAttempts {
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(intervalMs)) {
          self.verifyConnection(ssid: ssid, isAlreadyConnected: isAlreadyConnected, attempt: attempt + 1, result: result)
        }
      } else {
        // 10 seconds passed without SSID match → real failure
        DispatchQueue.main.async {
          result(FlutterError(
            code: "CONNECTION_TIMEOUT",
            message: "Connected configuration was accepted but '\(ssid)' could not be verified as the active network. The network may be out of range or the password is incorrect.",
            details: nil
          ))
        }
      }
    }
  }
}
