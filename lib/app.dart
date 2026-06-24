import 'package:flutter/material.dart';

import 'ui/screens/root_screen.dart';

/// Teams Lite — a from-scratch Dart port of the purple-teams plugin logic,
/// targeting Microsoft Teams **personal** accounts.
class TeamsLiteApp extends StatelessWidget {
  const TeamsLiteApp({super.key});

  // Teams brand purple.
  static const Color _brand = Color(0xFF6264A7);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Teams Lite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const RootScreen(),
    );
  }
}
