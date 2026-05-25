# HR Leave Management

Windows desktop application for managing leave operations directly against SQL Server. The app no longer uses an API connection; all database work is performed through ODBC using `config.ini`.

## Main Features

- User login with role-based menus.
- Bring Forward Leave bulk entry and Excel import/export.
- Leave Taken bulk entry and Excel import/export.
- Main database connection check from `config.ini`.
- Leave Report Config CRUD against the fixed `HR_REPORT_CONFIG` database.
- Manage Users for creating and maintaining `USER` and `REPORT` accounts.
- App appearance settings for font size, dark/light mode, and color palette.

## Role Access

| Role | Visible menus |
| --- | --- |
| `ADMIN` | Bring Forward, Leave Taken, DB Targets, Leave Report Config, Manage Users |
| `USER` | Bring Forward, Leave Taken |
| `REPORT` | Leave Report Config |

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
- Report configuration database from `[ReportConfig]`, fixed database name `HR_REPORT_CONFIG`.

On startup, the app creates or repairs required app users and executes the related stored procedure setup files in `stored_procedure/`.

For Leave Report Config, use the `Setup DB` button if `HR_REPORT_CONFIG` or `dbo.report_targets` is missing. Email passwords are stored in the `email_password` column and encrypted in SQL Server.

## config.ini

The app reads `config.ini` from the same folder as `leave_management.exe` first. If it is not found there, it falls back to the bundled asset copy.

Example:

```ini
[DatabaseConfig]
Server=DIN-STT
Database=MYPAY_LCO
Driver=ODBC Driver 17 for SQL Server

[ReportConfig]
Server=#REPORT SERVER,PORT
Driver=ODBC Driver 17 for SQL Server
```

Notes:

- `[DatabaseConfig]` controls normal leave operations.
- `[ReportConfig]` controls only the Leave Report Config menu.
- `[ReportConfig] Server` is configurable. Replace `#REPORT SERVER,PORT` with the SQL Server location where the report configuration data is stored.
- The report config database name is **fixed** to `HR_REPORT_CONFIG`. Do not add a `Database=` line under `[ReportConfig]`; the app always uses `HR_REPORT_CONFIG` for this menu.
- If using a custom SQL port, set `Server=SERVER_NAME,PORT`.
- Keep the placeholder format as `Server=#REPORT SERVER,PORT` until replacing it with the real report SQL Server and port.

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
   config.ini
   flutter_windows.dll
   data\
   stored_procedure\
   ```

6. Edit `config.ini` in the extracted folder.

7. Run:

   ```text
   leave_management.exe
   ```

8. On first run, the app connects to the database from `config.ini`, creates or repairs required users, and executes the stored procedure setup files in `stored_procedure\`.

Important:

- Keep `config.ini` beside `leave_management.exe`.
- Keep the `data\` folder beside `leave_management.exe`.
- Keep the `stored_procedure\` folder beside `leave_management.exe` so startup setup can run.
- Do not run the exe directly from inside the zip file. Extract it first.

## Create Release Zip For GitHub

Use this method when preparing a new release package.

1. Build the Windows release:

   ```powershell
   flutter build windows --release
   ```

2. Open the release output:

   ```text
   build\windows\x64\runner\Release
   ```

3. Make sure `config.ini` exists in the same folder as:

   ```text
   leave_management.exe
   ```

4. Edit `config.ini` for the production SQL Server and database.

5. Run:

   ```text
   leave_management.exe
   ```

6. Create a zip from the contents of the `Release` folder:

   ```powershell
   Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath releases\leave_management_windows_release.zip -Force
   ```

7. Upload `releases\leave_management_windows_release.zip` to GitHub Releases.

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

## First Run Checklist

1. Install `ODBC Driver 17 for SQL Server`.
2. Confirm the SQL Server can be reached from the PC.
3. Confirm `[DatabaseConfig]` points to the main leave database.
4. Confirm `[ReportConfig]` points to the server that hosts `HR_REPORT_CONFIG`.
5. Start the app.
6. Open DB Targets and click `Test Connection`.
7. Open Leave Report Config and click `Setup DB`, then `Refresh`.
8. Add or verify report targets.
9. Open Manage Users and create `USER` or `REPORT` users as needed.

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
