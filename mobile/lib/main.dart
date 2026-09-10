import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/screens/splash_screen.dart';
import 'package:mobile/theme/navsync_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set technical aerospace status & navigation bar styles
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: NavSyncTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const NavSyncApp());
}

class NavSyncApp extends StatelessWidget {
  const NavSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NavSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: NavSyncTheme.background,
        colorScheme: const ColorScheme.dark(
          surface: NavSyncTheme.surface,
          primary: NavSyncTheme.accent,
          onSurface: NavSyncTheme.primaryText,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
