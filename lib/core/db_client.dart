import 'dart:convert';
import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_odbc/dart_odbc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'constants.dart';

class DatabaseException implements Exception {
  final String message;

  DatabaseException(this.message);

  @override
  String toString() => message;
}

class StoredProcedureUpdateResult {
  final int scriptCount;
  final int batchCount;
  final String databaseName;

  StoredProcedureUpdateResult({
    required this.scriptCount,
    required this.batchCount,
    required this.databaseName,
  });
}

class _SqlScript {
  final String name;
  final String sql;

  _SqlScript({required this.name, required this.sql});
}

class DirectDbClient {
  static final DirectDbClient _instance = DirectDbClient._internal();
  factory DirectDbClient() => _instance;
  DirectDbClient._internal();

  final DartOdbc _odbc = DartOdbc();
  bool _isConnected = false;
  String? _connectedConnectionString;

  void enableDiagnostics() {
    debugPrint('DirectDbClient: ODBC diagnostics enabled.');
  }

  Future<bool> ensureConnected({
    String? serverName,
    String? databaseName,
  }) async {
    if (serverName != null &&
        serverName.isNotEmpty &&
        serverName != kServerName) {
      throw DatabaseException(
        'This app now uses only config.ini. Server override "$serverName" is not supported.',
      );
    }

    final connectionString = buildOdbcConnectionString(
      databaseName: databaseName,
    );
    if (_isConnected && _connectedConnectionString == connectionString) {
      return true;
    }

    if (_isConnected) {
      await _odbc.disconnect();
      _isConnected = false;
      _connectedConnectionString = null;
    }

    try {
      debugPrint(
        'DirectDbClient: Connecting with $kDriverName to $kServerName / ${databaseName ?? kDatabaseName}',
      );
      await _odbc.connectWithConnectionString(connectionString);
      _isConnected = true;
      _connectedConnectionString = connectionString;

      try {
        await ensureLvSysUserTableExists(databaseName ?? kDatabaseName);
      } catch (e) {
        debugPrint('DirectDbClient: User table setup warning: $e');
      }
      return true;
    } catch (e) {
      _isConnected = false;
      _connectedConnectionString = null;
      throw DatabaseException('SQL Server ODBC connection failed: $e');
    }
  }

