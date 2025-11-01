import 'dart:io';
import 'package:flutter/foundation.dart'; // Add this import

String getBaseUrl() {
  // For web (running in browser)
  if (kIsWeb) {
    return "http://localhost:5001";
  }

  // For Android emulator
  if (Platform.isAndroid) {
    return "http://10.0.2.2:5001";
  }

  // For iOS
  if (Platform.isIOS) {
    // Check if running on simulator or physical device
    // Simulators can use localhost, physical devices need IP
    if (Platform.environment.containsKey('SIMULATOR_DEVICE_NAME')) {
      return "http://localhost:5001"; // iOS Simulator
    } else {
      return "http://10.167.177.31:5001"; // Physical iPhone - YOUR IP
    }
  }

  // For desktop (Mac, Windows, Linux)
  return "http://localhost:5001";
}
