CREATE OR ALTER PROCEDURE dbo.sp_AddBringForwardLeave
(
    @EMP_CODE varchar(50),
    @DAY_     decimal(18,2),
    @REMARK   varchar(255) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.[LV_RECORDS]
    (
        EMP_CODE,
        LV_DATE,
        LV_CODE,
        DAY_,
        LV_APP_DATE,
        REMARK,
        LV_EVENT_CODE,
        SYSTEM_CODE
    )
    VALUES
    (
        @EMP_CODE,
        DATEFROMPARTS(YEAR(GETDATE()), 1, 1),
        'BF(AL)',
        @DAY_,
        GETDATE(),
        @REMARK,
        'BRINGFORWARD',
        'LEAVE'
    );
END;
GO
