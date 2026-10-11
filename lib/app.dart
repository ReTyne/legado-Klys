import 'package:flutter/material.dart';
import 'ui/main/main_screen.dart';

class LegadoApp extends StatelessWidget {
  const LegadoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legado',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF6750A4)),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF6750A4)),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
