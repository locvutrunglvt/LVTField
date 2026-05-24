import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/map/map_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/author_page.dart';
import 'features/settings/help_screen.dart';
import 'features/tools/gps_compass_screen.dart';
import 'features/tools/track_recording_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LVTField App - Mobile GIS for Forest Survey
/// Author: Lộc Vũ Trung
class LVTFieldApp extends StatefulWidget {
  const LVTFieldApp({super.key});

  /// Global key to access theme switching from anywhere
  static final GlobalKey<_LVTFieldAppState> appKey = GlobalKey<_LVTFieldAppState>();

  /// Switch theme mode from outside
  static void setThemeMode(ThemeMode mode) {
    appKey.currentState?._setThemeMode(mode);
  }

  /// Get current theme mode
  static ThemeMode get currentThemeMode =>
      appKey.currentState?._themeMode ?? ThemeMode.system;

  @override
  State<LVTFieldApp> createState() => _LVTFieldAppState();
}

class _LVTFieldAppState extends State<LVTFieldApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString('theme_mode') ?? 'system';
    if (mounted) {
      setState(() {
        _themeMode = _parseThemeMode(modeStr);
      });
    }
  }

  void _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  ThemeMode _parseThemeMode(String str) {
    switch (str) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      key: LVTFieldApp.appKey,
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      routerConfig: _router,
    );
  }
}

/// App router configuration
final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/map/:projectId',
      name: 'map',
      builder: (context, state) {
        final projectId = state.pathParameters['projectId']!;
        return MapScreen(projectId: projectId);
      },
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/author',
      name: 'author',
      builder: (context, state) => const AuthorPage(),
    ),
    GoRoute(
      path: '/help',
      name: 'help',
      builder: (context, state) => const HelpScreen(),
    ),
    GoRoute(
      path: '/tools/gps',
      name: 'gps',
      builder: (context, state) => const GpsCompassScreen(),
    ),
  ],
);
