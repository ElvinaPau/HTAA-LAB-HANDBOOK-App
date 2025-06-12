import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
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
    );
  }
}