  List<Map<String, dynamic>> _normaliseRows(List<Map<String, dynamic>> rows) {
    return rows
        .map((row) => row.map((key, value) => MapEntry(key, value)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> query(
    String sqlStr, {
    String? serverName,
    String? databaseName,
  }) async {
    await ensureConnected(serverName: serverName, databaseName: databaseName);
    try {
      final rows = await _odbc.execute(sqlStr);
      return _normaliseRows(rows);
    } catch (e) {
      throw DatabaseException('SQL query failed: $e');
    }
  }

  Future<int> execute(
    String sqlStr, {
    String? serverName,
    String? databaseName,
  }) async {
    await ensureConnected(serverName: serverName, databaseName: databaseName);
    try {
      final rows = await _odbc.execute(sqlStr);
      return rows.length;
    } catch (e) {
      throw DatabaseException('SQL execution failed: $e');
    }
  }

  Future<StoredProcedureUpdateResult> updateStoredProcedures({
    String? databaseName,
  }) async {
    if (kIsWeb) {
      throw DatabaseException('Update Query is not supported on web builds.');
    }

    final dbName = (databaseName != null && databaseName.isNotEmpty)
        ? databaseName
        : kDatabaseName;
    if (dbName.isEmpty) {
      throw DatabaseException('Database is not configured.');
    }

    await ensureConnected(databaseName: dbName);

    final scripts = await _loadStoredProcedureScripts();
    if (scripts.isEmpty) {
      throw DatabaseException('No stored procedure SQL scripts were found.');
    }

    var batchCount = 0;
    for (final script in scripts) {
      await execute('USE ${_sqlIdentifier(dbName)}', databaseName: dbName);
      for (final batch in _splitSqlBatches(script.sql)) {
        await execute(batch, databaseName: dbName);
        batchCount++;
      }
    }

    debugPrint(
      'DirectDbClient: Updated ${scripts.length} SQL script(s), $batchCount batch(es).',
    );
    return StoredProcedureUpdateResult(
      scriptCount: scripts.length,
      batchCount: batchCount,
      databaseName: dbName,
    );
  }

  Future<List<_SqlScript>> _loadStoredProcedureScripts() async {
    final dir = await _findStoredProcedureDirectory();
    if (dir != null) {
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((file) => file.path.toLowerCase().endsWith('.sql'))
              .where((file) {
                final name = file.uri.pathSegments.last.toLowerCase();
                return name != 'setup_config_database.sql';
              })
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      final scripts = <_SqlScript>[];
      for (final file in files) {
        scripts.add(
          _SqlScript(
            name: file.uri.pathSegments.last,
            sql: await file.readAsString(),
          ),
        );
      }
      return scripts;
    }

    const bundledScripts = <String>[
      'sp_AddBringForwardLeave.sql',
      'sp_AddBringForwardLeave_Bulk.sql',
      'sp_AddLeaveRecords_Bulk.sql',
      'sp_DailyAttendanceLeaveReport.sql',
      'sp_ManageReportTargets.sql',
      'sp_ValidateLeaveUser.sql',
    ];

    final scripts = <_SqlScript>[];
    for (final name in bundledScripts) {
      try {
        scripts.add(
          _SqlScript(
            name: name,
            sql: await rootBundle.loadString('stored_procedure/$name'),
          ),
        );
      } catch (e) {
        debugPrint('DirectDbClient: Unable to load bundled script $name: $e');
      }
    }
    return scripts;
  }

  Future<Directory?> _findStoredProcedureDirectory() async {
    final candidates = <Directory>[
      Directory('stored_procedure'),
      Directory(
        '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}stored_procedure',
      ),
    ];

    for (final dir in candidates) {
      if (await dir.exists()) return dir;
    }
    return null;
  }

  List<String> _splitSqlBatches(String sql) {
    final batches = <String>[];
    final buffer = StringBuffer();

    for (final line in LineSplitter().convert(sql)) {
      if (line.trim().toUpperCase() == 'GO') {
        final batch = buffer.toString().trim();
        if (batch.isNotEmpty) batches.add(batch);
        buffer.clear();
      } else {
        buffer.writeln(line);
      }
    }

    final lastBatch = buffer.toString().trim();
    if (lastBatch.isNotEmpty) batches.add(lastBatch);
    return batches;
  }

  String _sqlIdentifier(String value) => '[${value.replaceAll(']', ']]')}]';

  String _quote(String value) => value.replaceAll("'", "''");

  Future<void> ensureLvSysUserTableExists(String databaseName) async {
    final tableCheck = await query(
      "SELECT 1 FROM sys.tables WHERE name = 'LV_SYS_USER' AND schema_id = SCHEMA_ID('dbo')",
      databaseName: databaseName,
    );

    if (tableCheck.isEmpty) {
      await execute('''
CREATE TABLE dbo.LV_SYS_USER (
  USERNAME VARCHAR(14) NOT NULL PRIMARY KEY,
  PASSWD VARCHAR(255) NULL,
  ROLE VARCHAR(20) DEFAULT 'USER'
)
''', databaseName: databaseName);
    } else {
      final columnCheck = await query('''
SELECT
  (SELECT character_maximum_length FROM information_schema.columns WHERE table_name = 'LV_SYS_USER' AND column_name = 'PASSWD') AS PasswdLen,
  (SELECT 1 FROM information_schema.columns WHERE table_name = 'LV_SYS_USER' AND column_name = 'ROLE') AS RoleExists
''', databaseName: databaseName);
      if (columnCheck.isNotEmpty) {
        final passwdLen = columnCheck.first['PasswdLen'];
        final roleExists = columnCheck.first['RoleExists'];
        if (passwdLen is num && passwdLen < 255) {
          await execute(
            'ALTER TABLE dbo.LV_SYS_USER ALTER COLUMN PASSWD VARCHAR(255) NULL',
            databaseName: databaseName,
          );
        }
        if (roleExists != 1) {
          await execute(
            "ALTER TABLE dbo.LV_SYS_USER ADD ROLE VARCHAR(20) DEFAULT 'USER'",
            databaseName: databaseName,
          );
        }
      }
    }

    await _seedUser('SUPER', 'ADMIN', databaseName);
    await _seedUser('STT', 'USER', databaseName);
    await _seedUser('REPORT', 'REPORT', databaseName);
  }

