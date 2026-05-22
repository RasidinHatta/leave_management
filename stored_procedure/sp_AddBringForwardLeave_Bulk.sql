DROP PROCEDURE IF EXISTS dbo.sp_AddBringForwardLeave_Bulk;
GO

DROP TYPE IF EXISTS dbo.BringForwardLeaveList;
GO

CREATE TYPE dbo.BringForwardLeaveList AS TABLE
(
    EMP_CODE varchar(50) NOT NULL,
    DAY_     decimal(18,2) NOT NULL
);
GO

CREATE OR ALTER PROCEDURE dbo.sp_AddBringForwardLeave_Bulk
(
    @Year  int,
    @Month int,
    @List  dbo.BringForwardLeaveList READONLY
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Month < 1 OR @Month > 12
    BEGIN
        THROW 50001, 'Month must be between 1 and 12.', 1;
    END;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @BFList TABLE
        (
            EMP_CODE varchar(50) NOT NULL,
            BF_DAY decimal(18,2) NOT NULL
        );

        INSERT INTO @BFList
        SELECT EMP_CODE, SUM(DAY_)
        FROM @List
        GROUP BY EMP_CODE;

        IF EXISTS
        (
            SELECT 1
            FROM @BFList B
            INNER JOIN dbo.LV_RECORDS R
                ON R.EMP_CODE = B.EMP_CODE
               AND YEAR(R.LV_DATE) = @Year
               AND R.LV_CODE = 'BF(AL)'
               AND R.LV_EVENT_CODE = 'BRINGFORWARD'
        )
        BEGIN
            THROW 50003, 'Bring Forward record already exists.', 1;
        END;

        INSERT INTO dbo.LV_RECORDS
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
        SELECT
            B.EMP_CODE,
            DATEFROMPARTS(@Year, 1, 1),
            'BF(AL)',
            B.BF_DAY,
            GETDATE(),
            CONCAT('Annual Leave Bring Forward ', @Year - 1),
            'BRINGFORWARD',
            'LEAVE'
        FROM @BFList B;

        UPDATE S
        SET
            S.BF = B.BF_DAY,
            S.YTD_BF = B.BF_DAY,

            S.YTD =
                ISNULL(S.ENT, 0)
              + ISNULL(B.BF_DAY, 0)
              + ISNULL(S.CR, 0),

            S.BAL =
                ISNULL(S.ENT, 0)
              + ISNULL(B.BF_DAY, 0)
              + ISNULL(S.CR, 0)
              - ISNULL(S.BURN, 0)
              - ISNULL(S.TAKEN, 0)
              - ISNULL(S.ENCASH, 0)
              - ISNULL(S.FORFEIT, 0),

            S.YTD_BAL =
                ISNULL(S.ENT, 0)
              + ISNULL(B.BF_DAY, 0)
              + ISNULL(S.CR, 0)
              - ISNULL(S.YTD_BURN, 0)
              - ISNULL(S.YTD_TAKEN, 0)
              - ISNULL(S.YTD_ENCASH, 0)
              - ISNULL(S.YTD_FORFEIT, 0),

            S.BAL_YEAR =
                ISNULL(S.ENT, 0)
              + ISNULL(B.BF_DAY, 0)
              + ISNULL(S.CR, 0)
              - ISNULL(S.BURN, 0)
              - ISNULL(S.TAKEN, 0)
              - ISNULL(S.ENCASH, 0)
              - ISNULL(S.FORFEIT, 0)
        FROM dbo.LV_SUMMARY S
        INNER JOIN @BFList B
            ON S.EMP_CODE = B.EMP_CODE
        WHERE S.YEAR_ = @Year
          AND S.MONTH_ = @Month
          AND S.LV_GROUP_CODE = 'AL';

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK;
            THROW 50002, 'No LV_SUMMARY record found. Please initialize employee leave first.', 1;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;

        THROW;
    END CATCH
END;
GO
