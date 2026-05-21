import 'package:flutter/material.dart';
import 'package:leave_management/core/constants.dart';
import 'package:leave_management/core/theme.dart';
import 'package:leave_management/screens/home_screen.dart';
import 'package:leave_management/screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadConfig();
  runApp(const LeaveManagementApp());
}

class LeaveManagementApp extends StatefulWidget {
  const LeaveManagementApp({super.key});

  static final ValueNotifier<double> fontSizeNotifier = ValueNotifier<double>(0.85);

  @override
  State<LeaveManagementApp> createState() => _LeaveManagementAppState();
}

class _LeaveManagementAppState extends State<LeaveManagementApp> {
  bool _isLoggedIn = false;
  String _loggedInUsername = '';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: LeaveManagementApp.fontSizeNotifier,
      builder: (context, factor, child) {
        return MaterialApp(
          title: 'HR Leave Management',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark.copyWith(
            textTheme: AppTheme.scaleTextTheme(
              AppTheme.dark.textTheme,
              factor,
            ),
          ),
          home: _isLoggedIn
              ? HomeScreen(
                  username: _loggedInUsername,
                  onLogout: () {
                    setState(() {
                      _isLoggedIn = false;
                      _loggedInUsername = '';
                    });
                  },
                )
              : LoginScreen(
                  onLoginSuccess: (username) {
                    setState(() {
                      _isLoggedIn = true;
                      _loggedInUsername = username;
                    });
                  },
                ),
        );
      },
    );
  }
}