  Future<void> _seedUser(
    String username,
    String role,
    String databaseName,
  ) async {
    final exists = await query(
      "SELECT 1 FROM dbo.LV_SYS_USER WHERE USERNAME = '$username'",
      databaseName: databaseName,
    );
    if (exists.isNotEmpty) return;

    final hashedPwd = BCrypt.hashpw('39903', BCrypt.gensalt(logRounds: 10));
    await execute(
      "INSERT INTO dbo.LV_SYS_USER (USERNAME, PASSWD, ROLE) VALUES ('$username', '$hashedPwd', '$role')",
      databaseName: databaseName,
    );
  }

  Future<Map<String, dynamic>> leaveLogin(
    String username,
    String password,
    String databaseName,
  ) async {
    final cleanUsername = _quote(username);
    final results = await query(
      "SELECT USERNAME, PASSWD, ROLE FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanUsername'",
      databaseName: databaseName,
    );
    if (results.isEmpty) {
      throw DatabaseException('Invalid username or password');
    }

    final user = results.first;
    final storedHash = user['PASSWD'] as String?;
    final role = user['ROLE'] as String? ?? 'USER';
    if (storedHash == null) {
      throw DatabaseException('Invalid username or password');
    }

    final isMatch = BCrypt.checkpw(password, storedHash);
    final isLegacyMatch = password == storedHash;
    if (!isMatch && !isLegacyMatch) {
      throw DatabaseException('Invalid username or password');
    }

    return {
      'success': true,
      'username': user['USERNAME'],
      'role': role,
      'database': databaseName,
    };
  }

  Future<List<dynamic>> getUsers(
    String requesterUsername,
    String databaseName,
  ) async {
    final cleanRequester = _quote(requesterUsername);
    final reqResults = await query(
      "SELECT ROLE FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanRequester'",
      databaseName: databaseName,
    );
    if (reqResults.isEmpty || reqResults.first['ROLE'] != 'ADMIN') {
      throw DatabaseException('Only ADMIN can view users');
    }

    return query(
      "SELECT USERNAME as username, ROLE as role FROM dbo.LV_SYS_USER WHERE ISNULL(ROLE, 'USER') <> 'ADMIN' ORDER BY USERNAME ASC",
      databaseName: databaseName,
    );
  }

  Future<Map<String, dynamic>> addUser(
    String requesterUsername,
    String newUsername,
    String newPassword,
    String role,
    String databaseName,
  ) async {
    final cleanRequester = _quote(requesterUsername);
    final reqResults = await query(
      "SELECT ROLE FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanRequester'",
      databaseName: databaseName,
    );
    if (reqResults.isEmpty || reqResults.first['ROLE'] != 'ADMIN') {
      throw DatabaseException('Only ADMIN can create users');
    }

    final cleanNewUser = _quote(newUsername);
    final normalizedRole = role.toUpperCase().trim();
    if (normalizedRole != 'USER' && normalizedRole != 'REPORT') {
      throw DatabaseException('Role must be USER or REPORT');
    }

    final userCheck = await query(
      "SELECT 1 FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanNewUser'",
      databaseName: databaseName,
    );
    if (userCheck.isNotEmpty) {
      throw DatabaseException('User already exists');
    }

    final hashedPwd = BCrypt.hashpw(newPassword, BCrypt.gensalt(logRounds: 10));
    await execute(
      "INSERT INTO dbo.LV_SYS_USER (USERNAME, PASSWD, ROLE) VALUES ('$cleanNewUser', '$hashedPwd', '$normalizedRole')",
      databaseName: databaseName,
    );

    return {'success': true, 'message': 'User created successfully'};
  }

