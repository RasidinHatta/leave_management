USE HR_REPORT_CONFIG;
GO

-- ============================================================================
-- 1. ADD REPORT TARGET
-- ============================================================================
IF OBJECT_ID('dbo.sp_AddReportTarget', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AddReportTarget;
GO

CREATE PROCEDURE dbo.sp_AddReportTarget
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

    -- Check if it already exists
    IF EXISTS (SELECT 1 FROM dbo.report_targets WHERE database_name = @DatabaseName)
    BEGIN
        RAISERROR('Target with database_name ''%s'' already exists.', 16, 1, @DatabaseName);
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
        ENCRYPTBYPASSPHRASE(N'leave-management-report-config', @EmailPassword),
        @EmailUseTls,
        @ToEmails,
        @CcEmails,
        @IsActive,
        GETDATE(),
        GETDATE()
    );

    PRINT 'Successfully added report target: ' + @DatabaseName;
END
GO

-- ============================================================================
-- 2. EDIT REPORT TARGET
-- ============================================================================
IF OBJECT_ID('dbo.sp_EditReportTarget', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_EditReportTarget;
GO

CREATE PROCEDURE dbo.sp_EditReportTarget
    @DatabaseName   NVARCHAR(100), -- Used as identifier
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

    -- Ensure the target exists
    IF NOT EXISTS (SELECT 1 FROM dbo.report_targets WHERE database_name = @DatabaseName)
    BEGIN
        RAISERROR('Target with database_name ''%s'' does not exist.', 16, 1, @DatabaseName);
        RETURN;
    END

    -- Update only provided values
    UPDATE dbo.report_targets
    SET 
        display_name   = ISNULL(@DisplayName, display_name),
        smtp_server    = ISNULL(@SmtpServer, smtp_server),
        smtp_port      = ISNULL(@SmtpPort, smtp_port),
        email_user     = ISNULL(@EmailUser, email_user),
        email_password = CASE
            WHEN @EmailPassword IS NULL THEN email_password
            ELSE ENCRYPTBYPASSPHRASE(N'leave-management-report-config', @EmailPassword)
        END,
        email_use_tls  = ISNULL(@EmailUseTls, email_use_tls),
        to_emails      = ISNULL(@ToEmails, to_emails),
        cc_emails      = ISNULL(@CcEmails, cc_emails),
        is_active      = ISNULL(@IsActive, is_active),
        updated_at     = GETDATE()
    WHERE database_name = @DatabaseName;

    PRINT 'Successfully updated report target: ' + @DatabaseName;
END
GO

/* 
-- ============================================================================
-- EXAMPLE USAGE
-- ============================================================================

-- ADD:
EXEC dbo.sp_AddReportTarget 
    @DatabaseName = 'MYPAY_NEW', 
    @DisplayName = 'New Branch (MYPAY_NEW)', 
    @EmailUser = 'rasidin@smartouch.com.my', 
    @EmailPassword = 'yourpassword', 
    @ToEmails = 'recipient@gmail.com';

-- EDIT:
EXEC dbo.sp_EditReportTarget 
    @DatabaseName = 'MYPAY_NEW', 
    @IsActive = 0, -- Disable it
    @DisplayName = 'New Branch (Deactivated)';

*/
