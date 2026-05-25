import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leave_management/core/theme.dart';
import 'package:leave_management/core/constants.dart';
import 'package:leave_management/core/db_client.dart';

// ---------------------------------------------------------------------------
// Data model for a single BF row (editable via controllers)
// ---------------------------------------------------------------------------
class _BfRow {
  final TextEditingController empCodeCtrl = TextEditingController();
  final TextEditingController dayCtrl = TextEditingController();

  _BfRow({String empCode = '', String day = ''}) {
    empCodeCtrl.text = empCode;
    dayCtrl.text = day;
  }

  void dispose() {
    empCodeCtrl.dispose();
    dayCtrl.dispose();
  }

  bool get isValid =>
      empCodeCtrl.text.trim().isNotEmpty &&
      double.tryParse(dayCtrl.text.trim()) != null;

  Map<String, dynamic> toMap() {
    return {
      'empCode': empCodeCtrl.text.trim(),
      'day': double.parse(dayCtrl.text.trim()),
    };
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class BringForwardScreen extends StatefulWidget {
  const BringForwardScreen({super.key});

  @override
  State<BringForwardScreen> createState() => _BringForwardScreenState();
}

class _BringForwardScreenState extends State<BringForwardScreen> {
  final List<_BfRow> _rows = [];
  final _databaseCtrl = TextEditingController();

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  List<Map<String, dynamic>> _targets = [];
  String? _selectedDatabase;
  bool _loadingDatabases = false;

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
    } else {
      _fetchDatabases();
    }
  }

  Future<void> _fetchDatabases() async {
    _selectedDatabase = kDatabaseName;
    _databaseCtrl.text = kDatabaseName;
    _targets = [];
    setState(() => _loadingDatabases = false);
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
  void _addRow() => setState(() => _rows.add(_BfRow()));

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
  // Excel import  (Sheet: "BF" | A=empCode  B=name(skip)  C=days  D=remark)
  // -------------------------------------------------------------------------
  Future<void> _importFromExcel() async {
    setState(() => _isImporting = true);

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        dialogTitle: 'Select Bring-Forward Excel File',
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

      // Locate the "BF" sheet
      final sheet = excel.tables['BF'];
      if (sheet == null) {
        _showSnack(
          'Sheet named "BF" not found in the selected file.\n'
          'Available sheets: ${excel.tables.keys.join(', ')}',
          isError: true,
        );
        return;
      }

      final newRows = <_BfRow>[];
      int skipped = 0;

      // Skip header row (index 0); process from row index 1 onwards
      for (final row in sheet.rows.skip(1)) {
        final empCode = _cellStr(row, 0); // Column A
        // Column B (index 1) = emp name — intentionally skipped
        final dayRaw = _cellStr(row, 2); // Column C

        if (empCode.isEmpty) {
          skipped++;
          continue;
        }

        final day = double.tryParse(dayRaw);
        if (day == null) {
          skipped++;
          continue;
        }

        newRows.add(
          _BfRow(
            empCode: empCode,
            day: dayRaw.contains('.') ? day.toString() : day.toStringAsFixed(0),
          ),
        );
      }

      if (newRows.isEmpty) {
        _showSnack('No valid rows found in the BF sheet.', isError: true);
        return;
      }

      setState(() {
        // Replace existing rows with imported ones
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

  Future<void> _exportToExcel() async {
    try {
      var excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.rename(defaultSheet, 'BF');
      }
      var sheet = excel['BF'];

      // Add header row
      sheet.appendRow([
        TextCellValue('Employee Code'),
        TextCellValue('Employee Name'),
        TextCellValue('Days'),
      ]);

      // Export current table content if any row is populated
      int exportedRowsCount = 0;
      for (final row in _rows) {
        final empCode = row.empCodeCtrl.text.trim();
        final days = row.dayCtrl.text.trim();
        if (empCode.isNotEmpty || days.isNotEmpty) {
          sheet.appendRow([
            TextCellValue(empCode),
            TextCellValue(''), // Name column (skipped on import)
            TextCellValue(days),
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
        fileName: 'Bring_Forward_Template.xlsx',
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

  /// Safely extract a trimmed string value from a cell in a row.
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
      _showSnack(
        'Please add at least one valid row (Employee Code + Days are required).',
        isError: true,
      );
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm Bring Forward'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to add bring-forward leave for '
              '${validRows.length} employee(s).',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              'Target Database: $db\n'
              'Target Year: $_selectedYear\n'
              'Target Month: $_selectedMonth',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            SizedBox(height: 12),
            Text(
              '⚠️  This action cannot be undone. Proceed?',
              style: TextStyle(color: AppColors.warning, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });

    try {
      final result = await DirectDbClient().addBringForwardLeave(
        database: db,
        year: _selectedYear,
        month: _selectedMonth,
        list: validRows.map((r) => r.toMap()).toList(),
      );
      setState(() {
        _isSuccess = true;
        _resultMessage =
            result['message'] as String? ??
            'Bring forward leave added successfully!';

        // Clear all table rows and restart with one blank row
        for (final row in _rows) {
          row.dispose();
        }
        _rows.clear();
        _rows.add(_BfRow());
        _importSummary = null;
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        var msg = e.toString();
        if (msg.startsWith('Exception: ')) {
          msg = msg.substring('Exception: '.length);
        }
        _resultMessage = msg;
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
            _buildParamsForm(),
            SizedBox(height: 12),
            Expanded(child: _buildTable()),
          ],
        ),
      ),
    );
  }

  Widget _buildParamsForm() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Target Year Dropdown
          Expanded(
            child: DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _selectedYear,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              dropdownColor: AppColors.surfaceElevated,
              decoration: InputDecoration(
                labelText: 'Target Year *',
                prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: [2024, 2025, 2026, 2027, 2028, 2029, 2030].map((year) {
                return DropdownMenuItem<int>(
                  value: year,
                  child: Text(
                    year.toString(),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedYear = val ?? DateTime.now().year;
                });
              },
            ),
          ),
          SizedBox(width: 16),
          // Target Month Dropdown
          Expanded(
            child: DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _selectedMonth,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              dropdownColor: AppColors.surfaceElevated,
              decoration: InputDecoration(
                labelText: 'Target Month *',
                prefixIcon: Icon(Icons.calendar_view_month_outlined, size: 18),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: List.generate(12, (index) => index + 1).map((month) {
                final monthNames = [
                  'January',
                  'February',
                  'March',
                  'April',
                  'May',
                  'June',
                  'July',
                  'August',
                  'September',
                  'October',
                  'November',
                  'December',
                ];
                return DropdownMenuItem<int>(
                  value: month,
                  child: Text(
                    '$month - ${monthNames[month - 1]}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedMonth = val ?? 12;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- Sub-widgets --------------------------------------------------------

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
            Icons.arrow_circle_right_outlined,
            color: AppColors.tertiary,
            size: 20,
          ),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bring Forward Leave',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Bulk allocation of carry-forward annual leave',
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
          label: Text(_isLoading ? 'Processing…' : 'Run Bring Forward'),
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
            width: 120,
            child: Text(
              'DAYS',
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
          // Column A: empCode
          Expanded(
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
          // Column C: days
          SizedBox(
            width: 120,
            child: TextField(
              controller: row.dayCtrl,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              decoration: InputDecoration(
                hintText: 'Days Leave',
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(width: 8),
          // Delete
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