  Future<Map<String, dynamic>> updateUser(
    String requesterUsername,
    String targetUsername,
    String? newPassword,
    String role,
    String databaseName,
  ) async {
    final cleanRequester = _quote(requesterUsername);
    final reqResults = await query(
      "SELECT ROLE FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanRequester'",
      databaseName: databaseName,
    );
    if (reqResults.isEmpty || reqResults.first['ROLE'] != 'ADMIN') {
      throw DatabaseException('Only ADMIN can update users');
    }

    final cleanTarget = _quote(targetUsername);
    final normalizedRole = role.toUpperCase().trim();
    if (normalizedRole != 'USER' && normalizedRole != 'REPORT') {
      throw DatabaseException('Role must be USER or REPORT');
    }

    final userCheck = await query(
      "SELECT 1 FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanTarget' AND ISNULL(ROLE, 'USER') <> 'ADMIN'",
      databaseName: databaseName,
    );
    if (userCheck.isEmpty) {
      throw DatabaseException('Target user not found');
    }

    if (newPassword != null && newPassword.trim().isNotEmpty) {
      final hashedPwd = BCrypt.hashpw(
        newPassword,
        BCrypt.gensalt(logRounds: 10),
      );
      await execute(
        "UPDATE dbo.LV_SYS_USER SET PASSWD = '$hashedPwd', ROLE = '$normalizedRole' WHERE USERNAME = '$cleanTarget'",
        databaseName: databaseName,
      );
    } else {
      await execute(
        "UPDATE dbo.LV_SYS_USER SET ROLE = '$normalizedRole' WHERE USERNAME = '$cleanTarget'",
        databaseName: databaseName,
      );
    }

    return {'success': true, 'message': 'User updated successfully'};
  }

  Future<Map<String, dynamic>> deleteUser(
    String requesterUsername,
    String targetUsername,
    String databaseName,
  ) async {
    if (requesterUsername == targetUsername) {
      throw DatabaseException('You cannot delete your own account');
    }

    final cleanRequester = _quote(requesterUsername);
    final reqResults = await query(
      "SELECT ROLE FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanRequester'",
      databaseName: databaseName,
    );
    if (reqResults.isEmpty || reqResults.first['ROLE'] != 'ADMIN') {
      throw DatabaseException('Only ADMIN can delete users');
    }

    final cleanTarget = _quote(targetUsername);
    final userCheck = await query(
      "SELECT 1 FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanTarget' AND ISNULL(ROLE, 'USER') <> 'ADMIN'",
      databaseName: databaseName,
    );
    if (userCheck.isEmpty) {
      throw DatabaseException('Target user not found');
    }

    await execute(
      "DELETE FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanTarget'",
      databaseName: databaseName,
    );
    return {'success': true, 'message': 'User deleted successfully'};
  }

  Future<List<Map<String, dynamic>>> getLeaveTypes(String databaseName) {
    return query('''
SELECT
  CAST(LV_CODE AS VARCHAR(50)) AS lvCode,
  CAST(LV_DESC AS VARCHAR(255)) AS lvDesc,
  CAST(LV_EVENT_CODE AS VARCHAR(50)) AS lvEventCode,
  CAST(IS_LEAVE AS INT) AS isLeave,
  CAST(DAY_ AS DECIMAL(18, 4)) AS day,
  CAST(LV_DAY_PORTION_CODE AS VARCHAR(50)) AS lvDayPortionCode
FROM dbo.LV_TYPE
WHERE CAST(LV_EVENT_CODE AS VARCHAR(50)) = 'LEAVE'
ORDER BY CAST(LV_CODE AS VARCHAR(50))
''', databaseName: databaseName);
  }

  Future<List<Map<String, dynamic>>> getDailyReport({
    required String database,
    required String date,
    String? office,
    String? department,
  }) {
    final cleanDate = _quote(date);
    final params = StringBuffer(
      "EXEC dbo.sp_DailyAttendanceLeaveReport @ReportDate = '$cleanDate'",
    );
    if (office != null && office.isNotEmpty) {
      params.write(", @Office = '${_quote(office)}'");
    }
    if (department != null && department.isNotEmpty) {
      params.write(", @Department = '${_quote(department)}'");
    }
    return query(params.toString(), databaseName: database);
  }

