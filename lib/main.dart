import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const platform = MethodChannel('com.example.desk_buddy/cv_channel');

  Future<void> _showNativeToast() async {
    try {
      final String result = await platform.invokeMethod('showToast', {"message": "哈囉！這是來自 Android 的原生訊息"});
      print(result);
    } on PlatformException catch (e) {
      print("Failed to call native: '${e.message}'.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Desk Buddy 雛型')),
        body: Center(
          child: ElevatedButton(
            onPressed: _showNativeToast,
            child: const Text('測試原生溝通'),
          ),
        ),
      ),
    );
  }
}