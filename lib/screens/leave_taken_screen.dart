import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:leave_management/core/db_client.dart';
import 'package:leave_management/core/theme.dart';
import 'package:leave_management/core/constants.dart';

// ---------------------------------------------------------------------------
// Data model for a single Leave Taken row (editable via controllers)
// ---------------------------------------------------------------------------
class _LeaveRow {
  final TextEditingController empCodeCtrl = TextEditingController();
  final TextEditingController dateCtrl = TextEditingController();
  final TextEditingController codeCtrl = TextEditingController();
  final TextEditingController remarkCtrl = TextEditingController();

  _LeaveRow({
    String empCode = '',
    String date = '',
    String code = '',
    String remark = '',
  }) {
    empCodeCtrl.text = empCode;
    dateCtrl.text = date;
    codeCtrl.text = code;
    remarkCtrl.text = remark;
  }

  void dispose() {
    empCodeCtrl.dispose();
    dateCtrl.dispose();
    codeCtrl.dispose();
    remarkCtrl.dispose();
  }

  bool get isValid {
    final emp = empCodeCtrl.text.trim();
    final date = dateCtrl.text.trim();
    final code = codeCtrl.text.trim();
    return emp.isNotEmpty &&
        date.isNotEmpty &&
        code.isNotEmpty &&
        DateTime.tryParse(date) != null;
  }

  Map<String, dynamic> toMap() {
    return {
      'empCode': empCodeCtrl.text.trim(),
      'lvDate': dateCtrl.text.trim(),
      'lvCode': codeCtrl.text.trim().toUpperCase(),
      'remark': remarkCtrl.text.trim().isEmpty ? null : remarkCtrl.text.trim(),
    };
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class LeaveTakenScreen extends StatefulWidget {
  const LeaveTakenScreen({super.key});

  @override
  State<LeaveTakenScreen> createState() => _LeaveTakenScreenState();
}

class _LeaveTakenScreenState extends State<LeaveTakenScreen> {
  final List<_LeaveRow> _rows = [];
  final DirectDbClient _dbClient = DirectDbClient();
  final _databaseCtrl = TextEditingController();

  List<Map<String, dynamic>> _targets = [];
  String? _selectedDatabase;
  bool _loadingDatabases = false;
  List<Map<String, String>> _leaveTypes = [];
  bool _loadingLeaveTypes = false;

  bool _isLoading = false;
  bool _isImporting = false;
  String? _resultMessage;
  bool _isSuccess = false;
  String? _importSummary;

  @override
  void initState() {
    super.initState();
    _addRow(); // start with one empty row
    if (kDatabaseName.isNotEmpty) {
      _selectedDatabase = kDatabaseName;
      _databaseCtrl.text = kDatabaseName;
      _fetchLeaveTypes(kDatabaseName);
    } else {
      _fetchDatabases();
    }
  }

  Future<void> _fetchDatabases() async {
    // Since the leave API is removed, we do not fetch database targets from a backend.
    // The UI will rely on a pre-configured database name (kDatabaseName) or remain empty.
    setState(() => _loadingDatabases = false);
    _targets = [];
  }

  Future<void> _fetchLeaveTypes(String? db) async {
    setState(() => _loadingLeaveTypes = true);
    try {
      final list = await _dbClient.getLeaveTypes(db ?? kDatabaseName);
      setState(() {
        _leaveTypes = list.map<Map<String, String>>((t) {
          final code = (t['lvCode'] as String? ?? '').toUpperCase().trim();
          final desc = (t['lvDesc'] as String? ?? '').trim();
          return {'code': code, 'desc': desc};
        }).toList();
      });
    } catch (e) {
      _showSnack('Failed to load leave types: $e', isError: true);
    } finally {
      setState(() => _loadingLeaveTypes = false);
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    _databaseCtrl.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Row management
  // -------------------------------------------------------------------------
  void _addRow() => setState(() => _rows.add(_LeaveRow()));

  void _removeRow(int index) {
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
      if (_rows.isEmpty) _addRow();
    });
  }

  void _clearAll() {
    setState(() {
      for (final row in _rows) {
        row.dispose();
      }
      _rows.clear();
      _addRow();
      _resultMessage = null;
      _importSummary = null;
    });
  }

  // -------------------------------------------------------------------------
  // Excel parse helper
  // -------------------------------------------------------------------------
  String? _parseExcelDate(String val) {
    val = val.trim();
    if (val.isEmpty) return null;

    // 1. Try ISO YYYY-MM-DD
    final parsed = DateTime.tryParse(val);
    if (parsed != null) {
      return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    }

    // 2. Try d/m/yyyy or dd/mm/yyyy
    final parts = val.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        }
      }
    }

