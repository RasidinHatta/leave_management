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

/// Starting chunk size for sp_AddLeaveRecords_Bulk round trips. Sending
/// thousands of rows as one dynamically-built SQL script risks hitting
/// ODBC/driver text-size limits, and the SP's LV_SUMMARY recalculation
/// re-scans LV_RECORDS on every chunk, so later chunks in a large run get
/// slower as earlier chunks accumulate. If a chunk's EXEC call fails
/// outright it gets bisected into smaller chunks (down to
/// _leaveTakenMinChunkSize) and retried instead of failing the whole thing.
const int _leaveTakenChunkSize = 250;
const int _leaveTakenMinChunkSize = 25;

const List<String> _mainDatabaseStoredProcedureScripts = [
  'sp_AddBringForwardLeave.sql',
  'sp_AddBringForwardLeave_Bulk.sql',
  'sp_AddLeaveRecords_Bulk.sql',
  'sp_DailyAttendanceLeaveReport.sql',
  'sp_ValidateLeaveUser.sql',
];

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

  /// Runs a stored-procedure batch and surfaces server errors.
  /// Plain execute() only reads the first result set, so a THROW fired after
  /// other statements in the SP is silently lost. Wrapping in TRY/CATCH makes
  /// the error come back as a row we can detect and re-throw.
  Future<void> executeSp(String sqlStr, {String? databaseName}) async {
    await ensureConnected(databaseName: databaseName);
    final wrapped =
        'BEGIN TRY\n$sqlStr\nEND TRY\n'
        'BEGIN CATCH\nSELECT ERROR_MESSAGE() AS __errmsg;\nEND CATCH';
    try {
      final rows = await _odbc.execute(wrapped);
      if (rows.isNotEmpty && rows.first.containsKey('__errmsg')) {
        throw DatabaseException(
          rows.first['__errmsg']?.toString() ?? 'Stored procedure failed.',
        );
      }
    } on DatabaseException {
      rethrow;
    } catch (e) {
      throw DatabaseException('SQL execution failed: $e');
    }
  }

  /// Submits [chunk] to sp_AddLeaveRecords_Bulk. The SP validates every
  /// business rule (leave-code validity, duplicates, the 1-day-per-employee-
  /// per-date cap) *before* inserting and throws a specific error if any
  /// row fails or if its own inserted-row count doesn't match what was
  /// requested — so a non-throwing call is trusted as a full success rather
  /// than re-verified with a separate query (an earlier re-verification
  /// step here produced false negatives: rows that were actually committed
  /// still came back "missing" on immediate re-read).
  ///
  /// If the EXEC call does throw — typically one or two genuinely
  /// conflicting rows (e.g. two entries for the same employee/date that
  /// together exceed 1 day) poisoning the whole chunk — and the chunk is
  /// bigger than [_leaveTakenMinChunkSize], it's bisected into two halves
  /// and each retried independently, so the failure narrows down to just
  /// the real offending row(s) with the SP's actual error message instead
  /// of failing every row in the chunk. Appends failed rows (with a
  /// 'reason') to [failures] and returns the number of rows inserted.
  Future<int> _submitLeaveChunk(
    List<Map<String, dynamic>> chunk,
    String database,
    List<Map<String, dynamic>> failures,
  ) async {
    final buffer = StringBuffer();
    buffer.writeln('DECLARE @List dbo.LeaveImportList;');
    for (final item in chunk) {
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

    try {
      await executeSp(buffer.toString(), databaseName: database);
      return chunk.length;
    } catch (e) {
      if (chunk.length > _leaveTakenMinChunkSize) {
        final mid = chunk.length ~/ 2;
        final first = await _submitLeaveChunk(
          chunk.sublist(0, mid),
          database,
          failures,
        );
        final second = await _submitLeaveChunk(
          chunk.sublist(mid),
          database,
          failures,
        );
        return first + second;
      }
      final reason = e is DatabaseException ? e.message : e.toString();
      for (final item in chunk) {
        failures.add({...item, 'reason': reason});
      }
      return 0;
    }
  }

  Future<void> _assertBringForwardRecordsSaved(
    List<Map<String, dynamic>> list,
    String database,
    int year,
  ) async {
    final values = list
        .map((item) {
          final empCode = _quote(item['empCode'].toString());
          final bfDay = item['bfDay'] == null
              ? 'NULL'
              : 'CAST(${double.parse(item['bfDay'].toString())} AS decimal(18,2))';
          final crDay = item['crDay'] == null
              ? 'NULL'
              : 'CAST(${double.parse(item['crDay'].toString())} AS decimal(18,2))';
          return "('$empCode', $bfDay, $crDay)";
        })
        .join(',\n');

    final missingRows = await query('''
SELECT TOP 1
  CAST(V.EMP_CODE AS VARCHAR(50)) AS empCode
FROM
(
  SELECT EMP_CODE, SUM(BF_DAY) AS BF_DAY, SUM(CR_DAY) AS CR_DAY
  FROM (VALUES
$values
  ) I(EMP_CODE, BF_DAY, CR_DAY)
  GROUP BY EMP_CODE
) V
WHERE NOT EXISTS
(
  SELECT 1
  FROM dbo.LV_RECORDS R
  WHERE R.EMP_CODE = V.EMP_CODE
    AND YEAR(R.LV_DATE) = $year
    AND R.LV_CODE = CASE WHEN V.BF_DAY IS NOT NULL THEN 'BF(AL)' ELSE 'CR(AL)' END
    AND R.DAY_ = COALESCE(V.BF_DAY, V.CR_DAY)
)
OR
(
  V.BF_DAY IS NOT NULL AND V.CR_DAY IS NOT NULL AND NOT EXISTS
  (
    SELECT 1
    FROM dbo.LV_RECORDS R
    WHERE R.EMP_CODE = V.EMP_CODE
      AND YEAR(R.LV_DATE) = $year
      AND R.LV_CODE = 'CR(AL)'
      AND R.DAY_ = V.CR_DAY
  )
)
''', databaseName: database);

    if (missingRows.isNotEmpty) {
      throw DatabaseException(
        'Bring forward leave was not saved with the requested value for '
        'employee ${missingRows.first['empCode']} in '
        '$kServerName / $database.',
      );
    }
  }

  /// Returns the emp codes in [list] that are missing from dbo.STAFF (empty if none).
  Future<List<String>> _missingStaffCodes(
    List<Map<String, dynamic>> list,
    String database,
  ) async {
    final empValues = list
        .map((item) => "('${_quote(item['empCode'].toString())}')")
        .toSet()
        .join(',');
    final missing = await query(
      "SELECT V.EMP_CODE FROM (VALUES $empValues) V(EMP_CODE) "
      "WHERE NOT EXISTS (SELECT 1 FROM dbo.STAFF S WHERE S.EMP_CODE = V.EMP_CODE)",
      databaseName: database,
    );
    return missing.map((r) => r['EMP_CODE'].toString()).toList();
  }

  /// Throws "Staff X doesnt exist" if any emp code in [list] is missing from dbo.STAFF.
  Future<void> _assertStaffExist(
    List<Map<String, dynamic>> list,
    String database,
  ) async {
    final missing = await _missingStaffCodes(list, database);
    if (missing.isNotEmpty) {
      throw DatabaseException('Staff ${missing.join(', ')} doesnt exist');
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
                return _mainDatabaseStoredProcedureScripts.any(
                  (scriptName) => scriptName.toLowerCase() == name,
                );
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

    final scripts = <_SqlScript>[];
    for (final name in _mainDatabaseStoredProcedureScripts) {
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
            "IF COL_LENGTH('dbo.LV_SYS_USER', 'ROLE') IS NULL ALTER TABLE dbo.LV_SYS_USER ADD ROLE VARCHAR(20) DEFAULT 'USER'",
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
   OR CAST(LV_CODE AS VARCHAR(50)) IN ('PH', 'OFF', 'RL', 'REST')
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
    required List<Map<String, dynamic>> list,
    bool replaceExisting = false,
  }) async {
    if (list.isEmpty) throw DatabaseException('No records to add.');

    await _assertStaffExist(list, database);

    final existing = await _getExistingBringForwardLeave(
      database: database,
      year: year,
      list: list,
    );
    if (existing.isNotEmpty && !replaceExisting) {
      final codes = existing.map((row) => row['empCode']).join(', ');
      throw DatabaseException(
        'Existing BF found for $codes in $year. Replacement confirmation is required.',
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('DECLARE @List dbo.BringForwardLeaveList;');
    for (final item in list) {
      final empCode = _quote(item['empCode'].toString());
      final bfDay = item['bfDay'] == null
          ? 'NULL'
          : double.parse(item['bfDay'].toString()).toString();
      final crDay = item['crDay'] == null
          ? 'NULL'
          : double.parse(item['crDay'].toString()).toString();
      buffer.writeln(
        "INSERT INTO @List (EMP_CODE, BF_DAY, CR_DAY) VALUES ('$empCode', $bfDay, $crDay);",
      );
    }
    buffer.writeln(
      'EXEC dbo.sp_AddBringForwardLeave_Bulk @Year = $year, @Month = 1, @List = @List;',
    );

    await executeSp(buffer.toString(), databaseName: database);
    await _assertBringForwardRecordsSaved(list, database, year);

    return {
      'success': true,
      'message':
          'Successfully added ${list.length} bring forward/credit leave records in $kServerName / $database',
    };
  }

  Future<List<Map<String, dynamic>>> getExistingBringForwardLeave({
    required String database,
    required int year,
    required List<Map<String, dynamic>> list,
  }) async {
    if (list.isEmpty) return [];
    await _assertStaffExist(list, database);
    return _getExistingBringForwardLeave(
      database: database,
      year: year,
      list: list,
    );
  }

  Future<List<Map<String, dynamic>>> _getExistingBringForwardLeave({
    required String database,
    required int year,
    required List<Map<String, dynamic>> list,
  }) {
    final values = list
        .map((item) {
          final empCode = _quote(item['empCode'].toString());
          final bfDay = item['bfDay'] == null
              ? 'NULL'
              : 'CAST(${double.parse(item['bfDay'].toString())} AS decimal(18,2))';
          final crDay = item['crDay'] == null
              ? 'NULL'
              : 'CAST(${double.parse(item['crDay'].toString())} AS decimal(18,2))';
          return "('$empCode', $bfDay, $crDay)";
        })
        .join(',\n');

    return query('''
WITH Requested AS
(
  SELECT EMP_CODE, SUM(BF_DAY) AS NEW_BF_DAY, SUM(CR_DAY) AS NEW_CR_DAY
  FROM (VALUES
$values
  ) V(EMP_CODE, BF_DAY, CR_DAY)
  GROUP BY EMP_CODE
)
SELECT
  CAST(Q.EMP_CODE AS VARCHAR(50)) AS empCode,
  CAST(MAX(CASE WHEN R.LV_CODE = 'BF(AL)' THEN R.DAY_ END) AS DECIMAL(18,2)) AS currentBfDay,
  CAST(Q.NEW_BF_DAY AS DECIMAL(18,2)) AS newBfDay,
  CAST(MAX(CASE WHEN R.LV_CODE = 'CR(AL)' THEN R.DAY_ END) AS DECIMAL(18,2)) AS currentCrDay,
  CAST(Q.NEW_CR_DAY AS DECIMAL(18,2)) AS newCrDay
FROM Requested Q
INNER JOIN dbo.LV_RECORDS R
  ON R.EMP_CODE = Q.EMP_CODE
 AND YEAR(R.LV_DATE) = $year
 AND ((Q.NEW_BF_DAY IS NOT NULL AND R.LV_CODE = 'BF(AL)')
   OR (Q.NEW_CR_DAY IS NOT NULL AND R.LV_CODE = 'CR(AL)'))
GROUP BY Q.EMP_CODE, Q.NEW_BF_DAY, Q.NEW_CR_DAY
ORDER BY Q.EMP_CODE
''', databaseName: database);
  }

  String _leaveRowKey(Map<String, dynamic> item) {
    final empCode = item['empCode'].toString().trim().toUpperCase();
    final lvDate = item['lvDate'].toString().trim();
    final lvCode = item['lvCode'].toString().trim().toUpperCase();
    return '$empCode|$lvDate|$lvCode';
  }

  /// Adds leave records, skipping rows that fail validation instead of
  /// rejecting the whole batch. Skipped rows are returned under 'failures'
  /// (each with a 'reason') so the caller can report them (e.g. export to
  /// Excel) rather than surfacing one huge aggregate error message.
  ///
  /// [onProgress], if given, is called after each top-level chunk with
  /// (chunkIndex, totalChunks, rowsDone, totalRows) so the caller can show
  /// progress (e.g. "chunk 2 of 12").
  Future<Map<String, dynamic>> addLeaveTaken({
    required String database,
    required List<Map<String, dynamic>> list,
    void Function(int chunkIndex, int totalChunks, int rowsDone, int totalRows)?
    onProgress,
  }) async {
    if (list.isEmpty) throw DatabaseException('No records to add.');

    final failures = <Map<String, dynamic>>[];
    var candidates = <Map<String, dynamic>>[];
    final seenRows = <String>{};

    for (final item in list) {
      if (!seenRows.add(_leaveRowKey(item))) {
        failures.add({...item, 'reason': 'Duplicate row in import file'});
        continue;
      }
      candidates.add(item);
    }

    // Accept ordinary LEAVE-event types plus the operational PH/OFF/RL/REST
    // codes used by Leave Taken. Validate before hitting the bulk procedure so
    // one bad code cannot abort the whole batch.
    if (candidates.isNotEmpty) {
      final distinctCodes = candidates
          .map((item) => item['lvCode'].toString().trim().toUpperCase())
          .toSet();
      final codeValues = distinctCodes.map((c) => "('${_quote(c)}')").join(',');
      final validCodeRows = await query(
        "SELECT V.LV_CODE FROM (VALUES $codeValues) V(LV_CODE) "
        "WHERE EXISTS (SELECT 1 FROM dbo.LV_TYPE T WHERE T.LV_CODE = V.LV_CODE "
        "AND (T.LV_EVENT_CODE = 'LEAVE' OR T.LV_CODE IN ('PH', 'OFF', 'RL', 'REST')))",
        databaseName: database,
      );
      final validCodes = validCodeRows
          .map((r) => r['LV_CODE'].toString().trim().toUpperCase())
          .toSet();
      final invalidCodes = distinctCodes.difference(validCodes);
      if (invalidCodes.isNotEmpty) {
        final remaining = <Map<String, dynamic>>[];
        for (final item in candidates) {
          final lvCode = item['lvCode'].toString().trim().toUpperCase();
          if (invalidCodes.contains(lvCode)) {
            failures.add({
              ...item,
              'reason':
                  'Invalid leave code "$lvCode" is not configured for Leave Taken',
            });
          } else {
            remaining.add(item);
          }
        }
        candidates = remaining;
      }
    }

    if (candidates.isNotEmpty) {
      final values = candidates
          .map((item) {
            final empCode = _quote(item['empCode'].toString());
            final lvDate = _quote(item['lvDate'].toString());
            final lvCode = _quote(item['lvCode'].toString());
            return "('$empCode', CAST('$lvDate' AS date), '$lvCode')";
          })
          .join(',\n');

      final duplicateRows = await query('''
SELECT
  CAST(R.EMP_CODE AS VARCHAR(50)) AS empCode,
  CONVERT(VARCHAR(10), R.LV_DATE, 120) AS lvDate,
  CAST(R.LV_CODE AS VARCHAR(50)) AS lvCode
FROM dbo.LV_RECORDS R
INNER JOIN (VALUES
$values
) V(EMP_CODE, LV_DATE, LV_CODE)
  ON R.EMP_CODE = V.EMP_CODE
 AND CAST(R.LV_DATE AS date) = V.LV_DATE
 AND R.LV_CODE = V.LV_CODE
''', databaseName: database);

      final dupKeys = duplicateRows.map(_leaveRowKey).toSet();
      if (dupKeys.isNotEmpty) {
        final remaining = <Map<String, dynamic>>[];
        for (final item in candidates) {
          if (dupKeys.contains(_leaveRowKey(item))) {
            failures.add({
              ...item,
              'reason':
                  'Leave record already exists for this employee/date/type',
            });
          } else {
            remaining.add(item);
          }
        }
        candidates = remaining;
      }
    }

    if (candidates.isNotEmpty) {
      final missingCodes = (await _missingStaffCodes(
        candidates,
        database,
      )).map((c) => c.trim().toUpperCase()).toSet();
      if (missingCodes.isNotEmpty) {
        final remaining = <Map<String, dynamic>>[];
        for (final item in candidates) {
          final empCode = item['empCode'].toString().trim().toUpperCase();
          if (missingCodes.contains(empCode)) {
            failures.add({...item, 'reason': 'Employee code does not exist'});
          } else {
            remaining.add(item);
          }
        }
        candidates = remaining;
      }
    }

    if (candidates.isEmpty) {
      return {
        'success': false,
        'successCount': 0,
        'failures': failures,
        'message':
            'No leave records were added — all ${failures.length} row(s) failed validation.',
      };
    }

    // Submitting thousands of rows as one giant dynamically-built SQL script
    // (one INSERT line per row) risks hitting ODBC/driver text-size limits,
    // and the SP's LV_SUMMARY recalculation gets slower as LV_RECORDS grows
    // during the run. Submit in fixed-size top-level chunks (so progress
    // stays meaningful) and bisect any chunk whose EXEC call fails outright,
    // so a slow/oversized chunk doesn't take down rows that would otherwise
    // have succeeded.
    var insertedCount = 0;
    var rowsDone = 0;
    final totalChunks = (candidates.length / _leaveTakenChunkSize).ceil();
    var chunkIndex = 0;

    for (
      var start = 0;
      start < candidates.length;
      start += _leaveTakenChunkSize
    ) {
      chunkIndex++;
      final end = (start + _leaveTakenChunkSize < candidates.length)
          ? start + _leaveTakenChunkSize
          : candidates.length;
      final chunk = candidates.sublist(start, end);

      insertedCount += await _submitLeaveChunk(chunk, database, failures);

      rowsDone += chunk.length;
      onProgress?.call(chunkIndex, totalChunks, rowsDone, candidates.length);
    }

    return {
      'success': insertedCount > 0,
      'successCount': insertedCount,
      'failures': failures,
      'message': failures.isEmpty
          ? 'Successfully added $insertedCount leave records in $kServerName / $database'
          : 'Added $insertedCount of ${list.length} leave records in $kServerName / $database. '
                '${failures.length} row(s) failed — see the exported failure report.',
    };
  }
}
