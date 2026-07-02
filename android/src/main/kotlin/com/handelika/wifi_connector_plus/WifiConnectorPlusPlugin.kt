package com.handelika.wifi_connector_plus

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener

private const val REQUEST_CODE_WIFI_ADD = 1001

/** WifiConnectorPlusPlugin */
class WifiConnectorPlusPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    // Pending state for Android 10+ system-wide connection flow
    private var pendingResult: Result? = null
    private var pendingSsid: String? = null
    private var pendingPassword: String? = null
    private var pendingSecurityType: String? = null

    // ─── FlutterPlugin ───────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "wifi_connector_plus")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ─── ActivityAware ───────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activity = null
        activityBinding = null
    }

    // ─── ActivityResultListener ──────────────────────────────────────────────

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_WIFI_ADD) return false

        val result = pendingResult ?: return true
        val ssid = pendingSsid ?: return true

        pendingResult = null

        if (resultCode == Activity.RESULT_OK) {
            // Kullanıcı onayladı — sistem ağa bağlanmaya başlayacak.
            // Bağlantı gerçekleşene kadar izleyip cevap ver.
            awaitSystemConnection(ssid, result)
        } else {
            // Kullanıcı dialog'u kapattı veya iptal etti.
            result.error(
                "USER_CANCELLED",
                "User cancelled the Wi-Fi connection request.",
                null
            )
        }
        pendingSsid = null
        pendingPassword = null
        pendingSecurityType = null
        return true
    }

    // ─── MethodCallHandler ───────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "connect" -> {
                val ssid = call.argument<String>("ssid") ?: ""
                val password = call.argument<String>("password")
                val securityType = (call.argument<String>("securityType") ?: "WPA").uppercase()
                val isHidden = call.argument<Boolean>("isHidden") ?: false
                connectToWifi(ssid, password, securityType, isHidden, result)
            }
            else -> result.notImplemented()
        }
    }

    // ─── Core Logic ──────────────────────────────────────────────────────────

    private fun connectToWifi(
        ssid: String,
        password: String?,
        securityType: String,
        isHidden: Boolean,
        result: Result
    ) {
        if (ssid.isEmpty()) {
            result.error("INVALID_CREDENTIALS", "SSID cannot be empty.", null)
            return
        }

        val isSecured = securityType == "WPA" || securityType == "WPA2" ||
                securityType == "WPA3" || securityType == "WEP"
        if (isSecured && password.isNullOrEmpty()) {
            result.error(
                "INVALID_CREDENTIALS",
                "Password is required for security type: $securityType",
                null
            )
            return
        }

        val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifiManager.isWifiEnabled) {
            result.error("WIFI_DISABLED", "Wi-Fi is disabled. Please enable it first.", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ — sistem dialog ile sistem-çapı bağlantı
            connectSystemWide(ssid, password, securityType, isHidden, result)
        } else {
            // Android 9 altı — legacy WifiConfiguration
            connectLegacy(wifiManager, ssid, password, securityType, isHidden, result)
        }
    }

    /**
     * Android 10+ (API 29+):
     * ACTION_WIFI_ADD_NETWORKS intent ile sistem dialog gösterir.
     * Kullanıcı onayladığında sistem ağı kaydeder ve bağlanır (sistem-çapı).
     */
    private fun connectSystemWide(
        ssid: String,
        password: String?,
        securityType: String,
        isHidden: Boolean,
        result: Result
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return

        val currentActivity = activity
        if (currentActivity == null) {
            // Activity yoksa WifiNetworkSuggestion fallback
            connectWithSuggestion(ssid, password, securityType, isHidden, result)
            return
        }

        // Önce zaten bu ağa bağlı mı kontrol et
        val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        val currentSsid = wifiManager.connectionInfo?.ssid?.replace("\"", "")
        if (currentSsid == ssid) {
            result.success(true)
            return
        }

        try {
            val suggestionBuilder = WifiNetworkSuggestion.Builder()
                .setSsid(ssid)
                .setIsHiddenSsid(isHidden)

            when {
                (securityType == "WPA" || securityType == "WPA2") && !password.isNullOrEmpty() ->
                    suggestionBuilder.setWpa2Passphrase(password)
                securityType == "WPA3" && !password.isNullOrEmpty() ->
                    suggestionBuilder.setWpa3Passphrase(password)
                securityType == "WEP" && !password.isNullOrEmpty() ->
                    // Android 10+ WEP desteği kaldırıldı, WPA2 olarak dene
                    suggestionBuilder.setWpa2Passphrase(password)
                // Open ağ — sadece SSID
            }

            val suggestion = suggestionBuilder.build()
            val bundle = android.os.Bundle().apply {
                putParcelableArrayList(
                    Settings.EXTRA_WIFI_NETWORK_LIST,
                    arrayListOf(suggestion)
                )
            }
            val intent = Intent(Settings.ACTION_WIFI_ADD_NETWORKS).putExtras(bundle)

            // Sonucu bekle
            pendingResult = result
            pendingSsid = ssid
            pendingPassword = password
            pendingSecurityType = securityType

            currentActivity.startActivityForResult(intent, REQUEST_CODE_WIFI_ADD)

        } catch (e: Exception) {
            pendingResult = null
            pendingSsid = null
            result.error("CONNECTION_ERROR", "Error launching Wi-Fi dialog: ${e.localizedMessage}", null)
        }
    }

    /**
     * Kullanıcı sistem dialog'unu onayladıktan sonra,
     * sistem ağa bağlanana kadar izler (max 30 saniye).
     */
    private fun awaitSystemConnection(ssid: String, result: Result) {
        val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val handler = Handler(Looper.getMainLooper())

        var hasReplied = false
        var networkCallback: ConnectivityManager.NetworkCallback? = null

        val timeoutRunnable = Runnable {
            if (!hasReplied) {
                hasReplied = true
                networkCallback?.let {
                    try { connectivityManager.unregisterNetworkCallback(it) } catch (_: Exception) {}
                }
                // Timeout'ta son bir kontrol — belki bağlandı ama callback gelmedi
                @Suppress("DEPRECATION")
                val finalSsid = wifiManager.connectionInfo?.ssid?.replace("\"", "")
                if (finalSsid == ssid) {
                    result.success(true)
                } else {
                    result.error(
                        "CONNECTION_TIMEOUT",
                        "Connection to '$ssid' timed out after approval. The network may be out of range.",
                        null
                    )
                }
            }
        }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities
            ) {
                val wifiInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    networkCapabilities.transportInfo as? android.net.wifi.WifiInfo
                } else null

                @Suppress("DEPRECATION")
                val connectedSsid = (wifiInfo?.ssid ?: wifiManager.connectionInfo?.ssid)
                    ?.replace("\"", "")

                if (connectedSsid == ssid) {
                    handler.post {
                        if (!hasReplied) {
                            hasReplied = true
                            handler.removeCallbacks(timeoutRunnable)
                            try { connectivityManager.unregisterNetworkCallback(this) } catch (_: Exception) {}
                            result.success(true)
                        }
                    }
                }
            }

            override fun onAvailable(network: Network) {
                // onCapabilitiesChanged ile de yakalanır ama erken çıkmak için kontrol et
                @Suppress("DEPRECATION")
                val connectedSsid = wifiManager.connectionInfo?.ssid?.replace("\"", "")
                if (connectedSsid == ssid) {
                    handler.post {
                        if (!hasReplied) {
                            hasReplied = true
                            handler.removeCallbacks(timeoutRunnable)
                            try { connectivityManager.unregisterNetworkCallback(this) } catch (_: Exception) {}
                            result.success(true)
                        }
                    }
                }
            }
        }

        networkCallback = callback
        val networkRequest = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()

        connectivityManager.registerNetworkCallback(networkRequest, callback)
        handler.postDelayed(timeoutRunnable, 30_000)
    }

    /**
     * Fallback: Activity yoksa WifiNetworkSuggestion kullan.
     * Sistem bağlantıyı arka planda kurar (kullanıcı onayı notification ile).
     */
    private fun connectWithSuggestion(
        ssid: String,
        password: String?,
        securityType: String,
        isHidden: Boolean,
        result: Result
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return

        val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as WifiManager

        try {
            val suggestionBuilder = WifiNetworkSuggestion.Builder()
                .setSsid(ssid)
                .setIsHiddenSsid(isHidden)

            when {
                (securityType == "WPA" || securityType == "WPA2") && !password.isNullOrEmpty() ->
                    suggestionBuilder.setWpa2Passphrase(password)
                securityType == "WPA3" && !password.isNullOrEmpty() ->
                    suggestionBuilder.setWpa3Passphrase(password)
                securityType == "WEP" && !password.isNullOrEmpty() ->
                    suggestionBuilder.setWpa2Passphrase(password)
            }

            val suggestion = suggestionBuilder.build()
            wifiManager.removeNetworkSuggestions(listOf(suggestion))
            val status = wifiManager.addNetworkSuggestions(listOf(suggestion))

            if (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) {
                result.success(true)
            } else {
                result.error("SUGGESTION_FAILED", "Failed to add Wi-Fi suggestion: error $status", null)
            }
        } catch (e: Exception) {
            result.error("CONNECTION_ERROR", "Error: ${e.localizedMessage}", null)
        }
    }

    /**
     * Android 9 ve altı (API < 29): WifiConfiguration (deprecated legacy API).
     */
    @Suppress("DEPRECATION")
    private fun connectLegacy(
        wifiManager: WifiManager,
        ssid: String,
        password: String?,
        securityType: String,
        isHidden: Boolean,
        result: Result
    ) {
        try {
            // Mevcut aynı SSID'yi temizle
            wifiManager.configuredNetworks?.forEach { cfg ->
                if (cfg.SSID == "\"$ssid\"") {
                    wifiManager.removeNetwork(cfg.networkId)
                }
            }

            val wifiConfig = WifiConfiguration().apply {
                SSID = "\"$ssid\""
                hiddenSSID = isHidden
                when {
                    (securityType == "WPA" || securityType == "WPA2" || securityType == "WPA3")
                            && !password.isNullOrEmpty() -> {
                        preSharedKey = "\"$password\""
                    }
                    securityType == "WEP" && !password.isNullOrEmpty() -> {
                        wepKeys[0] = "\"$password\""
                        wepTxKeyIndex = 0
                        allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                        allowedAuthAlgorithms.set(WifiConfiguration.AuthAlgorithm.SHARED)
                    }
                    else -> allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                }
            }

            val netId = wifiManager.addNetwork(wifiConfig)
            if (netId == -1) {
                result.error(
                    "CONFIGURATION_FAILED",
                    "Failed to add network configuration. Check SSID/Password.",
                    null
                )
                return
            }

            wifiManager.disconnect()
            val enabled = wifiManager.enableNetwork(netId, true)
            wifiManager.reconnect()

            if (!enabled) {
                result.error("CONNECTION_FAILED", "Failed to enable network.", null)
                return
            }

            // Bağlantıyı polling ile doğrula
            val handler = Handler(Looper.getMainLooper())
            var hasReplied = false

            val checkRunnable = object : Runnable {
                var attempts = 0
                override fun run() {
                    val currentSsid = wifiManager.connectionInfo?.ssid?.replace("\"", "")
                    when {
                        currentSsid == ssid -> {
                            if (!hasReplied) {
                                hasReplied = true
                                result.success(true)
                            }
                        }
                        attempts < 20 -> { // max 10 saniye (500ms x 20)
                            attempts++
                            handler.postDelayed(this, 500)
                        }
                        else -> {
                            if (!hasReplied) {
                                hasReplied = true
                                result.error(
                                    "CONNECTION_TIMEOUT",
                                    "Connection to '$ssid' timed out. Check credentials.",
                                    null
                                )
                            }
                        }
                    }
                }
            }
            handler.postDelayed(checkRunnable, 500)

        } catch (e: Exception) {
            result.error("CONNECTION_ERROR", "Error: ${e.localizedMessage}", null)
        }
    }
}
