import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService._privateConstructor() {
    // Listen to system connectivity changes and forward to our stream
    _subscription = Connectivity().onConnectivityChanged.listen((result) {
      _connectivityController.add(result);
      _lastStatus = result;
    });
  }

  static final ConnectivityService _instance =
      ConnectivityService._privateConstructor();

  factory ConnectivityService() => _instance;

  final _connectivityController =
      StreamController<ConnectivityResult>.broadcast();
  late final StreamSubscription<ConnectivityResult> _subscription;

  ConnectivityResult? _lastStatus;

  /// Expose the broadcast stream
  Stream<ConnectivityResult> get connectivityStream =>
      _connectivityController.stream;

  /// Optional: get last known status
  ConnectivityResult? get lastStatus => _lastStatus;

  /// Dispose when app closes
  void dispose() {
    _subscription.cancel();
    _connectivityController.close();
  }

  /// Helper method for initial status (set at startup)
  Future<void> _initLastStatus() async {
    final result = await Connectivity().checkConnectivity();
    _lastStatus = result;
    _connectivityController.add(result);
  }

  /// Simple boolean check for online status
  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result == ConnectivityResult.mobile ||
        result == ConnectivityResult.wifi;
  }
}
