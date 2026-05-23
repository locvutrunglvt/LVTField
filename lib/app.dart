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

/// LVTField App - Mobile GIS for Forest Survey
/// Author: Lộc Vũ Trung
class LVTFieldApp extends StatelessWidget {
  const LVTFieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
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
  ],
);
