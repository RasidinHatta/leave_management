import 'dart:io';
import 'package:flutter/foundation.dart';

String kBaseUrl = 'http://localhost:3000';

Future<void> loadConfig() async {
  if (kIsWeb) return;
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final file = File('$exeDir/config.ini');

    if (!await file.exists()) {
      await file.writeAsString('''# HR Leave Management Configuration
# Change the baseUrl to point to the backend API server.

baseUrl = http://localhost:3000
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
          final key = parts[0].trim();
          final val = parts.sublist(1).join('=').trim();
          if (key.toLowerCase() == 'baseurl') {
            kBaseUrl = val;
            break;
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Failed to load config.ini: $e');
  }
}

