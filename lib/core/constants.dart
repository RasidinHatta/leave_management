import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:ini/ini.dart';

String kDbUsername = 'smartouch';
String kDbPassword = 'sql9903*';

String kServerName = '';
String kDatabaseName = '';
String kDriverName = 'ODBC Driver 17 for SQL Server';
bool kAdminMenuEnabled = false;

String kReportDatabaseName = 'HR_REPORT_CONFIG';
String kReportServerName = 'v1soho.com,1500';
String kReportDriverName = 'ODBC Driver 17 for SQL Server';

String get kOdbcConnectionString =>
    'DRIVER={$kDriverName};'
    'Server=$kServerName;'
    'Database=$kDatabaseName;'
    'Uid=$kDbUsername;'
    'Pwd=$kDbPassword;'
    'Encrypt=yes;'
    'TrustServerCertificate=yes;'
    'Persist Security Info=True;';

String buildOdbcConnectionString({String? databaseName}) {
  final dbName = (databaseName != null && databaseName.isNotEmpty)
      ? databaseName
      : kDatabaseName;
  return 'DRIVER={$kDriverName};'
      'Server=$kServerName;'
      'Database=$dbName;'
      'Uid=$kDbUsername;'
      'Pwd=$kDbPassword;'
      'Encrypt=yes;'
      'TrustServerCertificate=yes;'
      'Persist Security Info=True;';
}

String buildReportOdbcConnectionString() {
  return buildReportOdbcConnectionStringForDatabase(kReportDatabaseName);
}

String buildReportOdbcConnectionStringForDatabase(String databaseName) {
  return 'DRIVER={$kReportDriverName};'
      'Server=$kReportServerName;'
      'Database=$databaseName;'
      'Uid=$kDbUsername;'
      'Pwd=$kDbPassword;'
      'Encrypt=yes;'
      'TrustServerCertificate=yes;'
      'Persist Security Info=True;';
}

Future<void> loadConfig() async {
  final raw = await _loadConfigText();
  final config = Config.fromString(raw);

  const section = 'DatabaseConfig';
  final server = config.get(section, 'Server')?.trim() ?? '';
  final database = config.get(section, 'Database')?.trim() ?? '';
  final driver = config.get(section, 'Driver')?.trim();
  final admin = config.get(section, 'Admin')?.trim().toLowerCase() ?? '';
  final reportServer = config.get('ReportConfig', 'Server')?.trim();

  if (server.isEmpty || database.isEmpty) {
    throw Exception(
      'config.ini must contain Server and Database under [DatabaseConfig].',
    );
  }

  kServerName = server;
  kDatabaseName = database;
  if (driver != null && driver.isNotEmpty) {
    kDriverName = driver;
  }
  kAdminMenuEnabled = const {'1', 'true', 'yes', 'on'}.contains(admin);

  kReportServerName = reportServer != null && reportServer.isNotEmpty
      ? reportServer
      : 'v1soho.com,1500';
  kReportDriverName = kDriverName;
}

Future<String> _loadConfigText() async {
  if (!kIsWeb) {
    // `flutter run -d windows` starts the app with the project root as its
    // working directory. Prefer that config in debug mode so a hot restart
    // reloads edits without requiring CMake to recopy the file.
    if (kDebugMode) {
      final developmentConfig = File(
        '${Directory.current.path}${Platform.pathSeparator}config.ini',
      );
      if (await developmentConfig.exists()) {
        return developmentConfig.readAsString();
      }
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final externalConfig = File('$exeDir${Platform.pathSeparator}config.ini');
    if (await externalConfig.exists()) {
      return externalConfig.readAsString();
    }
  }

  return rootBundle.loadString('config.ini');
}
