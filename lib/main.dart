import 'package:flutter/material.dart';

import 'screens/login_screen.dart';

void main() => runApp(const DeskCompanionApp());

class DeskCompanionApp extends StatelessWidget {
  const DeskCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desk Companion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF57BEEB),
      ),
      // 之後如果你寫好了 LoginScreen，就把這裡換掉
      home: const LoginScreen(),
    );
  }
}
