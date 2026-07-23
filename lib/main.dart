import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'navigation/app_route_observer.dart';
import 'screens/face_detection_screen.dart';
import 'screens/login_screen.dart';

const bool _offlineDemoRequested = bool.fromEnvironment('OFFLINE_DEMO');

void main() =>
    runApp(DeskCompanionApp(offlineDemo: kDebugMode && _offlineDemoRequested));

class DeskCompanionApp extends StatelessWidget {
  const DeskCompanionApp({super.key, this.offlineDemo = false});

  final bool offlineDemo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desk Companion',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [appRouteObserver],
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF57BEEB),
      ),
      home: offlineDemo ? const FaceDetectionScreen() : const LoginScreen(),
    );
  }
}
