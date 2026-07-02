# Keep rules for Google ML Kit Barcode Scanning
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }

# Keep rules for Google Play Services ML Kit components
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_code_scanner.** { *; }

# Keep rules for mobile_scanner package
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep interface dev.steenbakker.mobile_scanner.** { *; }
