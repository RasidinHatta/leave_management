# HR Leave Management

Windows desktop application for managing leave operations directly against SQL Server. The app no longer uses an API connection; all database work is performed through ODBC using `config.ini`.

## Main Features

- User login with role-based menus.
- Bring Forward and Credit Leave bulk entry and Excel import/export.
- Leave Taken bulk entry and Excel import/export, with chunked submission and a
  progress indicator for large imports, and a failed-rows Excel report for
  anything that could not be imported (see [Leave Taken Bulk Import](#leave-taken-bulk-import)).
- Main database connection check from `config.ini`.
- Leave Report Config CRUD against the fixed `HR_REPORT_CONFIG` database.
- Manage Users for creating and maintaining `USER` and `REPORT` accounts.
- App appearance settings for font size, dark/light mode, and color palette.

Sample import templates are in [`templates/`](templates/): `Bring_Forward_Template.xlsx`
(sheet `BF`) and `Leave_Taken_Template.xlsx` (sheet `LV`).

## Role Access

| Role | Visible menus |
| --- | --- |
| `ADMIN` | Bring Forward, Leave Taken, DB Targets; plus Leave Report Config and Manage Users when `Admin=1` |
| `USER` | Bring Forward, Leave Taken; plus Leave Report Config and Manage Users when `Admin=1` |
| `REPORT` | Leave Report Config and Manage Users only when `Admin=1` |

`ADMIN` users are hidden from Manage Users. New/editable users are limited to `USER` and `REPORT`.

## Requirements

- Windows 10 or later.
- SQL Server reachable from the client PC.
- ODBC Driver 17 for SQL Server installed on the client PC.
- Flutter SDK only if building from source. End users who download the release zip do not need Flutter.

Download the Microsoft ODBC driver from Microsoft if the target PC does not already have `ODBC Driver 17 for SQL Server`.

## Database Requirements

The app uses two SQL Server connection targets:

- Main leave database from `[DatabaseConfig]`, for example `MYPAY_LCO`.
- Report configuration database `HR_REPORT_CONFIG`, default server `v1soho.com,1500`.

On startup, the app creates or repairs required app users. Stored procedure scripts in `stored_procedure/` are updated on demand from the DB Targets menu by clicking `Update Query`.

For Leave Report Config, use the `Setup DB` button if `HR_REPORT_CONFIG` or `dbo.report_targets` is missing. Email passwords are stored in the `email_password` column and encrypted in SQL Server.

## config.ini

During `flutter run -d windows`, a debug build reads `config.ini` from the
project working directory first. Editing that file and performing a hot restart
reloads the new values. Release builds read `config.ini` from the same folder as
`leave_management.exe`; if it is missing, they fall back to the bundled asset.

Example:

```ini
[DatabaseConfig]
Server=DIN-STT
Database=MYPAY_LCO
Driver=ODBC Driver 17 for SQL Server
Admin=1
```

Notes:

- `[DatabaseConfig]` controls normal leave operations.
- `Admin=1` shows the **Leave Report Config** and **Manage Users** sidebar
  menus. Both menus are hidden when the setting is omitted or set to `0`,
  including for an `ADMIN` login. **DB Targets** remains role-controlled.
- Leave Report Config defaults to `v1soho.com,1500`.
- To use a custom report server, add `[ReportConfig]` with only `Server=SERVER_NAME,PORT`.
- The report config driver always matches `[DatabaseConfig] Driver`.
- The report config database name is **fixed** to `HR_REPORT_CONFIG`. Do not add a `Database=` line under `[ReportConfig]`; the app always uses `HR_REPORT_CONFIG` for this menu.
- If using a custom SQL port, set `Server=SERVER_NAME,PORT`.

## Install From GitHub Release

Use this method for normal users.

1. Open the GitHub repository in a browser.

2. Go to:

   ```text
   Releases
   ```

3. Download the Windows release zip:

   ```text
   leave_management_windows_release.zip
   ```

4. Extract the zip to a local folder, for example:

   ```text
   C:\HR Leave Management
   ```

5. Confirm the extracted folder contains:

   ```text
   leave_management.exe
   setup.bat
   setup.ps1
   config.ini
   flutter_windows.dll
   data\
   stored_procedure\
   templates\
   docs\
   ```

6. To install the app to a local folder, run:

   ```text
   setup.bat
   ```

   The installer asks for an install parent folder. If you enter:

   ```text
   C:\smartouch
   ```

   the app is installed to:

   ```text
   C:\smartouch\SmartLMS
   ```

   It also asks whether to create a desktop shortcut.

7. Edit `config.ini` in the installed folder.

8. Run:

   ```text
   leave_management.exe
   ```

9. On first run, the app connects to the database from `config.ini` and creates or repairs required users.

10. Open DB Targets and click `Update Query` when you need to create or refresh stored procedures from `stored_procedure\`.

Important:

- Keep `config.ini` beside `leave_management.exe`.
- Keep the `data\` folder beside `leave_management.exe`.
- Keep the `stored_procedure\` folder beside `leave_management.exe` so DB Targets `Update Query` can run.
- Keep `templates\` for the current BF/CR and Leave Taken sample workbooks.
- The current user manual is included under `docs\`.
- Do not run the exe directly from inside the zip file. Extract it first.

## Create Release Zip For GitHub

Use this method when preparing a new release package.

1. Set the app version in `pubspec.yaml`:

   ```yaml
   version: 1.0.5+12
   ```

   The part before `+` is the release version. For example, `1.0.5+12` creates a zip ending with `1.0.5`.

2. Build the Windows release:

   ```powershell
   flutter build windows --release
   ```

3. Open the release output:

   ```text
   build\windows\x64\runner\Release
   ```

4. Make sure `config.ini` exists in the same folder as:

   ```text
   leave_management.exe
   ```

5. Edit `config.ini` for the production SQL Server and database.

6. Run:

   ```text
   leave_management.exe
   ```

7. Create a zip from the contents of the `Release` folder:

   ```powershell
   .\tool\zip_windows_release.ps1
   ```

   The script reads the version from `pubspec.yaml` automatically.

   To override the version manually:

   ```powershell
   .\tool\zip_windows_release.ps1 -Version 1.0.5
   ```

   To build and zip in one command:

   ```powershell
   .\tool\zip_windows_release.ps1 -Build
   ```

8. Upload the generated zip from `releases\` to GitHub Releases.

   Example output:

   ```text
   releases\leave_management_windows_release_1.0.1.zip
   ```

Do not commit the full `build\` folder to Git. Flutter build output is ignored by `.gitignore` on purpose.

## Build From Source

From the `leave_management` folder:

```powershell
flutter pub get
flutter analyze
flutter build windows --release
```

After building, copy or update `config.ini` in:

```text
build\windows\x64\runner\Release
```

The release executable follows the `config.ini` in that Release folder.

## Leave Taken Bulk Import

Leave Taken import behaves differently from Bring Forward: instead of
rejecting the whole batch when some rows are invalid, it validates each row
independently and only submits the rows that pass.

- Rows are skipped individually, not batch-wide, for: duplicate rows within
  the import file, rows that already exist in the database, employee codes
  not found in `dbo.STAFF`, and leave codes that are not configured for Leave
  Taken in `dbo.LV_TYPE`. Ordinary `LEAVE` event codes and the operational
  codes `PH`, `OFF`, `RL`, and `REST` are accepted.
- Large imports (thousands of rows) are submitted to
  `sp_AddLeaveRecords_Bulk` in chunks of 250 rows instead of one large SQL
  script, with a live "Processing chunk X of Y" indicator. If a chunk fails
  outright, it is automatically split in half and retried, which narrows a
  failure down to the specific row(s) causing it (for example two entries
  for the same employee and date that together exceed one day of leave)
  instead of failing the entire chunk.
- Any row that could not be imported is written to an Excel file next to the
  failed-rows layout below, saved under `log\` (next to `leave_management.exe`
  in a release build, or the project folder during `flutter run`), named
  `Leave_Import_Failed_<timestamp>.xlsx`. It uses the same columns as the
  Leave Taken import template plus a trailing `failed_reason` column
  explaining why each row was skipped.
- Rows that were successfully submitted are removed from the on-screen table;
  rows that failed (or were never valid) remain so they can be corrected and
  resubmitted.

Bring Forward and Credit Leave validate the whole batch up front and reject it
entirely if any employee code is missing (see
[Frequently Asked Questions](#frequently-asked-questions)). The Excel sheet
uses column C for BF days and column D for CR days; at least one value is
required per employee.

## First Run Checklist

1. Install `ODBC Driver 17 for SQL Server`.
2. Confirm the SQL Server can be reached from the PC.
3. Confirm `[DatabaseConfig]` points to the main leave database.
4. Confirm the default report server `v1soho.com,1500` is correct, or add `[ReportConfig]` with `Server=SERVER_NAME,PORT`.
5. Start the app.
6. Open DB Targets and click `Test Connection`.
7. Open DB Targets and click `Update Query` to refresh stored procedures.
8. Open Leave Report Config and click `Setup DB`, then `Refresh`.
9. Add or verify report targets.
10. Open Manage Users and create `USER` or `REPORT` users as needed.

## Changelog

### Version 1.0.5

- Fixed BF-only and CR-only Excel imports failing with SQL Server error 8117
  (`Operand data type NULL is invalid for sum operator`) when the opposite
  leave-days column is blank for every imported row.
- Build `1.0.5+12`: Leave Taken now detects an existing record by employee,
  calendar date, and leave code even when the stored `LV_DATE` contains a time
  component or the record has different event metadata. Existing rows are
  skipped and written to the automatic failed-rows Excel report while other
  valid rows continue processing.
- **Leave Report Config** and **Manage Users** are now strictly hidden unless
  `[DatabaseConfig] Admin=1`; **DB Targets** remains controlled by the database
  ADMIN role.
- Renamed the BF/Credit Leave frontend labels for clarity and fixed fractional
  overflow in Settings color-theme cards at larger font scales.

### Version 1.0.4

- Build `1.0.4+11`: added Credit Leave entry alongside Bring Forward. Credit
  values are stored as `CR(AL)` and recalculate `CR`, `YTD_CR`, and annual
  leave balances alongside `BF(AL)`.
- Added separate **Bring Forward Days** and **Credit Leave Days** fields to the
  screen, Excel import/export, and packaged sample workbook.
- Added `PH`, `OFF`, `RL`, and `REST` to Leave Taken while preserving each
  code's configured `LV_TYPE.LV_EVENT_CODE`.
- Added the `[DatabaseConfig]` setting `Admin=1` to show **Leave Report Config**
  and **Manage Users** in the sidebar. Database authorization checks remain in
  force for user-management operations.

### Version 1.0.3

- Build `1.0.3+10`: Leave Taken bulk import no longer rejects the entire
  batch when some rows are invalid. Duplicate rows, rows that already exist,
  missing employee codes, and invalid leave codes (e.g. `BF`) are now
  skipped per-row, and the valid rows are still submitted. See
  [Leave Taken Bulk Import](#leave-taken-bulk-import).
- Added an automatic failed-rows Excel export for Leave Taken import, saved
  under `log\` with the same columns as the import template plus a
  `failed_reason` column, so large failures no longer have to be read from
  a single on-screen message.
- Large Leave Taken imports are now submitted in chunks with automatic
  bisect-and-retry on chunk failure and a live per-chunk progress
  indicator, instead of one large SQL script per submission. This fixes
  large imports (multiple thousands of rows) silently failing outright.
- Fixed a bug where a small number of genuinely conflicting rows (for
  example two leave entries for the same employee and date that together
  exceed one day) could cause an internal post-insert check to falsely
  report hundreds of otherwise-valid, already-inserted rows as failed. The
  app now reports only the rows that actually failed, with the real reason.
- Fixed a crash (`setState() called after dispose()`) in Leave Report
  Config when the screen is closed, or the app is hot-restarted, while a
  database call is still in progress.
- Fixed a UI overflow error in Leave Taken caused by a very long inline
  error message (for example listing many invalid employee codes at once);
  long failure detail now goes to the exported Excel report instead.
- Added `templates/` with sample `Bring_Forward_Template.xlsx` and
  `Leave_Taken_Template.xlsx` import files.

### Version 1.0.2

- Build `1.0.2+9`: Bring Forward and Leave Taken now validate employee codes against `dbo.STAFF` before import. Missing staff produce a clear `Staff <code> doesnt exist` error, and the whole batch is rejected (strict, all-or-nothing) so no partial import happens.
- Stored procedure errors are no longer swallowed. Previously a `THROW` inside a procedure (e.g. rollback) could still report success; operations now surface the real failure message.
- Bring Forward "initialize employee leave first" message now names the affected staff code(s).
- Fixed a duplicate `ROLE` column error when repairing the `dbo.LV_SYS_USER` table on startup.

### Version 1.0.1

- Build `1.0.1+7`: Fixed Leave Report Config edit behavior so clearing `CC Emails` saves correctly and removes the existing `cc_emails` value in `HR_REPORT_CONFIG.dbo.report_targets`.
- Added DB Targets `Update Query` action to run stored procedure scripts on demand.
- Startup now only creates or repairs login users; stored procedures no longer run automatically on app launch.
- Updated leave taken and bring-forward stored procedures to recalculate `LV_SUMMARY` from `LV_RECORDS` as the source of truth.
- `LV_SUMMARY` recalculation now updates all 12 months for the affected employee, year, and leave group.
- Bring-forward recalculation reads `LV_RECORDS` records with `LV_CODE = 'BF(AL)'`.
- Leave taken recalculation maps `AL`, `FHA`, and `SHA` to annual leave and refreshes `BF` only for annual leave summaries.
- Report target stored procedures now encrypt email passwords correctly for the `VARBINARY(MAX)` password column.
- Added terminal installer scripts, `setup.bat` and `setup.ps1`, with install-location prompt and optional desktop shortcut creation.
- Release zip script now includes installer scripts and stops if the Windows build fails.

## Frequently Asked Questions

### What happens if an employee code does not exist or contains a typo?

Both Bring Forward (BF) and Leave Taken validate employee codes against `dbo.STAFF` when the batch is submitted, but they respond differently:

- **Bring Forward** displays `Staff <code> doesnt exist` and rejects the entire batch. No rows are inserted, including rows with valid employee codes.
- **Leave Taken** skips only the rows with the missing employee code(s) and still submits the rest of the batch. The skipped rows appear in the failed-rows Excel export (see [Leave Taken Bulk Import](#leave-taken-bulk-import)) with reason `Employee code does not exist`.

### What happens when several employee codes in a batch do not exist?

For Bring Forward, the error lists all missing codes in one message, for example:

```text
Staff E099, E088, E077 doesnt exist
```

and the whole BF batch is rejected. Correct or remove the invalid rows, then submit the complete batch again.

For Leave Taken, each affected row is listed individually in the failed-rows Excel export instead, and every other valid row is still imported.

### Can BF or leave be inserted for resigned staff?

The application checks only whether the employee code exists in `dbo.STAFF`. It does not check active status, resignation date, or termination status. A resigned employee who remains in `dbo.STAFF` can therefore receive BF and leave records. If the employee has been removed from `dbo.STAFF`, the employee is treated as nonexistent: the BF batch is rejected, or the Leave Taken row is skipped and reported in the failed-rows export.

### Does submitting BF or CR again add to or replace the existing value?

When submitted BF or CR contains an employee who already has that value for the target year, the application shows the existing and requested values. Choose `Replace & Continue` to replace the existing value, or cancel, remove that employee's row, and submit again. For example, if the stored BF is `10` and the confirmed replacement is `20`, the BF becomes `20`, not `30`. BF and CR are independently optional, so leaving one blank does not replace it. The corresponding `LV_SUMMARY` values are recalculated.

### What happens if the same employee appears more than once in one BF batch?

The BF days from those rows are summed before saving. For example, two rows containing `5` and `3` days for the same employee and year produce a BF value of `8`.

### Can an incorrect BF value or year be corrected after submission?

An incorrect BF value can be corrected by submitting the correct value again for the same employee and year. If the wrong target year was selected, submitting for the correct year does not remove the record from the wrong year. The incorrect year's `LV_RECORDS` entry must be corrected or deleted directly in the database because the application has no BF undo/delete function.

### Does submitting Leave Taken again replace an existing record?

No. Leave Taken does not overwrite an existing record with the same employee, date, and leave code. That row is skipped as a duplicate (reason `Leave record already exists for this employee/date/type` in the failed-rows export) while the rest of the batch is still submitted.

### Can leave with a wrong date or leave type be corrected in the application?

The application currently has no leave undo, edit, or delete function. The incorrect `LV_RECORDS` entry must first be corrected or deleted directly in the database, after which the correct leave can be submitted. Leave duration is obtained from `dbo.LV_TYPE`; users do not enter the number of leave days directly.

### Can two different leave codes be recorded on the same date?

They are allowed only when their combined duration does not exceed one day and their half-day portions do not conflict. The same leave code cannot be submitted twice for the same employee and date. A row that violates this is skipped and reported in the failed-rows export rather than rejecting the whole batch.

### Can a leave code that isn't a "leave taken" type (for example `BF`) be imported through Leave Taken?

Leave Taken accepts codes configured in `dbo.LV_TYPE` with `LV_EVENT_CODE = 'LEAVE'`, plus `PH`, `OFF`, `RL`, and `REST`. Other codes (for example `BF`) are skipped with an invalid-code reason in the failed-rows export.

### What should I do if release ZIP creation reports a user-mapped section error?

Use the latest `tool\zip_windows_release.ps1`, which creates and validates a temporary archive before publishing the final ZIP. Do not distribute a ZIP from a failed run. Close any PowerShell session or File Explorer ZIP preview holding the old archive, open a new terminal, and run:

```powershell
.\tool\zip_windows_release.ps1
```

## Troubleshooting

### Connection Failed

- Check `Server`, `Database`, and `Driver` in `config.ini`.
- Confirm SQL Server allows remote connections.
- Confirm firewall and SQL Server port access.
- Confirm `ODBC Driver 17 for SQL Server` is installed.

### Leave Types Fail To Load

- Confirm the main database contains `dbo.LV_TYPE`.
- Confirm rows exist where `LV_EVENT_CODE = 'LEAVE'`.
- Use the latest release build, which casts leave type columns to bounded SQL types to avoid ODBC memory allocation errors.

### Report Targets Table Missing

Open `Leave Report Config` and click `Setup DB`. This creates or repairs `HR_REPORT_CONFIG.dbo.report_targets` and related procedures.

### Email Sending Fails

- Check SMTP server and port.
- Check email user and password.
- Check TLS setting.
- For Gmail or Microsoft accounts, use an app password where required by the provider.

## User Manual

See the generated Word manual:

```text
docs\HR_Leave_Management_User_Manual.docx
```
