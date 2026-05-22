import 'dart:convert';
import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_odbc/dart_odbc.dart';
import 'package:flutter/foundation.dart';

import 'constants.dart';

class DatabaseException implements Exception {
  final String message;

  const DatabaseException(this.message);

  @override
  String toString() => message;
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

  Future<void> runStartupStoredProcedures({String? databaseName}) async {
    if (kIsWeb) return;

    final dbName = (databaseName != null && databaseName.isNotEmpty)
        ? databaseName
        : kDatabaseName;
    if (dbName.isEmpty) {
      debugPrint('DirectDbClient: Database is not configured.');
      return;
    }

    await ensureConnected(databaseName: dbName);

    final dir = await _findStoredProcedureDirectory();
    if (dir == null) {
      debugPrint('DirectDbClient: stored_procedure folder not found.');
      return;
    }

    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.sql'))
            .where((file) {
              final name = file.uri.pathSegments.last.toLowerCase();
              return name != 'setup_config_database.sql' &&
                  name != 'sp_managereporttargets.sql';
            })
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final sql = await file.readAsString();
      for (final batch in _splitSqlBatches(sql)) {
        await execute(batch, databaseName: dbName);
      }
    }

    debugPrint('DirectDbClient: Startup stored procedures finished.');
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

    for (final line in const LineSplitter().convert(sql)) {
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
      throw const DatabaseException('Invalid username or password');
    }

    final user = results.first;
    final storedHash = user['PASSWD'] as String?;
    final role = user['ROLE'] as String? ?? 'USER';
    if (storedHash == null) {
      throw const DatabaseException('Invalid username or password');
    }

    final isMatch = BCrypt.checkpw(password, storedHash);
    final isLegacyMatch = password == storedHash;
    if (!isMatch && !isLegacyMatch) {
      throw const DatabaseException('Invalid username or password');
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
      throw const DatabaseException('Only ADMIN can view users');
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
      throw const DatabaseException('Only ADMIN can create users');
    }

    final cleanNewUser = _quote(newUsername);
    final normalizedRole = role.toUpperCase().trim();
    if (normalizedRole != 'USER' && normalizedRole != 'REPORT') {
      throw const DatabaseException('Role must be USER or REPORT');
    }

    final userCheck = await query(
      "SELECT 1 FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanNewUser'",
      databaseName: databaseName,
    );
    if (userCheck.isNotEmpty) {
      throw const DatabaseException('User already exists');
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
      throw const DatabaseException('Only ADMIN can update users');
    }

    final cleanTarget = _quote(targetUsername);
    final normalizedRole = role.toUpperCase().trim();
    if (normalizedRole != 'USER' && normalizedRole != 'REPORT') {
      throw const DatabaseException('Role must be USER or REPORT');
    }

    final userCheck = await query(
      "SELECT 1 FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanTarget' AND ISNULL(ROLE, 'USER') <> 'ADMIN'",
      databaseName: databaseName,
    );
    if (userCheck.isEmpty) {
      throw const DatabaseException('Target user not found');
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
      throw const DatabaseException('You cannot delete your own account');
    }

    final cleanRequester = _quote(requesterUsername);
    final reqResults = await query(
      "SELECT ROLE FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanRequester'",
      databaseName: databaseName,
    );
    if (reqResults.isEmpty || reqResults.first['ROLE'] != 'ADMIN') {
      throw const DatabaseException('Only ADMIN can delete users');
    }

    final cleanTarget = _quote(targetUsername);
    final userCheck = await query(
      "SELECT 1 FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanTarget' AND ISNULL(ROLE, 'USER') <> 'ADMIN'",
      databaseName: databaseName,
    );
    if (userCheck.isEmpty) {
      throw const DatabaseException('Target user not found');
    }

    await execute(
      "DELETE FROM dbo.LV_SYS_USER WHERE USERNAME = '$cleanTarget'",
      databaseName: databaseName,
    );
    return {'success': true, 'message': 'User deleted successfully'};
  }

  Future<List<Map<String, dynamic>>> getLeaveTypes(String databaseName) {
    return query(
      "SELECT LV_CODE AS lvCode, LV_DESC AS lvDesc, LV_EVENT_CODE AS lvEventCode, IS_LEAVE AS isLeave, DAY_ AS day, LV_DAY_PORTION_CODE AS lvDayPortionCode FROM dbo.LV_TYPE WHERE LV_EVENT_CODE = 'LEAVE' ORDER BY LV_CODE",
      databaseName: databaseName,
    );
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
    if (list.isEmpty) throw const DatabaseException('No records to add.');

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
    if (list.isEmpty) throw const DatabaseException('No records to add.');

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
    return {
      'success': true,
      'message':
          'Successfully added ${list.length} leave records in database $database',
    };
  }
}
