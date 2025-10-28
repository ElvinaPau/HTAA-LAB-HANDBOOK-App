import 'dart:io';

String getBaseUrl() {
  if (Platform.isAndroid) {
    return "http://10.0.2.2:5001"; // Android emulator
  } else {
    return "http://localhost:5001"; // iOS simulator or web
  }
}