  Future<Map<String, dynamic>> addBringForwardLeave({
    required String database,
    required int year,
    required int month,
    required List<Map<String, dynamic>> list,
  }) async {
    if (list.isEmpty) throw DatabaseException('No records to add.');

    final buffer = StringBuffer();
    buffer.writeln('DECLARE @List dbo.BringForwardLeaveList;');
    for (final item in list) {
      final empCode = _quote(item['empCode'].toString());
      final day = double.parse(item['day'].toString());
      buffer.writeln(
        "INSERT INTO @List (EMP_CODE, DAY_) VALUES ('$empCode', $day);",
      );
    }
    buffer.writeln(
      'EXEC dbo.sp_AddBringForwardLeave_Bulk @Year = $year, @Month = $month, @List = @List;',
    );

    await execute(buffer.toString(), databaseName: database);
    return {
      'success': true,
      'message':
          'Successfully added ${list.length} bring forward leave records in database $database',
    };
  }

  Future<Map<String, dynamic>> addLeaveTaken({
    required String database,
    required List<Map<String, dynamic>> list,
  }) async {
    if (list.isEmpty) throw DatabaseException('No records to add.');

    final seenRows = <String>{};
    for (final item in list) {
      final empCode = item['empCode'].toString().trim().toUpperCase();
      final lvDate = item['lvDate'].toString().trim();
      final lvCode = item['lvCode'].toString().trim().toUpperCase();
      final key = '$empCode|$lvDate|$lvCode';
      if (!seenRows.add(key)) {
        throw DatabaseException(
          'Duplicate leave code found for employee $empCode on $lvDate.',
        );
      }
    }

    final values = list
        .map((item) {
          final empCode = _quote(item['empCode'].toString());
          final lvDate = _quote(item['lvDate'].toString());
          final lvCode = _quote(item['lvCode'].toString());
          return "('$empCode', CAST('$lvDate' AS date), '$lvCode')";
        })
        .join(',\n');

    final duplicateRows = await query('''
SELECT TOP 1
  CAST(R.EMP_CODE AS VARCHAR(50)) AS empCode,
  CONVERT(VARCHAR(10), R.LV_DATE, 120) AS lvDate,
  CAST(R.LV_CODE AS VARCHAR(50)) AS lvCode
FROM dbo.LV_RECORDS R
INNER JOIN (VALUES
$values
) V(EMP_CODE, LV_DATE, LV_CODE)
  ON R.EMP_CODE = V.EMP_CODE
 AND R.LV_DATE = V.LV_DATE
 AND R.LV_CODE = V.LV_CODE
WHERE R.LV_EVENT_CODE = 'LEAVE'
''', databaseName: database);

    if (duplicateRows.isNotEmpty) {
      final row = duplicateRows.first;
      throw DatabaseException(
        'Leave record already exists for employee ${row['empCode']} on ${row['lvDate']} with leave code ${row['lvCode']}.',
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('DECLARE @List dbo.LeaveImportList;');
    for (final item in list) {
      final empCode = _quote(item['empCode'].toString());
      final lvDate = _quote(item['lvDate'].toString());
      final lvCode = _quote(item['lvCode'].toString());
      final remark = item['remark'] != null
          ? "'${_quote(item['remark'].toString())}'"
          : 'NULL';
      buffer.writeln(
        "INSERT INTO @List (EMP_CODE, LV_DATE, LV_CODE, REMARK) VALUES ('$empCode', '$lvDate', '$lvCode', $remark);",
      );
    }
    buffer.writeln('EXEC dbo.sp_AddLeaveRecords_Bulk @List = @List;');

    await execute(buffer.toString(), databaseName: database);

    final verificationRows = await query('''
SELECT COUNT(*) AS insertedCount
FROM dbo.LV_RECORDS R
INNER JOIN (VALUES
$values
) V(EMP_CODE, LV_DATE, LV_CODE)
  ON R.EMP_CODE = V.EMP_CODE
 AND R.LV_DATE = V.LV_DATE
 AND R.LV_CODE = V.LV_CODE
WHERE R.LV_EVENT_CODE = 'LEAVE'
''', databaseName: database);
    final insertedCount = verificationRows.isNotEmpty
        ? int.tryParse(
            verificationRows.first['insertedCount']?.toString() ?? '',
          )
        : null;

    if (insertedCount != list.length) {
      throw DatabaseException(
        'Leave import did not complete. Expected ${list.length} row(s), inserted ${insertedCount ?? 0}.',
      );
    }

    return {
      'success': true,
      'message':
          'Successfully added $insertedCount leave records in database $database',
    };
  }
}
