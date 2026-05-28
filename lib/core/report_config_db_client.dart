import 'package:dart_odbc/dart_odbc.dart';
import 'package:flutter/foundation.dart';

import 'constants.dart';
import 'db_client.dart';
import 'package:leave_management/models/target.dart';

String _emailPasswordPassphrase = 'leave-management-report-config';

class ReportDatabaseOption {
  final String databaseName;
  final int? databaseId;
  final String createDate;
  final String stateDesc;
  final String recoveryModelDesc;

  const ReportDatabaseOption({
    required this.databaseName,
    required this.databaseId,
    required this.createDate,
    required this.stateDesc,
    required this.recoveryModelDesc,
  });
}

class ReportConfigDbClient {
  static final ReportConfigDbClient _instance =
      ReportConfigDbClient._internal();
  factory ReportConfigDbClient() => _instance;
  ReportConfigDbClient._internal();

  final DartOdbc _odbc = DartOdbc();
  bool _isConnected = false;
  bool _schemaReady = false;

  Future<void> ensureConnected() async {
    if (_isConnected) return;

    if (kReportServerName.isEmpty) {
      throw DatabaseException(
        'config.ini must contain Server under [ReportConfig].',
      );
    }

    await _ensureDatabaseExists();
    await _connectConfigDatabase();
  }

