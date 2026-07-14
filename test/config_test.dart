import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leave_management/core/constants.dart';

void main() {
  test('debug config reloads from the current working directory', () async {
    final originalWorkingDirectory = Directory.current;
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'leave_management_config_test_',
    );

    try {
      await File(
        '${temporaryDirectory.path}${Platform.pathSeparator}config.ini',
      ).writeAsString('''
[DatabaseConfig]
Server=DEBUG-SERVER
Database=DEBUG-DATABASE
Driver=DEBUG-DRIVER
''');
      Directory.current = temporaryDirectory;

      await loadConfig();

      expect(kServerName, 'DEBUG-SERVER');
      expect(kDatabaseName, 'DEBUG-DATABASE');
      expect(kDriverName, 'DEBUG-DRIVER');
    } finally {
      Directory.current = originalWorkingDirectory;
      await temporaryDirectory.delete(recursive: true);
    }
  });
}
