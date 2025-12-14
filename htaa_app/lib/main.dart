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

  // Open boxes (including new metadataBox for update tracking)
  await Hive.openBox('categoriesBox');
  await Hive.openBox('testsBox');
  await Hive.openBox('testDetailsBox');
  await Hive.openBox('formsBox');
  await Hive.openBox('contactsBox');
  await Hive.openBox('bookmarksBox');
  await Hive.openBox('pendingAdditionsBox');
  await Hive.openBox('pendingDeletionsBox');
  await Hive.openBox('metadataBox'); //For tracking updates

  // Run app
  runApp(const HtaaApp());

  // Trigger automatic update check (non-blocking)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _checkAndUpdateData();
  });
}

/// Automatically checks for updates and downloads if needed
Future<void> _checkAndUpdateData() async {
  final connectivity = ConnectivityService();
  final isOnline = await connectivity.isOnline();

  if (!isOnline) {
    print('Offline — using cached data');
    return;
  }

  try {
    final preloadService = await DataPreloadService.create();

    // Check if update is needed
    final needsUpdate = await preloadService.needsUpdate();

    if (needsUpdate) {
      print('Update detected — downloading latest data...');

      await preloadService.preloadAllData(
        onProgress: (message, progress) {
          print('$message (${(progress * 100).toStringAsFixed(1)}%)');
        },
      );

      // Save update timestamp
      await preloadService.saveUpdateMetadata();

      print('Update complete — data refreshed successfully');
    } else {
      print('Data is up to date — no update needed');
    }
  } catch (e) {
    print('Update failed: $e');
    print('Continuing with cached data');
  }
}

class HtaaApp extends StatelessWidget {
  const HtaaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HTAA LAB HANDBOOK',
      theme: ThemeData(
        primaryColor: const Color(0xFF8B5CF6),
        scaffoldBackgroundColor: const Color(0xFFF5E6FF),
        textTheme: Typography.englishLike2018.apply(
          fontSizeFactor: 1.2,
          bodyColor: Colors.black,
          displayColor: Colors.black,
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
    );
  }
}