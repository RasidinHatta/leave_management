import 'package:flutter/material.dart';
import 'package:leave_management/core/constants.dart';
import 'package:leave_management/core/db_client.dart';
import 'package:leave_management/core/theme.dart';

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  DateTime _selectedDate = DateTime.now();
  final _officeCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _databaseCtrl = TextEditingController();

  List<Map<String, dynamic>> _targets = [];
  String? _selectedDatabase;
  bool _loadingDatabases = false;

  bool _isLoading = false;
  List<Map<String, dynamic>> _results = [];
  List<String> _columns = [];
  String? _error;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _databaseCtrl.text = kDatabaseName;
    _selectedDatabase = kDatabaseName;
    _fetchDatabases();
  }

  Future<void> _fetchDatabases() async {
    _targets = [];
    setState(() => _loadingDatabases = false);
  }

  @override
  void dispose() {
    _officeCtrl.dispose();
    _departmentCtrl.dispose();
    _databaseCtrl.dispose();
    super.dispose();
  }

  String get _formattedDate =>
      '${_selectedDate.day.toString().padLeft(2, '0')}/'
      '${_selectedDate.month.toString().padLeft(2, '0')}/'
      '${_selectedDate.year}';

  String get _apiDate =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-'
      '${_selectedDate.month.toString().padLeft(2, '0')}-'
      '${_selectedDate.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _search() async {
    final db = _databaseCtrl.text.trim();
    if (db.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Database is required.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _hasSearched = true;
    });

    try {
      final data = await DirectDbClient().getDailyReport(
        date: _apiDate,
        office: _officeCtrl.text.trim().isNotEmpty
            ? _officeCtrl.text.trim()
            : null,
        department: _departmentCtrl.text.trim().isNotEmpty
            ? _departmentCtrl.text.trim()
            : null,
        database: db,
      );
      setState(() {
        _results = data;
        _columns = data.isNotEmpty ? data.first.keys.toList() : [];
      });
    } on DatabaseException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _isLoading = false);
    }
  }

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
            _buildQueryForm(),
            SizedBox(height: 16),
            if (_isLoading)
              Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              _buildError()
            else if (_hasSearched)
              Expanded(child: _buildResults())
            else
              _buildEmptyState(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
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
            Icons.calendar_today_outlined,
            color: AppColors.tertiary,
            size: 20,
          ),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Attendance & Leave Report',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Query attendance and leave records by date',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQueryForm() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Query Parameters',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              // Date picker
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Report Date *',
                      prefixIcon: Icon(Icons.date_range_outlined, size: 18),
                    ),
                    child: Text(
                      _formattedDate,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _officeCtrl,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Office (optional)',
                    hintText: 'e.g. Johor-JG',
                    prefixIcon: Icon(Icons.business_outlined, size: 18),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _departmentCtrl,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Department (optional)',
                    hintText: 'e.g. MKT Dept',
                    prefixIcon: Icon(Icons.group_outlined, size: 18),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
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
                          labelText: 'Database *',
                          prefixIcon: Icon(Icons.storage_outlined, size: 18),
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
              ),
              SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _search,
                icon: Icon(Icons.search, size: 16),
                label: Text('Search'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Expanded _buildError() {
    return Expanded(
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 480),
          padding: EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.errorBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppColors.error, size: 40),
              SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.error),
              ),
              SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _search,
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Expanded _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.2),
            ),
            SizedBox(height: 16),
            Text(
              'Select a date and click Search to load records',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.2),
            ),
            SizedBox(height: 16),
            Text(
              'No records found for the selected criteria',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentPanel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.accentBorder),
              ),
              child: Text(
                '${_results.length} record${_results.length == 1 ? '' : 's'} found  •  $_formattedDate',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      AppColors.surfaceElevated,
                    ),
                    columns: _columns
                        .map(
                          (col) => DataColumn(
                            label: Text(
                              col.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    rows: _results
                        .map(
                          (row) => DataRow(
                            cells: _columns
                                .map(
                                  (col) => DataCell(
                                    Text(
                                      row[col]?.toString() ?? '—',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
