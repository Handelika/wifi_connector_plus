import Flutter
import UIKit
import NetworkExtension

public class WifiConnectorPlusPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "wifi_connector_plus", binaryMessenger: registrar.messenger())
    let instance = WifiConnectorPlusPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

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
      let securityType = args["securityType"] as? String ?? "WPA"
      let isHidden = args["isHidden"] as? Bool ?? false
      
      connectToWifi(ssid: ssid, password: password, securityType: securityType, isHidden: isHidden, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func connectToWifi(ssid: String, password: String?, securityType: String, isHidden: Bool, result: @escaping FlutterResult) {
    if #available(iOS 11.0, *) {
      let configuration: NEHotspotConfiguration
      
      if (securityType == "WPA" || securityType == "WPA2" || securityType == "WPA3") && password != nil {
        configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password!, isWEP: false)
      } else if securityType == "WEP" && password != nil {
        configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password!, isWEP: true)
      } else {
        configuration = NEHotspotConfiguration(ssid: ssid)
      }
      
      configuration.joinOnce = false
      
      NEHotspotConfigurationManager.shared.apply(configuration) { error in
        if let error = error {
          let nsError = error as NSError
          // NEHotspotConfigurationErrorAlreadyAssociated (code 13) means already connected — treat as success
          if nsError.domain == NEHotspotConfigurationErrorDomain && nsError.code == 13 {
            result(true)
          } else {
            // Log the detailed error for debugging
            print("[WifiConnectorPlus] NEHotspot error: \(nsError.domain) code=\(nsError.code) — \(nsError.localizedDescription)")
            result(FlutterError(
              code: "WIFI_ERROR",
              message: nsError.localizedDescription,
              details: "domain=\(nsError.domain) code=\(nsError.code)"
            ))
          }
        } else {
          result(true)
        }
      }
    } else {
      result(FlutterError(code: "UNSUPPORTED", message: "iOS 11.0 or later is required", details: nil))
    }
  }
}
