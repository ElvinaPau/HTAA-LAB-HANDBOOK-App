import 'dart:io';

String getBaseUrl() {
  if (Platform.isAndroid) {
    return "http://10.0.2.2:4000"; // Android emulator
  } else {
    return "http://localhost:4000"; // iOS simulator or web
  }
}