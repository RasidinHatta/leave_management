import 'package:flutter/services.dart' show rootBundle;
import 'package:ini/ini.dart';

const String kDbUsername = 'smartouch';
const String kDbPassword = 'sql9903*';

String kServerName = '';
String kDatabaseName = '';
String kDriverName = 'ODBC Driver 17 for SQL Server';

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

Future<void> loadConfig() async {
  final raw = await rootBundle.loadString('config.ini');
  final config = Config.fromString(raw);

  const section = 'DatabaseConfig';
  final server = config.get(section, 'Server')?.trim() ?? '';
  final database = config.get(section, 'Database')?.trim() ?? '';
  final driver = config.get(section, 'Driver')?.trim();

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
}
