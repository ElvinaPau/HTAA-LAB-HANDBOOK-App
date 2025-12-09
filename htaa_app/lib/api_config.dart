import 'dart:io';
import 'package:flutter/foundation.dart';

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
      return "http://10.128.66.115:5001"; // Replace with your Mac's IP
    }
  }

  // For desktop (Mac, Windows, Linux)
  return "http://localhost:5001";
}
