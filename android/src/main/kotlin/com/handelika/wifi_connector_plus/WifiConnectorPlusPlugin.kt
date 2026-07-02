package com.handelika.wifi_connector_plus

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** WifiConnectorPlusPlugin */
class WifiConnectorPlusPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "wifi_connector_plus")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${Build.VERSION.RELEASE}")
            }
            "connect" -> {
                val ssid = call.argument<String>("ssid") ?: ""
                val password = call.argument<String>("password")
                val securityType = call.argument<String>("securityType") ?: "WPA"
                val isHidden = call.argument<Boolean>("isHidden") ?: false

                connectToWifi(ssid, password, securityType, isHidden, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun connectToWifi(
        ssid: String,
        password: String?,
        securityType: String,
        isHidden: Boolean,
        result: Result
    ) {
        val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val specifierBuilder = WifiNetworkSpecifier.Builder()
                    .setIsHiddenSsid(isHidden)

                if ((securityType == "WPA" || securityType == "WPA2") && !password.isNullOrEmpty()) {
                    specifierBuilder.setSsid(ssid)
                    specifierBuilder.setWpa2Passphrase(password)
                } else if (securityType == "WPA3" && !password.isNullOrEmpty()) {
                    specifierBuilder.setSsid(ssid)
                    specifierBuilder.setWpa3Passphrase(password)
                } else if (securityType == "WEP" && !password.isNullOrEmpty()) {
                    specifierBuilder.setSsid(ssid)
                    specifierBuilder.setWpa2Passphrase(password)
                } else {
                    specifierBuilder.setSsid(ssid)
                }

                val specifier = specifierBuilder.build()
                val request = NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .setNetworkSpecifier(specifier)
                    .build()

                val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

                connectivityManager.requestNetwork(request, object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        super.onAvailable(network)
                        connectivityManager.bindProcessToNetwork(network)
                        result.success(true)
                    }

                    override fun onUnavailable() {
                        super.onUnavailable()
                        result.success(false)
                    }
                })
            } catch (e: Exception) {
                // Fallback to Suggestion API if requestNetwork throws
                try {
                    val suggestionBuilder = WifiNetworkSuggestion.Builder()
                        .setIsHiddenSsid(isHidden)

                    if ((securityType == "WPA" || securityType == "WPA2") && !password.isNullOrEmpty()) {
                        suggestionBuilder.setSsid(ssid)
                        suggestionBuilder.setWpa2Passphrase(password)
                    } else if (securityType == "WPA3" && !password.isNullOrEmpty()) {
                        suggestionBuilder.setSsid(ssid)
                        suggestionBuilder.setWpa3Passphrase(password)
                    } else {
                        suggestionBuilder.setSsid(ssid)
                    }

                    val suggestions = listOf(suggestionBuilder.build())
                    val status = wifiManager.addNetworkSuggestions(suggestions)
                    if (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) {
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } catch (ex: Exception) {
                    result.success(false)
                }
            }
        } else {
            // Older Android versions
            try {
                @Suppress("DEPRECATION")
                val wifiConfig = WifiConfiguration().apply {
                    SSID = "\"$ssid\""
                    if ((securityType == "WPA" || securityType == "WPA2" || securityType == "WPA3") && !password.isNullOrEmpty()) {
                        preSharedKey = "\"$password\""
                    } else if (securityType == "WEP" && !password.isNullOrEmpty()) {
                        wepKeys[0] = "\"$password\""
                        wepTxKeyIndex = 0
                        allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                        allowedAuthAlgorithms.set(WifiConfiguration.AuthAlgorithm.SHARED)
                    } else {
                        allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                    }
                }

                @Suppress("DEPRECATION")
                val netId = wifiManager.addNetwork(wifiConfig)
                if (netId != -1) {
                    @Suppress("DEPRECATION")
                    wifiManager.disconnect()
                    @Suppress("DEPRECATION")
                    val enabled = wifiManager.enableNetwork(netId, true)
                    @Suppress("DEPRECATION")
                    wifiManager.reconnect()
                    result.success(enabled)
                } else {
                    result.success(false)
                }
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
