import 'package:flutter/material.dart';
import 'screens/webview_screen.dart';

void main() {
  runApp(const ShopPulseCustomerApp());
}

class ShopPulseCustomerApp extends StatelessWidget {
  const ShopPulseCustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShopPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2563EB),
        brightness: Brightness.light,
      ),
      home: const WebViewScreen(),
    );
  }
}
