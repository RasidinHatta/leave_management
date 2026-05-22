CREATE OR ALTER PROCEDURE dbo.sp_ValidateLeaveUser
(
    @Username VARCHAR(14),
    @Password VARCHAR(40)
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT USERNAME, PASSWD 
    FROM dbo.LV_SYS_USER 
    WHERE USERNAME = @Username AND PASSWD = @Password;
END;
GO