    // 3. Try d-m-yyyy or yyyy-mm-dd (with hyphens)
    final hyphenParts = val.split('-');
    if (hyphenParts.length == 3) {
      if (hyphenParts[0].length == 4) {
        final year = int.tryParse(hyphenParts[0]);
        final month = int.tryParse(hyphenParts[1]);
        final day = int.tryParse(hyphenParts[2]);
        if (year != null && month != null && day != null) {
          return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        }
      } else {
        final day = int.tryParse(hyphenParts[0]);
        final month = int.tryParse(hyphenParts[1]);
        final year = int.tryParse(hyphenParts[2]);
        if (day != null && month != null && year != null) {
          return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        }
      }
    }

    return null;
  }

  // -------------------------------------------------------------------------
  // Excel import (Sheet: "LV" | A=empCode  B=name(skip)  C=date  D=leaveCode E=remark)
  // -------------------------------------------------------------------------
  Future<void> _importFromExcel() async {
    setState(() => _isImporting = true);

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        dialogTitle: 'Select Leave Taken Excel File',
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isImporting = false);
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        _showSnack('Could not read file path.', isError: true);
        return;
      }

      final bytes = await File(filePath).readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      // Locate sheet named "LV"
      var sheet = excel.tables['LV'];
      if (sheet == null) {
        // Search case-insensitively for sheet LV
        final key = excel.tables.keys.firstWhere(
          (k) => k.trim().toUpperCase() == 'LV',
          orElse: () => '',
        );
        if (key.isNotEmpty) {
          sheet = excel.tables[key];
        }
      }

      sheet ??= excel.tables.values.first;

      final newRows = <_LeaveRow>[];
      int skipped = 0;

      // Skip header row; process from index 1 onwards
      for (final row in sheet.rows.skip(1)) {
        final empCode = _cellStr(row, 0); // Column A
        final dateRaw = _cellStr(row, 2); // Column C
        final lvCode = _cellStr(row, 3); // Column D
        final remark = _cellStr(row, 4); // Column E (optional)

        if (empCode.isEmpty || lvCode.isEmpty) {
          skipped++;
          continue;
        }

        final parsedDate = _parseExcelDate(dateRaw);
        if (parsedDate == null) {
          skipped++;
          continue;
        }

        final lvCodeUpper = lvCode.toUpperCase();
        final hasCode = _leaveTypes.any((t) => t['code'] == lvCodeUpper);
        if (!hasCode) {
          _leaveTypes.add({'code': lvCodeUpper, 'desc': lvCodeUpper});
        }

        newRows.add(
          _LeaveRow(
            empCode: empCode,
            date: parsedDate,
            code: lvCodeUpper,
            remark: remark,
          ),
        );
      }

      if (newRows.isEmpty) {
        _showSnack('No valid rows found in the sheet.', isError: true);
        return;
      }

      setState(() {
        for (final r in _rows) {
          r.dispose();
        }
        _rows
          ..clear()
          ..addAll(newRows);
        _resultMessage = null;
        _importSummary =
            'Imported ${newRows.length} row(s) from Excel${skipped > 0 ? ' ($skipped skipped)' : ''}.';
      });
    } catch (e) {
      _showSnack('Import failed: $e', isError: true);
    } finally {
      setState(() => _isImporting = false);
    }
  }

  String _formatToExcelDate(String val) {
    val = val.trim();
    final parts = val.split('-');
    if (parts.length == 3) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return '$day/$month/$year';
      }
    }
    return val;
  }

  Future<void> _exportToExcel() async {
    try {
      var excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.rename(defaultSheet, 'LV');
      }
      var sheet = excel['LV'];

      // Add header row
      sheet.appendRow([
        TextCellValue('Employee Code'),
        TextCellValue('Employee Name'),
        TextCellValue('Leave Date (d/m/yyyy)'),
        TextCellValue('Leave Type'),
        TextCellValue('Remark'),
      ]);

      // Export current table content
      int exportedRowsCount = 0;
      for (final row in _rows) {
        final empCode = row.empCodeCtrl.text.trim();
        final date = row.dateCtrl.text.trim();
        final code = row.codeCtrl.text.trim();
        final remark = row.remarkCtrl.text.trim();
        if (empCode.isNotEmpty || date.isNotEmpty || code.isNotEmpty) {
          sheet.appendRow([
            TextCellValue(empCode),
            TextCellValue(''), // Name (ignored on import)
            TextCellValue(_formatToExcelDate(date)),
            TextCellValue(code),
            TextCellValue(remark),
          ]);
          exportedRowsCount++;
        }
      }

      final fileBytes = excel.save();
      if (fileBytes == null) {
        _showSnack('Failed to generate Excel file.', isError: true);
        return;
      }

      String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'Save Excel Template',
        fileName: 'Leave_Taken_Template.xlsx',
        allowedExtensions: ['xlsx'],
        type: FileType.custom,
      );

      if (outputFile != null) {
        if (!outputFile.endsWith('.xlsx')) {
          outputFile = '$outputFile.xlsx';
        }
        final file = File(outputFile);
        await file.writeAsBytes(fileBytes);
        _showSnack(
          exportedRowsCount > 0
              ? 'Exported $exportedRowsCount row(s) to $outputFile'
              : 'Excel template saved to $outputFile',
        );
      }
    } catch (e) {
      _showSnack('Export failed: $e', isError: true);
    }
  }

  String _cellStr(List<Data?> row, int index) {
    if (index >= row.length) return '';
    final cell = row[index];
    if (cell == null) return '';
    final val = cell.value;
    if (val == null) return '';
    return val.toString().trim();
  }

  // -------------------------------------------------------------------------
  // Submit
  // -------------------------------------------------------------------------
  Future<void> _submit() async {
    final db = _databaseCtrl.text.trim();
    if (db.isEmpty) {
      _showSnack('Target Database is required.', isError: true);
      return;
    }

    final validRows = _rows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) {
      _showSnack('No valid rows to import.', isError: true);
      return;
    }

    // Double check dates format before submitting
    for (final row in validRows) {
      final date = row.dateCtrl.text.trim();
      if (DateTime.tryParse(date) == null) {
        _showSnack(
          'Invalid date format: "$date". Must be YYYY-MM-DD.',
          isError: true,
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });

    try {
      final result = await _dbClient.addLeaveTaken(
        database: db,
        list: validRows.map((r) => r.toMap()).toList(),
      );
      setState(() {
        _isSuccess = true;
        _resultMessage =
            result['message'] as String? ?? 'Leave records added successfully!';

        // Clear all table rows and restart with one blank row
        for (final row in _rows) {
          row.dispose();
        }
        _rows.clear();
        _rows.add(_LeaveRow());
        _importSummary = null;
      });
    } on DatabaseException catch (e) {
      setState(() {
        _isSuccess = false;
        _resultMessage = e.message;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : null,
        duration: Duration(seconds: 4),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            SizedBox(height: 20),
            _buildToolbar(),
            if (_importSummary != null) ...[
              SizedBox(height: 10),
              _buildImportBanner(),
            ],
            SizedBox(height: 12),
            if (_resultMessage != null) ...[
              _buildResultBanner(),
              SizedBox(height: 12),
            ],
            Expanded(child: _buildTable()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accentPanel,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.event_busy_outlined,
            color: AppColors.tertiary,
            size: 20,
          ),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Leave Taken',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Bulk allocation of employee leave records',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final validCount = _rows.where((r) => r.isValid).length;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Database select
        if (kDatabaseName.isEmpty)
          SizedBox(
            width: 280,
            child: _loadingDatabases
                ? SizedBox(
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedDatabase,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: InputDecoration(
                      labelText: 'Target Database *',
                      prefixIcon: Icon(Icons.storage_outlined),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: _targets.map((t) {
                      final dbName = t['databaseName'] as String;
                      final dispName = t['displayName'] as String;
                      return DropdownMenuItem<String>(
                        value: dbName,
                        child: Text(
                          '$dispName ($dbName)',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedDatabase = val;
                        _databaseCtrl.text = val ?? '';
                      });
                      if (val != null) {
                        _fetchLeaveTypes(val);
                      }
                    },
                  ),
          )
        else
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storage_outlined,
                  size: 16,
                  color: AppColors.secondary,
                ),
                SizedBox(width: 8),
                Text(
                  'Database: $kDatabaseName',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        // Export Excel
        OutlinedButton.icon(
          onPressed: _exportToExcel,
          icon: Icon(Icons.download_outlined, size: 16),
          label: Text('Export Excel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary),
          ),
        ),

        // Import Excel
        OutlinedButton.icon(
          onPressed: _isImporting ? null : _importFromExcel,
          icon: _isImporting
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.upload_file_outlined, size: 16),
          label: Text(_isImporting ? 'Importing…' : 'Import Excel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary),
          ),
        ),

        // Clear
        OutlinedButton.icon(
          onPressed: _clearAll,
          icon: Icon(Icons.clear_all, size: 16),
          label: Text('Clear'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
        ),

        // Spacer element
        SizedBox(width: 8),

        // Row count badge
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            '$validCount valid / ${_rows.length} rows',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),

        // Submit
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _submit,
          icon: _isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(Icons.send_outlined, size: 16),
          label: Text(_isLoading ? 'Processing…' : 'Run Leave Taken'),
        ),
      ],
    );
  }

  Widget _buildImportBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _importSummary!,
              style: TextStyle(color: AppColors.success, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _importSummary = null),
            icon: Icon(Icons.close, size: 14),
            color: AppColors.textSecondary,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 20, minHeight: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBanner() {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _isSuccess ? AppColors.successBg : AppColors.errorBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isSuccess
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isSuccess ? Icons.check_circle_outline : Icons.error_outline,
            color: _isSuccess ? AppColors.success : AppColors.error,
            size: 16,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              _resultMessage!,
              style: TextStyle(
                color: _isSuccess ? AppColors.success : AppColors.error,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _resultMessage = null),
            icon: Icon(Icons.close, size: 14),
            color: AppColors.textSecondary,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 20, minHeight: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildTableHeader(),
          Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, _) => Divider(height: 1),
              itemBuilder: (_, i) => _buildTableRow(i),
            ),
          ),
          _buildAddRowFooter(),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '#',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'EMPLOYEE CODE',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: Text(
              'LEAVE DATE (YYYY-MM-DD)',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: Text(
              'LEAVE TYPE',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              'REMARK',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildTableRow(int index) {
    final row = _rows[index];
    final isValid = row.isValid;

    return AnimatedContainer(
      duration: Duration(milliseconds: 100),
      color: isValid
          ? Colors.transparent
          : AppColors.errorBg.withValues(alpha: 0.3),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${index + 1}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          // Employee Code
          Expanded(
            flex: 2,
            child: TextField(
              controller: row.empCodeCtrl,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'Employee Code...',
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(width: 12),
          // Leave Date
          SizedBox(
            width: 180,
            child: TextField(
              controller: row.dateCtrl,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'YYYY-MM-DD',
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(Icons.calendar_today, size: 14),
                  color: AppColors.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                  onPressed: () async {
                    final curr =
                        DateTime.tryParse(row.dateCtrl.text.trim()) ??
                        DateTime.now();
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: curr,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      builder: (ctx, child) {
                        return Theme(
                          data: Theme.of(ctx).copyWith(
                            colorScheme: ColorScheme.dark(
                              primary: AppColors.primary,
                              onPrimary: AppColors.onPrimary,
                              surface: AppColors.surfaceElevated,
                              onSurface: AppColors.textPrimary,
                            ),
                            dialogTheme: DialogThemeData(
                              backgroundColor: AppColors.background,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (chosen != null) {
                      setState(() {
                        row.dateCtrl.text =
                            '${chosen.year}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
                      });
                    }
                  },
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(width: 12),
          // Leave Code Dropdown
          SizedBox(
            width: 140,
            child: _loadingLeaveTypes
                ? SizedBox(
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ),
                  )
                : InputDecorator(
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value:
                            _leaveTypes.any(
                              (t) =>
                                  t['code'] ==
                                  row.codeCtrl.text.trim().toUpperCase(),
                            )
                            ? row.codeCtrl.text.trim().toUpperCase()
                            : null,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                        dropdownColor: AppColors.surfaceElevated,
                        hint: Text(
                          'Select...',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        items: _leaveTypes.map((type) {
                          final code = type['code'] ?? '';
                          final desc = type['desc'] ?? '';
                          final displayText = desc.isNotEmpty && desc != code
                              ? '$code - $desc'
                              : code;
                          return DropdownMenuItem<String>(
                            value: code,
                            child: Text(
                              displayText,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              row.codeCtrl.text = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
          ),
          SizedBox(width: 12),
          // Remark
          Expanded(
            flex: 3,
            child: TextField(
              controller: row.remarkCtrl,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Remark (optional)...',
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(width: 8),
          // Delete row
          SizedBox(
            width: 36,
            child: IconButton(
              onPressed: () => _removeRow(index),
              icon: Icon(Icons.delete_outline, size: 16),
              color: AppColors.error.withValues(alpha: 0.7),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Remove row',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddRowFooter() {
    return InkWell(
      onTap: _addRow,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 16, color: AppColors.textSecondary),
            SizedBox(width: 6),
            Text(
              'Add Row',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
