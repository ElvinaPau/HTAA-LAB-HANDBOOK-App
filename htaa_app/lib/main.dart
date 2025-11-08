import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/home_screen.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Make sure Flutter is ready

  // Initialize Hive
  await Hive.initFlutter();

  // Open a box (like a local database)
  await Hive.openBox('categoriesBox');
  await Hive.openBox('testsBox');
  await Hive.openBox('testDetailsBox');

  runApp(const HtaaApp());
}

class HtaaApp extends StatelessWidget {
  const HtaaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HTAA LAB HANDBOOK',
      theme: ThemeData(
        primaryColor: Color(0xFF865BB8),
        scaffoldBackgroundColor: const Color(0xFFFFEAFD),
      ),
      home: HomeScreen(),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
    );
  }
}
