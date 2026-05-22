CREATE OR ALTER PROCEDURE dbo.sp_DailyAttendanceLeaveReport
    @ReportDate date,
    @Office varchar(20) = NULL,
    @Department varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET DATEFIRST 7; -- 1 = Sunday, 7 = Saturday

    ;WITH LeaveRows AS
    (
        SELECT
            R.*,
            DATEADD(DAY,
                -ROW_NUMBER() OVER (
                    PARTITION BY R.EMP_CODE, R.LV_CODE, R.LV_APP_DATE
                    ORDER BY R.LV_DATE
                ),
                CAST(R.LV_DATE AS date)
            ) AS LeaveGroup
        FROM dbo.LV_RECORDS R
        WHERE R.LV_EVENT_CODE = 'LEAVE'
    ),
    LeavePeriods AS
    (
        SELECT
            EMP_CODE,
            LV_CODE,
            LV_APP_DATE,
            REMARK,
            MIN(CAST(LV_DATE AS date)) AS LeaveStartDate,
            MAX(CAST(LV_DATE AS date)) AS LeaveEndDate
        FROM LeaveRows
        GROUP BY
            EMP_CODE,
            LV_CODE,
            LV_APP_DATE,
            REMARK,
            LeaveGroup
    )
    SELECT
        CONVERT(varchar(10), @ReportDate, 103) AS [Date],

        S.EMP_CODE AS [Employee Code],
        S.EMP_NAME AS [Name],

        ISNULL(B.BRANCH_DESC, S.BRANCH_CODE) AS [Office],

        ISNULL(D.DEPT_DESC, S.DEPT_CODE) AS [Department],

        CASE 
            WHEN P.LeaveStartDate = P.LeaveEndDate THEN
                CONVERT(varchar(10), P.LeaveStartDate, 103)
            ELSE
                CONVERT(varchar(10), P.LeaveStartDate, 103)
                + ' - ' +
                CONVERT(varchar(10), P.LeaveEndDate, 103)
        END AS [Period of Leave],

        ISNULL(T.LV_DESC, P.LV_CODE) AS [Leave applied],

        CONVERT(varchar(10), RTW.ResumeDate, 103) AS [Resume to work],

        P.REMARK AS [Remark]

    FROM LeavePeriods P

    INNER JOIN dbo.STAFF S
        ON S.EMP_CODE = P.EMP_CODE

    LEFT JOIN dbo.BRANCH B
        ON B.BRANCH_CODE = S.BRANCH_CODE

    LEFT JOIN dbo.DEPT D
        ON D.DEPT_CODE = S.DEPT_CODE

    LEFT JOIN dbo.LV_TYPE T
        ON T.LV_CODE = P.LV_CODE
       AND T.LV_EVENT_CODE = 'LEAVE'

    OUTER APPLY
    (
        SELECT TOP 1
            X.CheckDate AS ResumeDate
        FROM
        (
            SELECT DATEADD(DAY, V.number, P.LeaveEndDate) AS CheckDate
            FROM master.dbo.spt_values V
            WHERE V.type = 'P'
              AND V.number BETWEEN 1 AND 60
        ) X

        LEFT JOIN dbo.SHIFTCHILD SC
            ON SC.SHIFT_CODE = S.SHIFT_TEAM
           AND SC.SHIFT_DAY = CONVERT(varchar(1), DATEPART(WEEKDAY, X.CheckDate))
           AND SC.SHIFT_DAY IN ('1','2','3','4','5','6','7')

        LEFT JOIN dbo.LV_HOLIDAY_DETAILS HD
            ON HD.LV_HOLIDAY_CODE = S.LV_HOLIDAY_CODE
           AND CAST(HD.DATE_ AS date) = CAST(X.CheckDate AS date)

        WHERE ISNULL(SC.INI_NRL, 0) <> 1
          AND HD.DATE_ IS NULL

        ORDER BY X.CheckDate
    ) RTW

    WHERE @ReportDate BETWEEN P.LeaveStartDate AND P.LeaveEndDate
      AND (@Office IS NULL OR @Office = '' OR S.BRANCH_CODE = @Office)
      AND (@Department IS NULL OR @Department = '' OR S.DEPT_CODE = @Department)

    ORDER BY
        ISNULL(B.BRANCH_DESC, S.BRANCH_CODE),
        ISNULL(D.DEPT_DESC, S.DEPT_CODE),
        S.EMP_NAME;
END;
GO