  Future<void> _ensureDatabaseExists() async {
    final master = DartOdbc();
    try {
      await master.connectWithConnectionString(
        buildReportOdbcConnectionStringForDatabase('master'),
      );
      await master.execute('''
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'$kReportDatabaseName')
BEGIN
  CREATE DATABASE $kReportDatabaseName;
END
''');
    } catch (e) {
      throw DatabaseException('Unable to prepare $kReportDatabaseName: $e');
    } finally {
      try {
        await master.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _connectConfigDatabase() async {
    if (_isConnected) return;

    try {
      debugPrint(
        'ReportConfigDbClient: Connecting with $kReportDriverName to $kReportServerName / $kReportDatabaseName',
      );
      await _odbc.connectWithConnectionString(
        buildReportOdbcConnectionString(),
      );
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      throw DatabaseException('Report config database connection failed: $e');
    }
  }

  Future<void> ensureSchema() async {
    await ensureConnected();
    if (_schemaReady) return;
    await _ensureSchemaConnected();
    _schemaReady = true;
  }

  Future<void> _ensureSchemaConnected() async {
    try {
      await _odbc.execute('''
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'report_targets')
BEGIN
  CREATE TABLE dbo.report_targets (
    id              INT           IDENTITY(1,1) PRIMARY KEY,
    database_name   NVARCHAR(100) NOT NULL UNIQUE,
    display_name    NVARCHAR(200) NOT NULL,
    smtp_server     NVARCHAR(100) NOT NULL DEFAULT 'mail.smartouch.com.my',
    smtp_port       INT           NOT NULL DEFAULT 587,
    email_user      NVARCHAR(100) NOT NULL,
    email_password  VARBINARY(MAX) NOT NULL,
    email_use_tls   BIT           NOT NULL DEFAULT 1,
    to_emails       NVARCHAR(MAX) NOT NULL,
    cc_emails       NVARCHAR(MAX) NULL,
    is_active       BIT           NOT NULL DEFAULT 1,
    created_at      DATETIME      NOT NULL DEFAULT GETDATE(),
    updated_at      DATETIME      NOT NULL DEFAULT GETDATE()
  );
END
''');

      await _odbc.execute('''
IF EXISTS (
  SELECT 1
  FROM sys.columns
  WHERE object_id = OBJECT_ID('dbo.report_targets')
    AND name = 'email_password'
    AND system_type_id <> 165
)
BEGIN
  IF COL_LENGTH('dbo.report_targets', 'email_password_encrypted') IS NULL
  BEGIN
    ALTER TABLE dbo.report_targets ADD email_password_encrypted VARBINARY(MAX) NULL;
  END

  EXEC sp_executesql N'
    UPDATE dbo.report_targets
    SET email_password_encrypted =
      ENCRYPTBYPASSPHRASE(
        N''$_emailPasswordPassphrase'',
        CONVERT(NVARCHAR(4000), email_password)
      );
  ';

  ALTER TABLE dbo.report_targets DROP COLUMN email_password;

  EXEC sp_rename
    'dbo.report_targets.email_password_encrypted',
    'email_password',
    'COLUMN';

  ALTER TABLE dbo.report_targets ALTER COLUMN email_password VARBINARY(MAX) NOT NULL;
END
''');

      await _odbc.execute('''
CREATE OR ALTER TRIGGER dbo.trg_report_targets_updated_at
ON dbo.report_targets
AFTER UPDATE
AS
BEGIN
  SET NOCOUNT ON;
  UPDATE dbo.report_targets
  SET updated_at = GETDATE()
  FROM dbo.report_targets rt
  INNER JOIN inserted i ON rt.id = i.id;
END
''');

      await _odbc.execute('''
CREATE OR ALTER PROCEDURE dbo.sp_AddReportTarget
  @DatabaseName   NVARCHAR(100),
  @DisplayName    NVARCHAR(200),
  @SmtpServer     NVARCHAR(100) = 'mail.smartouch.com.my',
  @SmtpPort       INT = 587,
  @EmailUser      NVARCHAR(100),
  @EmailPassword  NVARCHAR(4000),
  @EmailUseTls    BIT = 1,
  @ToEmails       NVARCHAR(MAX),
  @CcEmails       NVARCHAR(MAX) = NULL,
  @IsActive       BIT = 1
AS
BEGIN
  SET NOCOUNT ON;

  IF EXISTS (SELECT 1 FROM dbo.report_targets WHERE database_name = @DatabaseName)
  BEGIN
    RAISERROR('Target with this database name already exists.', 16, 1);
    RETURN;
  END

  INSERT INTO dbo.report_targets (
    database_name,
    display_name,
    smtp_server,
    smtp_port,
    email_user,
    email_password,
    email_use_tls,
    to_emails,
    cc_emails,
    is_active,
    created_at,
    updated_at
  )
  VALUES (
    @DatabaseName,
    @DisplayName,
    @SmtpServer,
    @SmtpPort,
    @EmailUser,
    ENCRYPTBYPASSPHRASE(N'$_emailPasswordPassphrase', @EmailPassword),
    @EmailUseTls,
    @ToEmails,
    @CcEmails,
    @IsActive,
    GETDATE(),
    GETDATE()
  );
END
''');

      await _odbc.execute('''
CREATE OR ALTER PROCEDURE dbo.sp_EditReportTarget
  @DatabaseName   NVARCHAR(100),
  @DisplayName    NVARCHAR(200) = NULL,
  @SmtpServer     NVARCHAR(100) = NULL,
  @SmtpPort       INT = NULL,
  @EmailUser      NVARCHAR(100) = NULL,
  @EmailPassword  NVARCHAR(4000) = NULL,
  @EmailUseTls    BIT = NULL,
  @ToEmails       NVARCHAR(MAX) = NULL,
  @CcEmails       NVARCHAR(MAX) = NULL,
  @IsActive       BIT = NULL
AS
BEGIN
  SET NOCOUNT ON;

  IF NOT EXISTS (SELECT 1 FROM dbo.report_targets WHERE database_name = @DatabaseName)
  BEGIN
    RAISERROR('Target with this database name does not exist.', 16, 1);
    RETURN;
  END

  UPDATE dbo.report_targets
  SET
    display_name   = ISNULL(@DisplayName, display_name),
    smtp_server    = ISNULL(@SmtpServer, smtp_server),
    smtp_port      = ISNULL(@SmtpPort, smtp_port),
    email_user     = ISNULL(@EmailUser, email_user),
    email_password = CASE
      WHEN @EmailPassword IS NULL THEN email_password
      ELSE ENCRYPTBYPASSPHRASE(N'$_emailPasswordPassphrase', @EmailPassword)
    END,
    email_use_tls  = ISNULL(@EmailUseTls, email_use_tls),
    to_emails      = ISNULL(@ToEmails, to_emails),
    cc_emails      = ISNULL(@CcEmails, cc_emails),
    is_active      = ISNULL(@IsActive, is_active),
    updated_at     = GETDATE()
  WHERE database_name = @DatabaseName;
END
''');
    } catch (e) {
      throw DatabaseException(
        'Report config schema/procedure setup failed: $e',
      );
    }
  }

  Future<List<Map<String, dynamic>>> query(String sql) async {
    await ensureSchema();
    try {
      return _odbc.execute(sql);
    } catch (e) {
      throw DatabaseException('Report config query failed: $e');
    }
  }

  Future<void> execute(String sql) async {
    await ensureSchema();
    try {
      await _odbc.execute(sql);
    } catch (e) {
      throw DatabaseException('Report config command failed: $e');
    }
  }

  String _quote(String value) => value.replaceAll("'", "''");

  String _sqlString(String? value) {
    if (value == null || value.trim().isEmpty) return 'NULL';
    return "N'${_quote(value.trim())}'";
  }

  Future<Map<String, dynamic>> getConnectionInfo() async {
    await ensureConnected();
    try {
      final rows = await _odbc.execute('''
SELECT
  @@SERVERNAME AS serverName,
  DB_NAME() AS databaseName,
  SYSTEM_USER AS loginName
''');
      return rows.isNotEmpty ? rows.first : <String, dynamic>{};
    } catch (e) {
      throw DatabaseException(
        'Report config connection check query failed: $e',
      );
    }
  }

  Future<List<ReportDatabaseOption>> getAvailableReportDatabases() async {
    await ensureConnected();
    try {
      final rows = await _odbc.execute('''
SELECT
    name AS DatabaseName,
    database_id,
    create_date,
    state_desc,
    recovery_model_desc
FROM sys.databases
WHERE name NOT LIKE '%TEST%'
ORDER BY name
''');

      return rows
          .map((row) {
            return ReportDatabaseOption(
              databaseName: row['DatabaseName']?.toString() ?? '',
              databaseId: row['database_id'] is int
                  ? row['database_id'] as int
                  : int.tryParse(row['database_id']?.toString() ?? ''),
              createDate: row['create_date']?.toString() ?? '',
              stateDesc: row['state_desc']?.toString() ?? '',
              recoveryModelDesc: row['recovery_model_desc']?.toString() ?? '',
            );
          })
          .where((db) => db.databaseName.isNotEmpty)
          .toList();
    } catch (e) {
      throw DatabaseException('Unable to load database list: $e');
    }
  }

  Future<List<Target>> getTargets() async {
    await ensureSchema();
    List<Map<String, dynamic>> rows;
    try {
      rows = await _odbc.execute('''
SELECT
  CONVERT(VARCHAR(100), database_name) AS databaseName,
  CONVERT(VARCHAR(200), display_name) AS displayName,
  CONVERT(VARCHAR(100), smtp_server) AS smtpServer,
  smtp_port AS smtpPort,
  CONVERT(VARCHAR(100), email_user) AS emailUser,
  '' AS emailPassword,
  CONVERT(INT, email_use_tls) AS emailUseTls,
  CONVERT(VARCHAR(4000), to_emails) AS toEmails,
  CONVERT(VARCHAR(4000), ISNULL(cc_emails, '')) AS ccEmails,
  CONVERT(INT, is_active) AS isActive
FROM dbo.report_targets
ORDER BY display_name, database_name
''');
    } catch (e) {
      try {
        rows = await _odbc.execute('''
SELECT
  CONVERT(VARCHAR(100), database_name) AS databaseName,
  CONVERT(VARCHAR(200), display_name) AS displayName,
  CONVERT(VARCHAR(100), smtp_server) AS smtpServer,
  smtp_port AS smtpPort,
  CONVERT(VARCHAR(100), email_user) AS emailUser,
  '' AS emailPassword,
  CONVERT(INT, email_use_tls) AS emailUseTls,
  '' AS toEmails,
  '' AS ccEmails,
  CONVERT(INT, is_active) AS isActive
FROM dbo.report_targets
ORDER BY display_name, database_name
''');
      } catch (_) {
        throw DatabaseException(
          'Report config query failed. Connection is OK, but reading dbo.report_targets failed: $e',
        );
      }
    }

    return rows.map(_targetFromRow).toList();
  }

  Target _targetFromRow(Map<String, dynamic> row) {
    bool bit(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      return value.toString() == '1' ||
          value.toString().toLowerCase() == 'true';
    }

    return Target(
      databaseName: row['databaseName']?.toString() ?? '',
      displayName: row['displayName']?.toString() ?? '',
      smtpServer: row['smtpServer']?.toString(),
      smtpPort: row['smtpPort'] is int
          ? row['smtpPort'] as int
          : int.tryParse(row['smtpPort']?.toString() ?? ''),
      emailUser: row['emailUser']?.toString() ?? '',
      emailPassword: row['emailPassword']?.toString() ?? '',
      emailUseTls: bit(row['emailUseTls']),
      toEmails: row['toEmails']?.toString() ?? '',
      ccEmails: row['ccEmails']?.toString(),
      isActive: bit(row['isActive']),
    );
  }

  Future<void> addTarget(Target target) {
    return execute('''
EXEC dbo.sp_AddReportTarget
  @DatabaseName = ${_sqlString(target.databaseName)},
  @DisplayName = ${_sqlString(target.displayName)},
  @SmtpServer = ${_sqlString(target.smtpServer ?? 'mail.smartouch.com.my')},
  @SmtpPort = ${target.smtpPort ?? 587},
  @EmailUser = ${_sqlString(target.emailUser)},
  @EmailPassword = ${_sqlString(target.emailPassword)},
  @EmailUseTls = ${target.emailUseTls ? 1 : 0},
  @ToEmails = ${_sqlString(target.toEmails)},
  @CcEmails = ${_sqlString(target.ccEmails)},
  @IsActive = ${target.isActive ? 1 : 0}
''');
  }

  Future<void> updateTarget(Target target, {bool updatePassword = false}) {
    return execute('''
EXEC dbo.sp_EditReportTarget
  @DatabaseName = ${_sqlString(target.databaseName)},
  @DisplayName = ${_sqlString(target.displayName)},
  @SmtpServer = ${_sqlString(target.smtpServer ?? 'mail.smartouch.com.my')},
  @SmtpPort = ${target.smtpPort ?? 587},
  @EmailUser = ${_sqlString(target.emailUser)},
  @EmailPassword = ${updatePassword ? _sqlString(target.emailPassword) : 'NULL'},
  @EmailUseTls = ${target.emailUseTls ? 1 : 0},
  @ToEmails = ${_sqlString(target.toEmails)},
  @CcEmails = ${_sqlString(target.ccEmails)},
  @IsActive = ${target.isActive ? 1 : 0}
''');
  }

  Future<void> deleteTarget(String databaseName) {
    return execute(
      "DELETE FROM dbo.report_targets WHERE database_name = ${_sqlString(databaseName)}",
    );
  }
}
