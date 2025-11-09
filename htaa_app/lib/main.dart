import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/home_screen.dart';
import 'services/data_preload_service.dart';
import 'services/connectivity_service.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();

  // Open boxes
  await Hive.openBox('categoriesBox');
  await Hive.openBox('testsBox');
  await Hive.openBox('testDetailsBox');
  await Hive.openBox('formsBox');
  await Hive.openBox('contactsBox');
  await Hive.openBox('bookmarksBox');
  await Hive.openBox('pendingAdditionsBox');
  await Hive.openBox('pendingDeletionsBox');

  // Run app
  runApp(const HtaaApp());

  // Trigger background preload (non-blocking)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _runInitialPreload();
  });
}

Future<void> _runInitialPreload() async {
  final connectivity = ConnectivityService();
  final isOnline = await connectivity.isOnline();

  if (!isOnline) {
    print('⚠️ Skipping preload — no internet connection');
    return;
  }

  try {
    // Use async factory constructor
    final preloadService = await DataPreloadService.create();

    await preloadService.preloadAllData(
      onProgress: (message, progress) {
        // Optional: connect to a UI progress bar
        print('🔹 $message (${(progress * 100).toStringAsFixed(1)}%)');
      },
    );

    print('✅ Preload complete — all test data cached locally.');
  } catch (e) {
    print('❌ Preload failed: $e');
  }
}

class HtaaApp extends StatelessWidget {
  const HtaaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HTAA LAB HANDBOOK',
      theme: ThemeData(
        primaryColor: const Color(0xFF865BB8),
        scaffoldBackgroundColor: const Color(0xFFFFEAFD),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
    );
  }
}
