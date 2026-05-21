import 'dart:io';
import 'package:flutter/foundation.dart';

String kBaseUrl = 'http://localhost:3000';
String kConnectionString = '';

String get kDatabaseName => getDatabaseNameFromConnectionString(kConnectionString);

String getDatabaseNameFromConnectionString(String connStr) {
  final parts = connStr.split(';');
  for (final part in parts) {
    final kv = part.split('=');
    if (kv.length == 2) {
      final key = kv[0].trim().toLowerCase();
      final val = kv[1].trim();
      if (key == 'initial catalog' || key == 'database') {
        return val;
      }
    }
  }
  return '';
}

Future<void> loadConfig() async {
  if (kIsWeb) return;
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    var file = File('config.ini');

    if (!await file.exists()) {
      file = File('$exeDir/config.ini');
    }

    if (!await file.exists()) {
      await file.writeAsString('''[API]
# Change the baseUrl to point to the backend API server.
baseUrl = http://localhost:3000

[CONNECTION]
;STRING=Provider=SQLNCLI11;Persist Security Info=True;Initial Catalog=MYPAY_KIN;Data Source=DIN-STT
STRING=Provider=SQLNCLI11;Persist Security Info=True;Initial Catalog=MYPAY_JSM;Data Source=v1soho.com,1500
''');
    } else {
      final lines = await file.readAsLines();
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith(';') || line.startsWith('#') || line.startsWith('[')) {
          continue;
        }
        if (line.contains('=')) {
          final parts = line.split('=');
          final key = parts[0].trim().toLowerCase();
          final val = parts.sublist(1).join('=').trim();
          if (key == 'baseurl') {
            kBaseUrl = val;
          } else if (key == 'string') {
            kConnectionString = val;
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Failed to load config.ini: $e');
  }
}

