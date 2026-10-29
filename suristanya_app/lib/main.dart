import 'package:flutter/material.dart';

import 'services/api_settings.dart';
import 'services/auth_store.dart';
import 'services/scan_history_store.dart';
import 'theme/app_theme.dart';
import 'widgets/connection_banner.dart';

// Screens
import 'screens/welcome_screen.dart';
import 'screens/signin_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/how_it_works_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chatbot_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/results_screen.dart';
import 'screens/full_report_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/history_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/labs_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiSettings.instance.load();
  await AuthStore.instance.load();
  await ScanHistoryStore.instance.load();
  runApp(const SuristanyaApp());
}

class SuristanyaApp extends StatelessWidget {
  const SuristanyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final initial = AuthStore.instance.isSignedIn ? '/dashboard' : '/';

    return MaterialApp(
      title: 'Suristanya',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: initial,
      builder: (context, child) =>
          ConnectionBanner(child: child ?? const SizedBox()),
      onGenerateRoute: (settings) {
        Widget page = const WelcomeScreen();

        switch (settings.name) {
          case '/':
            page = const WelcomeScreen();
            break;
          case '/signin':
            page = const SignInScreen();
            break;
          case '/signup':
            page = const SignUpScreen();
            break;
          case '/forgot':
            page = const ForgotPasswordScreen();
            break;
          case '/how':
            page = const HowItWorksScreen();
            break;
          case '/dashboard':
            page = const DashboardScreen();
            break;
          case '/chat':
            page = const ChatbotScreen();
            break;
          case '/scan':
            page = const ScanScreen();
            break;
          case '/processing':
            page = const ProcessingScreen();
            break;
          case '/results':
            page = const ResultsScreen();
            break;
          case '/full-report':
            page = const FullReportScreen();
            break;
          case '/profile':
            page = const ProfileScreen();
            break;
          case '/history':
            page = const HistoryScreen();
            break;
          case '/privacy':
            page = const PrivacyScreen();
            break;
          case '/labs':
            page = const LabsScreen();
            break;
        }

        // Global Smooth Fade + Slide Transition
        return PageRouteBuilder(
          settings: settings,
          // Using single underscores to fix linter warnings
          pageBuilder: (_, _, _) => page,
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (_, animation, _, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            return FadeTransition(
              opacity: curvedAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05), // slide up slightly
                  end: Offset.zero,
                ).animate(curvedAnimation),
                child: child,
              ),
            );
          },
        );
      },
    );
  }
}
