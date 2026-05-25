SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID(N'[dbo].[sp_AddLeaveRecords_Bulk]', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_AddLeaveRecords_Bulk]
GO

CREATE PROCEDURE [dbo].[sp_AddLeaveRecords_Bulk]
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
        -- 2. Prevent duplicate same leave code inside import list
        --    Example: same staff same date FHA + FHA not allowed
        ------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM @List L
            GROUP BY
                L.EMP_CODE,
                L.LV_DATE,
                L.LV_CODE
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 50004, 'Import list contains duplicate leave code for the same employee and date.', 1;
        END;

        ------------------------------------------------------------
        -- 3. Prevent duplicate same leave code in LV_RECORDS
        --    Example: FHA already exists, cannot insert FHA again
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
            THROW 50003, 'Same leave code already exists for this employee on the same date.', 1;
        END;

        ------------------------------------------------------------
        -- 4. Prevent total leave day on same employee/date exceed 1 day
        --    Allow half day + half day only when total <= 1.00
        ------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM
            (
                SELECT
                    L.EMP_CODE,
                    L.LV_DATE,
                    SUM(ISNULL(T.DAY_, 1)) AS NEW_DAY
                FROM @List L
                INNER JOIN dbo.[LV_TYPE] T
                    ON T.LV_CODE = L.LV_CODE
                   AND T.LV_EVENT_CODE = 'LEAVE'
                GROUP BY
                    L.EMP_CODE,
                    L.LV_DATE
            ) N
            LEFT JOIN
            (
                SELECT
                    R.EMP_CODE,
                    R.LV_DATE,
                    SUM(ISNULL(R.DAY_, 0)) AS EXISTING_DAY
                FROM dbo.[LV_RECORDS] R
                WHERE R.LV_EVENT_CODE = 'LEAVE'
                GROUP BY
                    R.EMP_CODE,
                    R.LV_DATE
            ) E
                ON E.EMP_CODE = N.EMP_CODE
               AND E.LV_DATE = N.LV_DATE
            WHERE ISNULL(E.EXISTING_DAY, 0) + ISNULL(N.NEW_DAY, 0) > 1.00
        )
        BEGIN
            THROW 50005, 'Total leave day for the same employee and date cannot exceed 1 day.', 1;
        END;

        ------------------------------------------------------------
        -- 4A. Prevent duplicate half-day portion inside import list
        --     Example:
        --     FHA + FML = not allowed because both are First Half
        --     SHA + SML = not allowed because both are Second Half
        ------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM
            (
                SELECT
                    L.EMP_CODE,
                    L.LV_DATE,
                    T.LV_DAY_PORTION_CODE
                FROM @List L
                INNER JOIN dbo.[LV_TYPE] T
                    ON T.LV_CODE = L.LV_CODE
                   AND T.LV_EVENT_CODE = 'LEAVE'
                WHERE ISNULL(T.DAY_, 1) < 1
                  AND ISNULL(T.LV_DAY_PORTION_CODE, '') <> ''
            ) X
            GROUP BY
                X.EMP_CODE,
                X.LV_DATE,
                X.LV_DAY_PORTION_CODE
            HAVING COUNT(*) > 1
        )
        BEGIN
            THROW 50006, 'Import list contains duplicate half-day portion for the same employee and date.', 1;
        END;

        ------------------------------------------------------------
        -- 4B. Prevent new leave from using same half-day portion
        --     as existing LV_RECORDS
        --     Example:
        --     Existing FHA, then insert FML = not allowed
        --     Existing FHA, then insert SML = allowed
        ------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM @List L
            INNER JOIN dbo.[LV_TYPE] T
                ON T.LV_CODE = L.LV_CODE
               AND T.LV_EVENT_CODE = 'LEAVE'
            INNER JOIN dbo.[LV_RECORDS] R
                ON R.EMP_CODE = L.EMP_CODE
               AND R.LV_DATE = L.LV_DATE
               AND R.LV_EVENT_CODE = 'LEAVE'
            WHERE ISNULL(T.DAY_, 1) < 1
              AND ISNULL(R.DAY_, 1) < 1
              AND ISNULL(T.LV_DAY_PORTION_CODE, '') <> ''
              AND ISNULL(R.LV_DAY_PORTION_CODE, '') = ISNULL(T.LV_DAY_PORTION_CODE, '')
        )
        BEGIN
            THROW 50007, 'Same half-day portion already exists for this employee on the same date.', 1;
        END;

        ------------------------------------------------------------
        -- 5. Validate LV_SUMMARY exists for mapped leave group
        --    Example:
        --    FHA/SHA/D-01-Y updates AL summary
        --    FML/SML updates ML summary
        ------------------------------------------------------------
        IF EXISTS
        (
            SELECT 1
            FROM
            (
                SELECT
                    L.EMP_CODE,
                    YEAR(L.LV_DATE) AS YEAR_,
                    MONTH(L.LV_DATE) AS MONTH_,

                    CASE 
                        WHEN L.LV_CODE IN ('FHA', 'SHA', 'D-01-Y') THEN 'AL'
                        WHEN L.LV_CODE IN ('FCP', 'SCP') THEN 'CPL'
                        WHEN L.LV_CODE IN ('FEL', 'SEL') THEN 'EL'
                        WHEN L.LV_CODE IN ('FML', 'SML') THEN 'ML'
                        WHEN L.LV_CODE IN ('FSD', 'SSD') THEN 'STD'
                        WHEN L.LV_CODE IN ('FUL', 'SUL') THEN 'UL'
                        ELSE L.LV_CODE
                    END AS LV_GROUP_CODE
                FROM @List L
                GROUP BY
                    L.EMP_CODE,
                    YEAR(L.LV_DATE),
                    MONTH(L.LV_DATE),
                    CASE 
                        WHEN L.LV_CODE IN ('FHA', 'SHA', 'D-01-Y') THEN 'AL'
                        WHEN L.LV_CODE IN ('FCP', 'SCP') THEN 'CPL'
                        WHEN L.LV_CODE IN ('FEL', 'SEL') THEN 'EL'
                        WHEN L.LV_CODE IN ('FML', 'SML') THEN 'ML'
                        WHEN L.LV_CODE IN ('FSD', 'SSD') THEN 'STD'
                        WHEN L.LV_CODE IN ('FUL', 'SUL') THEN 'UL'
                        ELSE L.LV_CODE
                    END
            ) X
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM dbo.[LV_SUMMARY] S
                WHERE S.EMP_CODE = X.EMP_CODE
                  AND S.YEAR_ = X.YEAR_
                  AND S.MONTH_ >= X.MONTH_
                  AND S.LV_GROUP_CODE = X.LV_GROUP_CODE
            )
        )
        BEGIN
            THROW 50002, 'No LV_SUMMARY record found for the mapped leave group. Please initialize employee leave first.', 1;
        END;

        ------------------------------------------------------------
        -- 6. Store inserted leave records
        ------------------------------------------------------------
        DECLARE @InsertedLeave TABLE
        (
            EMP_CODE varchar(50),
            LV_DATE  date,
            LV_CODE  varchar(50),
            DAY_     decimal(18,2)
        );

        ------------------------------------------------------------
        -- 7. Insert into LV_RECORDS
        --    Important:
        --    LV_RECORDS keeps original LV_CODE.
        --    Example: FHA remains FHA, SML remains SML.
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
        -- 8. Update LV_SUMMARY
        --    LV_RECORDS uses actual code: FHA / SHA / FML / SML
        --    LV_SUMMARY uses mapped group: AL / ML
        --    Use LV_DATE month, not LV_APP_DATE month.
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

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;

        THROW;
    END CATCH
END;
GO
