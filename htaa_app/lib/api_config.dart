import 'dart:io';
import 'package:flutter/foundation.dart';

String getBaseUrl() {
  const String productionUrl = "https://pathology-admin-dashboard-v2.onrender.com";

  // Always use production Render URL (even in debug mode)
  return productionUrl;

  // Uncomment below for local development
  /*
  // If running in RELEASE build on mobile → use production backend
  if (kReleaseMode) {
    return productionUrl;
  }

  // For web (running in browser)
  if (kIsWeb) {
    return "http://localhost:5001";
  }

  // For Android emulator (debug mode)
  if (Platform.isAndroid) {
    return "http://10.0.2.2:5001";
  }

  // For iOS
  if (Platform.isIOS) {
    // Simulator vs physical device
    if (Platform.environment.containsKey('SIMULATOR_DEVICE_NAME')) {
      return "http://localhost:5001"; 
    } else {
      return "http://192.168.1.244:5001"; // Your Mac IP (debug only)
    }
  }

  // Desktop (debug only)
  return "http://localhost:5001";
  */
}

/// Get timeout duration based on environment
Duration getTimeout() {
  final baseUrl = getBaseUrl();
  final isProduction = baseUrl.contains('render.com');
  
  // Render can be slow on cold starts (up to 60-90 seconds)
  return isProduction 
      ? const Duration(seconds: 90) 
      : const Duration(seconds: 10);
}