CREATE OR ALTER PROCEDURE [dbo].[sp_AddLeaveRecords_Bulk]
(
    @List dbo.LeaveImportList READONLY
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        ------------------------------------------------------------
        -- 1. Validate leave code
        ------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM @List L
            LEFT JOIN dbo.[LV_TYPE] T
                ON T.LV_CODE = L.LV_CODE
               AND T.LV_EVENT_CODE = 'LEAVE'
            WHERE T.LV_CODE IS NULL
        )
        BEGIN
            THROW 50001, 'Invalid leave code found. Please check LV_TYPE setup.', 1;
        END;

        ------------------------------------------------------------
        -- 2. Prevent duplicate leave record
        ------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM @List L
            INNER JOIN dbo.[LV_RECORDS] R
                ON R.EMP_CODE = L.EMP_CODE
               AND R.LV_DATE = L.LV_DATE
               AND R.LV_CODE = L.LV_CODE
               AND R.LV_EVENT_CODE = 'LEAVE'
        )
        BEGIN
            THROW 50003, 'Leave record already exists in LV_RECORDS.', 1;
        END;

        ------------------------------------------------------------
        -- 3. Store inserted leave records
        ------------------------------------------------------------
        DECLARE @InsertedLeave TABLE
        (
            EMP_CODE varchar(50),
            LV_DATE  date,
            LV_CODE  varchar(50),
            DAY_     decimal(18,2)
        );

        ------------------------------------------------------------
        -- 4. Insert into LV_RECORDS
        ------------------------------------------------------------
        INSERT INTO dbo.[LV_RECORDS]
        (
            EMP_CODE,
            LV_DATE,
            LV_CODE,
            DAY_,
            LV_APP_DATE,
            REMARK,
            LV_EVENT_CODE,
            LV_DAY_PORTION_CODE,
            SYSTEM_CODE
        )
        OUTPUT
            inserted.EMP_CODE,
            inserted.LV_DATE,
            inserted.LV_CODE,
            inserted.DAY_
        INTO @InsertedLeave
        SELECT
            L.EMP_CODE,
            L.LV_DATE,
            L.LV_CODE,
            ISNULL(T.DAY_, 1),
            GETDATE(),
            L.REMARK,
            'LEAVE',
            T.LV_DAY_PORTION_CODE,
            'ELEAVE'
        FROM @List L
        INNER JOIN dbo.[LV_TYPE] T
            ON T.LV_CODE = L.LV_CODE
           AND T.LV_EVENT_CODE = 'LEAVE';

        ------------------------------------------------------------
        -- 5. Update LV_SUMMARY
        --    Use LV_DATE month, not LV_APP_DATE month.
        --    Leave in January inserted in May still updates Jan-Dec.
        ------------------------------------------------------------
        ;WITH MonthlyLeaveTaken AS
        (
            SELECT
                EMP_CODE,
                YEAR(LV_DATE) AS YEAR_,
                MONTH(LV_DATE) AS MONTH_,

                CASE 
                    WHEN LV_CODE IN ('FHA', 'SHA', 'D-01-Y') THEN 'AL'
                    WHEN LV_CODE IN ('FCP', 'SCP') THEN 'CPL'
                    WHEN LV_CODE IN ('FEL', 'SEL') THEN 'EL'
                    WHEN LV_CODE IN ('FML', 'SML') THEN 'ML'
                    WHEN LV_CODE IN ('FSD', 'SSD') THEN 'STD'
                    WHEN LV_CODE IN ('FUL', 'SUL') THEN 'UL'
                    ELSE LV_CODE
                END AS LV_GROUP_CODE,

                SUM(DAY_) AS TAKEN_DAY
            FROM @InsertedLeave
            GROUP BY
                EMP_CODE,
                YEAR(LV_DATE),
                MONTH(LV_DATE),
                CASE 
                    WHEN LV_CODE IN ('FHA', 'SHA', 'D-01-Y') THEN 'AL'
                    WHEN LV_CODE IN ('FCP', 'SCP') THEN 'CPL'
                    WHEN LV_CODE IN ('FEL', 'SEL') THEN 'EL'
                    WHEN LV_CODE IN ('FML', 'SML') THEN 'ML'
                    WHEN LV_CODE IN ('FSD', 'SSD') THEN 'STD'
                    WHEN LV_CODE IN ('FUL', 'SUL') THEN 'UL'
                    ELSE LV_CODE
                END
        ),
        SummaryUpdate AS
        (
            SELECT
                S.EMP_CODE,
                S.YEAR_,
                S.MONTH_,
                S.LV_GROUP_CODE,
                SUM(L.TAKEN_DAY) AS TAKEN_DAY
            FROM dbo.[LV_SUMMARY] S
            INNER JOIN MonthlyLeaveTaken L
                ON S.EMP_CODE = L.EMP_CODE
               AND S.YEAR_ = L.YEAR_
               AND S.MONTH_ >= L.MONTH_
               AND S.LV_GROUP_CODE = L.LV_GROUP_CODE
            GROUP BY
                S.EMP_CODE,
                S.YEAR_,
                S.MONTH_,
                S.LV_GROUP_CODE
        )
        UPDATE S
        SET
            S.TAKEN = ISNULL(S.TAKEN, 0) + U.TAKEN_DAY,

            S.YTD_TAKEN = ISNULL(S.YTD_TAKEN, 0) + U.TAKEN_DAY,

            S.BAL =
                ISNULL(S.ENT, 0)
              + ISNULL(S.BF, 0)
              + ISNULL(S.CR, 0)
              - ISNULL(S.BURN, 0)
              - (ISNULL(S.TAKEN, 0) + U.TAKEN_DAY)
              - ISNULL(S.ENCASH, 0)
              - ISNULL(S.FORFEIT, 0),

            S.YTD_BAL =
                ISNULL(S.YTD, 0)
              - ISNULL(S.YTD_BURN, 0)
              - (ISNULL(S.YTD_TAKEN, 0) + U.TAKEN_DAY)
              - ISNULL(S.YTD_ENCASH, 0)
              - ISNULL(S.YTD_FORFEIT, 0),

            S.BAL_YEAR =
                ISNULL(S.ENT, 0)
              + ISNULL(S.BF, 0)
              + ISNULL(S.CR, 0)
              - ISNULL(S.BURN, 0)
              - (ISNULL(S.TAKEN, 0) + U.TAKEN_DAY)
              - ISNULL(S.ENCASH, 0)
              - ISNULL(S.FORFEIT, 0)
        FROM dbo.[LV_SUMMARY] S
        INNER JOIN SummaryUpdate U
            ON S.EMP_CODE = U.EMP_CODE
           AND S.YEAR_ = U.YEAR_
           AND S.MONTH_ = U.MONTH_
           AND S.LV_GROUP_CODE = U.LV_GROUP_CODE;

        IF @@ROWCOUNT = 0
        BEGIN
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
