import 'package:flutter/material.dart';
import 'package:leave_management/core/constants.dart';
import 'package:leave_management/core/db_client.dart';
import 'package:leave_management/core/theme.dart';
import 'package:leave_management/screens/home_screen.dart';
import 'package:leave_management/screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadConfig();
  DirectDbClient().enableDiagnostics();
  try {
    await DirectDbClient().runStartupStoredProcedures();
  } catch (e) {
    debugPrint('Startup database setup failed: $e');
  }
  runApp(const LeaveManagementApp());
}

class LeaveManagementApp extends StatefulWidget {
  const LeaveManagementApp({super.key});

  static final ValueNotifier<double> fontSizeNotifier = ValueNotifier<double>(
    0.85,
  );
  static final ValueNotifier<AppAppearance> appearanceNotifier =
      ValueNotifier<AppAppearance>(const AppAppearance());

  @override
  State<LeaveManagementApp> createState() => _LeaveManagementAppState();
}

class _LeaveManagementAppState extends State<LeaveManagementApp> {
  bool _isLoggedIn = false;
  String _loggedInUsername = '';
  String _loggedInRole = '';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppAppearance>(
      valueListenable: LeaveManagementApp.appearanceNotifier,
      builder: (context, appearance, _) {
        return ValueListenableBuilder<double>(
          valueListenable: LeaveManagementApp.fontSizeNotifier,
          builder: (context, factor, child) {
            return MaterialApp(
              title: 'HR Leave Management',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.fromAppearance(appearance),
              builder: (context, child) {
                final mediaQuery = MediaQuery.of(context);
                return MediaQuery(
                  data: mediaQuery.copyWith(
                    textScaler: TextScaler.linear(factor),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: _isLoggedIn
                  ? HomeScreen(
                      username: _loggedInUsername,
                      role: _loggedInRole,
                      onLogout: () {
                        setState(() {
                          _isLoggedIn = false;
                          _loggedInUsername = '';
                          _loggedInRole = '';
                        });
                      },
                    )
                  : LoginScreen(
                      onLoginSuccess: (username, role) {
                        setState(() {
                          _isLoggedIn = true;
                          _loggedInUsername = username;
                          _loggedInRole = role;
                        });
                      },
                    ),
            );
          },
        );
      },
    );
  }
}
