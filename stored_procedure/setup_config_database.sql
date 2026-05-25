-- =============================================================================
-- setup_config_database.sql
-- HR Report Automation — Central Configuration Database
-- =============================================================================
-- Run this script ONCE on the SQL Server to create the config store.
-- =============================================================================

USE master;
GO

-- ------------------------------------------------------------
-- 1. Create the config database (skip if already exists)
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT name FROM sys.databases WHERE name = N'HR_REPORT_CONFIG'
)
BEGIN
    CREATE DATABASE HR_REPORT_CONFIG;
    PRINT 'Database HR_REPORT_CONFIG created.';
END
ELSE
BEGIN
    PRINT 'Database HR_REPORT_CONFIG already exists — skipping creation.';
END
GO

USE HR_REPORT_CONFIG;
GO

-- ------------------------------------------------------------
-- 2. report_targets  — one row per database to report on
-- ------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'report_targets')
BEGIN
    DROP TABLE dbo.report_targets;
END

CREATE TABLE dbo.report_targets (
    id              INT           IDENTITY(1,1) PRIMARY KEY,
    database_name   NVARCHAR(100) NOT NULL UNIQUE,   -- e.g. MYPAY_LCO
    display_name    NVARCHAR(200) NOT NULL,           -- e.g. "MyPay LCO (Main)"
    
    -- SMTP Configuration
    smtp_server     NVARCHAR(100) NOT NULL DEFAULT 'mail.smartouch.com.my',
    smtp_port       INT           NOT NULL DEFAULT 587,
    email_user      NVARCHAR(100) NOT NULL,
    email_password  NVARCHAR(100) NOT NULL,
    email_use_tls   BIT           NOT NULL DEFAULT 1,

    -- Recipients
    to_emails       NVARCHAR(MAX) NOT NULL,           -- comma-separated TO
    cc_emails       NVARCHAR(MAX) NULL,               -- comma-separated CC (optional)
    
    is_active       BIT           NOT NULL DEFAULT 1,
    created_at      DATETIME      NOT NULL DEFAULT GETDATE(),
    updated_at      DATETIME      NOT NULL DEFAULT GETDATE()
);
PRINT 'Table dbo.report_targets created.';
GO

-- ------------------------------------------------------------
-- 3. Trigger to auto-update updated_at on every UPDATE
-- ------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_report_targets_updated_at')
BEGIN
    DROP TRIGGER dbo.trg_report_targets_updated_at;
END
GO

EXEC sp_executesql N'
CREATE TRIGGER dbo.trg_report_targets_updated_at
ON  dbo.report_targets
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.report_targets
    SET    updated_at = GETDATE()
    FROM   dbo.report_targets rt
    INNER JOIN inserted i ON rt.id = i.id;
END';
PRINT 'Trigger trg_report_targets_updated_at created.';
GO

-- ------------------------------------------------------------
-- 4. Seed initial data
-- ------------------------------------------------------------
INSERT INTO dbo.report_targets 
    (database_name, display_name, smtp_server, smtp_port, email_user, email_password, email_use_tls, to_emails, cc_emails, is_active)
VALUES 
    (
        'MYPAY_OTHER',
        'MyPay Other Branch',
        'mail.smartouch.com.my',
        587,
        'rasidin@smartouch.com.my',
        'rasidin*9903',
        1,
        'rasidin@smartouch.com.my',
        'rasidinhatta8@gmail.com',
        1
    );
PRINT 'Seed data inserted.';
GO

-- ------------------------------------------------------------
-- 5. SYS_USER — stores user credentials for dashboard login
-- ------------------------------------------------------------
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'SYS_USER')
BEGIN
    DROP TABLE dbo.SYS_USER;
END

CREATE TABLE [dbo].[SYS_USER](
    [USERNAME] [varchar](14) NOT NULL PRIMARY KEY,
    [PASSWD] [varchar](40) NULL
);
PRINT 'Table dbo.SYS_USER created.';
GO

INSERT INTO dbo.SYS_USER (USERNAME, PASSWD)
VALUES ('SUPER', '39903');
PRINT 'Default user SUPER created.';
GO

-- ------------------------------------------------------------
-- 6. Verify
-- ------------------------------------------------------------
SELECT id, database_name, display_name, smtp_server, to_emails, is_active 
FROM   dbo.report_targets
ORDER  BY id;
GO

PRINT '=== Setup complete. HR_REPORT_CONFIG is ready. ===';
GO
