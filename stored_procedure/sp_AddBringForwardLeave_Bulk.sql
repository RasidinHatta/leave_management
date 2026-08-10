DROP PROCEDURE IF EXISTS dbo.sp_AddBringForwardLeave_Bulk;
GO

DROP TYPE IF EXISTS dbo.BringForwardLeaveList;
GO

CREATE TYPE dbo.BringForwardLeaveList AS TABLE
(
    EMP_CODE varchar(50) NOT NULL,
    BF_DAY   decimal(18,2) NULL,
    CR_DAY   decimal(18,2) NULL
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
        THROW 50001, 'Month must be between 1 and 12.', 1;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @LeaveList TABLE
        (
            EMP_CODE varchar(50) NOT NULL,
            BF_DAY decimal(18,2) NULL,
            CR_DAY decimal(18,2) NULL
        );

        INSERT INTO @LeaveList (EMP_CODE, BF_DAY, CR_DAY)
        SELECT EMP_CODE, SUM(BF_DAY), SUM(CR_DAY)
        FROM @List
        GROUP BY EMP_CODE;

        IF NOT EXISTS (SELECT 1 FROM @LeaveList WHERE BF_DAY IS NOT NULL OR CR_DAY IS NOT NULL)
            THROW 50004, 'No bring forward or credit leave records were provided for import.', 1;

        ------------------------------------------------------------
        -- Replace/insert BF(AL) only when a BF value was submitted.
        ------------------------------------------------------------
        UPDATE R
        SET R.DAY_ = L.BF_DAY,
            R.LV_APP_DATE = GETDATE(),
            R.REMARK = CONCAT('Bringforward from year ', @Year - 1, ', System Generate (BF).'),
            R.LV_EVENT_CODE = 'BRINGFORWARD',
            R.SYSTEM_CODE = 'SMARTLMS'
        FROM dbo.LV_RECORDS R
        INNER JOIN @LeaveList L ON L.EMP_CODE = R.EMP_CODE
        WHERE L.BF_DAY IS NOT NULL
          AND YEAR(R.LV_DATE) = @Year
          AND R.LV_CODE = 'BF(AL)';

        INSERT INTO dbo.LV_RECORDS
            (EMP_CODE, LV_DATE, LV_CODE, DAY_, LV_APP_DATE, REMARK, LV_EVENT_CODE, SYSTEM_CODE)
        SELECT L.EMP_CODE, DATEFROMPARTS(@Year, 1, 1), 'BF(AL)', L.BF_DAY,
               GETDATE(), CONCAT('Bringforward from year ', @Year - 1, ', System Generate (BF).'),
               'BRINGFORWARD', 'SMARTLMS'
        FROM @LeaveList L
        WHERE L.BF_DAY IS NOT NULL
          AND NOT EXISTS
          (
              SELECT 1 FROM dbo.LV_RECORDS R
              WHERE R.EMP_CODE = L.EMP_CODE
                AND YEAR(R.LV_DATE) = @Year
                AND R.LV_CODE = 'BF(AL)'
          );

        ------------------------------------------------------------
        -- CR(AL) follows the same replace/insert logic as BF(AL).
        ------------------------------------------------------------
        UPDATE R
        SET R.DAY_ = L.CR_DAY,
            R.LV_APP_DATE = GETDATE(),
            R.REMARK = CONCAT('Credit leave for year ', @Year, ', System Generate (CR).'),
            R.LV_EVENT_CODE = 'CREDIT',
            R.SYSTEM_CODE = 'SMARTLMS'
        FROM dbo.LV_RECORDS R
        INNER JOIN @LeaveList L ON L.EMP_CODE = R.EMP_CODE
        WHERE L.CR_DAY IS NOT NULL
          AND YEAR(R.LV_DATE) = @Year
          AND R.LV_CODE = 'CR(AL)';

        INSERT INTO dbo.LV_RECORDS
            (EMP_CODE, LV_DATE, LV_CODE, DAY_, LV_APP_DATE, REMARK, LV_EVENT_CODE, SYSTEM_CODE)
        SELECT L.EMP_CODE, DATEFROMPARTS(@Year, 1, 1), 'CR(AL)', L.CR_DAY,
               GETDATE(), CONCAT('Credit leave for year ', @Year, ', System Generate (CR).'),
               'CREDIT', 'SMARTLMS'
        FROM @LeaveList L
        WHERE L.CR_DAY IS NOT NULL
          AND NOT EXISTS
          (
              SELECT 1 FROM dbo.LV_RECORDS R
              WHERE R.EMP_CODE = L.EMP_CODE
                AND YEAR(R.LV_DATE) = @Year
                AND R.LV_CODE = 'CR(AL)'
          );

        ;WITH LeaveCreditsFromRecords AS
        (
            SELECT
                R.EMP_CODE,
                YEAR(R.LV_DATE) AS YEAR_,
                SUM(CASE WHEN R.LV_CODE = 'BF(AL)' THEN ISNULL(R.DAY_, 0) ELSE 0 END) AS BF_DAY,
                SUM(CASE WHEN R.LV_CODE = 'CR(AL)' THEN ISNULL(R.DAY_, 0) ELSE 0 END) AS CR_DAY
            FROM dbo.LV_RECORDS R
            INNER JOIN @LeaveList L ON L.EMP_CODE = R.EMP_CODE
            WHERE YEAR(R.LV_DATE) = @Year
              AND R.LV_CODE IN ('BF(AL)', 'CR(AL)')
            GROUP BY R.EMP_CODE, YEAR(R.LV_DATE)
        )
        UPDATE S
        SET
            S.BF = C.BF_DAY,
            S.CR = C.CR_DAY,
            S.YTD_BF = C.BF_DAY,
            S.YTD_CR = C.CR_DAY,
            S.YTD = ISNULL(S.YTD, 0)
                  - ISNULL(S.YTD_BF, 0)
                  - ISNULL(S.YTD_CR, 0)
                  + C.BF_DAY
                  + C.CR_DAY,
            S.BAL = ISNULL(S.ENT, 0) + C.BF_DAY + C.CR_DAY
                  - ISNULL(S.BURN, 0) - ISNULL(S.TAKEN, 0)
                  - ISNULL(S.ENCASH, 0) - ISNULL(S.FORFEIT, 0),
            S.YTD_BAL = ISNULL(S.YTD, 0)
                      - ISNULL(S.YTD_BF, 0) - ISNULL(S.YTD_CR, 0)
                      + C.BF_DAY + C.CR_DAY
                      - ISNULL(S.YTD_BURN, 0) - ISNULL(S.YTD_TAKEN, 0)
                      - ISNULL(S.YTD_ENCASH, 0) - ISNULL(S.YTD_FORFEIT, 0),
            S.BAL_YEAR = ISNULL(S.ENT, 0) + C.BF_DAY + C.CR_DAY
                       - ISNULL(S.BURN, 0) - ISNULL(S.TAKEN, 0)
                       - ISNULL(S.ENCASH, 0) - ISNULL(S.FORFEIT, 0)
        FROM dbo.LV_SUMMARY S
        INNER JOIN LeaveCreditsFromRecords C
            ON S.EMP_CODE = C.EMP_CODE AND S.YEAR_ = C.YEAR_
        WHERE S.YEAR_ = @Year
          AND S.MONTH_ BETWEEN 1 AND 12
          AND S.LV_GROUP_CODE = 'AL';

        DECLARE @UpdatedSummaryRows int = @@ROWCOUNT;

        COMMIT;

        SELECT (SELECT COUNT(*) FROM @LeaveList) AS affectedRecordCount,
               @UpdatedSummaryRows AS updatedSummaryRows;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
