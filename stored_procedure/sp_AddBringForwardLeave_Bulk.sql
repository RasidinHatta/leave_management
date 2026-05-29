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
    @Month int, -- Kept for caller compatibility; LV_SUMMARY is updated for all 12 months.
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

        IF NOT EXISTS (SELECT 1 FROM @BFList)
        BEGIN
            THROW 50004, 'No bring forward leave records were provided for import.', 1;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM @BFList B
            OUTER APPLY
            (
                SELECT COUNT(DISTINCT S.MONTH_) AS SUMMARY_MONTHS
                FROM dbo.LV_SUMMARY S
                WHERE S.EMP_CODE = B.EMP_CODE
                  AND S.YEAR_ = @Year
                  AND S.LV_GROUP_CODE = 'AL'
                  AND S.MONTH_ BETWEEN 1 AND 12
            ) M
            WHERE ISNULL(M.SUMMARY_MONTHS, 0) <> 12
        )
        BEGIN
            THROW 50002, 'LV_SUMMARY must contain all 12 months for annual leave. Please initialize employee leave first.', 1;
        END;

        DECLARE @ExpectedSummaryRows int = (SELECT COUNT(*) * 12 FROM @BFList);

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
        FROM @BFList B
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.LV_RECORDS R
            WHERE R.EMP_CODE = B.EMP_CODE
              AND YEAR(R.LV_DATE) = @Year
              AND R.LV_CODE = 'BF(AL)'
              AND R.LV_EVENT_CODE = 'BRINGFORWARD'
        );

        ;WITH BringForwardFromRecords AS
        (
            SELECT
                R.EMP_CODE,
                YEAR(R.LV_DATE) AS YEAR_,
                SUM(ISNULL(R.DAY_, 0)) AS BF_DAY
            FROM dbo.LV_RECORDS R
            INNER JOIN @BFList B
                ON B.EMP_CODE = R.EMP_CODE
            WHERE YEAR(R.LV_DATE) = @Year
              AND R.LV_CODE = 'BF(AL)'
              AND R.LV_EVENT_CODE = 'BRINGFORWARD'
            GROUP BY
                R.EMP_CODE,
                YEAR(R.LV_DATE)
        )
        UPDATE S
        SET
            S.BF = BF.BF_DAY,
            S.YTD_BF = BF.BF_DAY,

            S.YTD =
                ISNULL(S.YTD, 0)
              - ISNULL(S.YTD_BF, 0)
              + ISNULL(BF.BF_DAY, 0),

            S.BAL =
                ISNULL(S.ENT, 0)
              + ISNULL(BF.BF_DAY, 0)
              + ISNULL(S.CR, 0)
              - ISNULL(S.BURN, 0)
              - ISNULL(S.TAKEN, 0)
              - ISNULL(S.ENCASH, 0)
              - ISNULL(S.FORFEIT, 0),

            S.YTD_BAL =
                ISNULL(S.YTD, 0)
              - ISNULL(S.YTD_BF, 0)
              + ISNULL(BF.BF_DAY, 0)
              - ISNULL(S.YTD_BURN, 0)
              - ISNULL(S.YTD_TAKEN, 0)
              - ISNULL(S.YTD_ENCASH, 0)
              - ISNULL(S.YTD_FORFEIT, 0),

            S.BAL_YEAR =
                ISNULL(S.ENT, 0)
              + ISNULL(BF.BF_DAY, 0)
              + ISNULL(S.CR, 0)
              - ISNULL(S.BURN, 0)
              - ISNULL(S.TAKEN, 0)
              - ISNULL(S.ENCASH, 0)
              - ISNULL(S.FORFEIT, 0)
        FROM dbo.LV_SUMMARY S
        INNER JOIN BringForwardFromRecords BF
            ON S.EMP_CODE = BF.EMP_CODE
           AND S.YEAR_ = BF.YEAR_
        WHERE S.YEAR_ = @Year
          AND S.MONTH_ BETWEEN 1 AND 12
          AND S.LV_GROUP_CODE = 'AL';

        DECLARE @UpdatedSummaryRows int = @@ROWCOUNT;

        IF @UpdatedSummaryRows <> @ExpectedSummaryRows
        BEGIN
            ROLLBACK;
            THROW 50002, 'LV_SUMMARY recalculation did not update all 12 annual leave months.', 1;
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
