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
                val suggestionBuilder = WifiNetworkSuggestion.Builder()
                    .setIsHiddenSsid(isHidden)

                if ((securityType == "WPA" || securityType == "WPA2") && !password.isNullOrEmpty()) {
                    suggestionBuilder.setSsid(ssid)
                    suggestionBuilder.setWpa2Passphrase(password)
                } else if (securityType == "WPA3" && !password.isNullOrEmpty()) {
                    suggestionBuilder.setSsid(ssid)
                    suggestionBuilder.setWpa3Passphrase(password)
                } else if (securityType == "WEP" && !password.isNullOrEmpty()) {
                    suggestionBuilder.setSsid(ssid)
                    suggestionBuilder.setWpa2Passphrase(password)
                } else {
                    suggestionBuilder.setSsid(ssid)
                }

                val suggestion = suggestionBuilder.build()
                val suggestions = listOf(suggestion)

                // Remove existing suggestions for this SSID to avoid conflicts
                wifiManager.removeNetworkSuggestions(suggestions)

                val status = wifiManager.addNetworkSuggestions(suggestions)
                if (status != WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) {
                    result.success(false)
                    return
                }

                // Check if already connected
                @Suppress("DEPRECATION")
                val currentWifiInfo = wifiManager.connectionInfo
                val currentSsid = currentWifiInfo?.ssid?.replace("\"", "")
                if (currentSsid == ssid) {
                    result.success(true)
                    return
                }

                val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val networkRequest = NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .build()

                val handler = android.os.Handler(android.os.Looper.getMainLooper())
                var callbackRegistered = true
                var hasReplied = false

                val networkCallback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        super.onAvailable(network)
                        checkConnection()
                    }

                    override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                        super.onCapabilitiesChanged(network, networkCapabilities)
                        checkConnection(networkCapabilities)
                    }

                    private fun checkConnection(networkCapabilities: NetworkCapabilities? = null) {
                        val wifiInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && networkCapabilities != null) {
                            networkCapabilities.transportInfo as? android.net.wifi.WifiInfo
                        } else {
                            null
                        }
                        @Suppress("DEPRECATION")
                        val connectedSsid = (wifiInfo?.ssid ?: wifiManager.connectionInfo?.ssid)?.replace("\"", "")
                        if (connectedSsid == ssid) {
                            handler.post {
                                if (!hasReplied) {
                                    hasReplied = true
                                    if (callbackRegistered) {
                                        try {
                                            connectivityManager.unregisterNetworkCallback(this)
                                        } catch (e: Exception) {}
                                        callbackRegistered = false
                                    }
                                    result.success(true)
                                }
                            }
                        }
                    }
                }

                val timeoutRunnable = Runnable {
                    if (!hasReplied) {
                        hasReplied = true
                        if (callbackRegistered) {
                            try {
                                connectivityManager.unregisterNetworkCallback(networkCallback)
                            } catch (e: Exception) {}
                            callbackRegistered = false
                        }
                        @Suppress("DEPRECATION")
                        val finalWifiInfo = wifiManager.connectionInfo
                        val finalSsid = finalWifiInfo?.ssid?.replace("\"", "")
                        if (finalSsid == ssid) {
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                }

                connectivityManager.registerNetworkCallback(networkRequest, networkCallback)
                handler.postDelayed(timeoutRunnable, 15000) // 15 seconds timeout
            } catch (e: Exception) {
                result.success(false)
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
