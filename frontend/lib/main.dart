import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/live_scanner_screen.dart';

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint("Failed to load cameras: $e");
  }

  runApp(const ProductCountApp());
}

class ProductCountApp extends StatelessWidget {
  const ProductCountApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Product Count Scanner AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF9D),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF0F172A),
        ),
      ),
      home: LiveScannerScreen(cameras: _cameras),
    );
  }
}
