import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leave_management/core/constants.dart';
import 'package:leave_management/core/db_client.dart';
import 'package:leave_management/core/report_config_db_client.dart';
import 'package:leave_management/core/theme.dart';
import 'package:leave_management/models/target.dart';

class LeaveReportConfigScreen extends StatefulWidget {
  const LeaveReportConfigScreen({super.key});

  @override
  State<LeaveReportConfigScreen> createState() =>
      _LeaveReportConfigScreenState();
}

class _LeaveReportConfigScreenState extends State<LeaveReportConfigScreen> {
  final _client = ReportConfigDbClient();
  List<Target> _targets = [];
  bool _isLoading = false;
  bool _isSettingUp = false;
  bool _isTesting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final targets = await _client.getTargets();
      setState(() => _targets = targets);
    } on DatabaseException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setupConfigDatabase() async {
    setState(() {
      _isSettingUp = true;
      _error = null;
    });

    try {
      await _client.ensureSchema();
      await _loadTargets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report config database setup complete.')),
      );
    } on DatabaseException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isSettingUp = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _error = null;
    });

    try {
      final info = await _client.getConnectionInfo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connection OK: ${info['serverName'] ?? kReportServerName} / ${info['databaseName'] ?? kReportDatabaseName}',
          ),
        ),
      );
    } on DatabaseException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _showTargetDialog(Target? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReportTargetDialog(client: _client, existing: existing),
    );
    if (saved == true) {
      await _loadTargets();
    }
  }

  Future<void> _deleteTarget(Target target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Report Target'),
        content: Text('Delete ${target.displayName} (${target.databaseName})?'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _client.deleteTarget(target.databaseName);
      await _loadTargets();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted ${target.databaseName}')));
    } on DatabaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
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
            SizedBox(height: 16),
            _buildConfigStrip(),
            SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _buildError()
                  : _buildTable(),
            ),
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
            Icons.fact_check_outlined,
            color: AppColors.tertiary,
            size: 20,
          ),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Leave Report Config',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'CRUD for HR_REPORT_CONFIG.dbo.report_targets',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        Spacer(),
        OutlinedButton.icon(
          onPressed: _isTesting ? null : _testConnection,
          icon: _isTesting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.power_settings_new, size: 16),
          label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
        ),
        SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: _isSettingUp ? null : _setupConfigDatabase,
          icon: _isSettingUp
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.build_outlined, size: 16),
          label: Text(_isSettingUp ? 'Setting Up...' : 'Setup DB'),
        ),
        SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: _isLoading || _isSettingUp ? null : _loadTargets,
          icon: Icon(Icons.refresh, size: 16),
          label: Text('Refresh'),
        ),
        SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () => _showTargetDialog(null),
          icon: Icon(Icons.add, size: 16),
          label: Text('Add Target'),
        ),
      ],
    );
  }

  Widget _buildConfigStrip() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage_outlined, color: AppColors.secondary, size: 16),
          SizedBox(width: 8),
          Text(
            '$kReportServerName / $kReportDatabaseName / $kReportDriverName',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: 560),
        padding: EdgeInsets.all(24),
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
              onPressed: _loadTargets,
              icon: Icon(Icons.refresh, size: 16),
              label: Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    if (_targets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.2),
            ),
            SizedBox(height: 16),
            Text(
              'No report targets configured yet',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _showTargetDialog(null),
              icon: Icon(Icons.add, size: 16),
              label: Text('Add First Target'),
            ),
          ],
        ),
      );
    }

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
              itemCount: _targets.length,
              separatorBuilder: (_, _) => Divider(height: 1),
              itemBuilder: (_, index) => _buildRow(_targets[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    final style = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('DATABASE', style: style)),
          Expanded(flex: 2, child: Text('DISPLAY NAME', style: style)),
          Expanded(flex: 2, child: Text('SMTP / USER', style: style)),
          Expanded(flex: 3, child: Text('RECIPIENTS', style: style)),
          SizedBox(
            width: 72,
            child: Text('STATUS', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(width: 76),
        ],
      ),
    );
  }

  Widget _buildRow(Target target) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              target.databaseName,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              target.displayName,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${target.smtpServer ?? '-'}:${target.smtpPort ?? 587}\n${target.emailUser}',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              target.toEmails,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          SizedBox(
            width: 72,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: target.isActive
                      ? AppColors.successBg
                      : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: target.isActive
                        ? AppColors.success.withValues(alpha: 0.4)
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  target.isActive ? 'Active' : 'Inactive',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: target.isActive
                        ? AppColors.success
                        : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 76,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => _showTargetDialog(target),
                  icon: Icon(Icons.edit_outlined, size: 16),
                  color: AppColors.secondary,
                  tooltip: 'Edit',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  onPressed: () => _deleteTarget(target),
                  icon: Icon(Icons.delete_outline, size: 16),
                  color: AppColors.error,
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTargetDialog extends StatefulWidget {
  final ReportConfigDbClient client;
  final Target? existing;

  const _ReportTargetDialog({required this.client, this.existing});

  @override
  State<_ReportTargetDialog> createState() => _ReportTargetDialogState();
}

class _ReportTargetDialogState extends State<_ReportTargetDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _databaseCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _smtpServerCtrl;
  late final TextEditingController _smtpPortCtrl;
  late final TextEditingController _emailUserCtrl;
  late final TextEditingController _emailPasswordCtrl;
  late final TextEditingController _toEmailsCtrl;
  late final TextEditingController _ccEmailsCtrl;

  bool _emailUseTls = true;
  bool _isActive = true;
  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _isLoadingDatabases = false;
  String? _databaseLoadError;
  List<ReportDatabaseOption> _databaseOptions = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _databaseCtrl = TextEditingController(text: existing?.databaseName ?? '');
    _displayNameCtrl = TextEditingController(text: existing?.displayName ?? '');
    _smtpServerCtrl = TextEditingController(
      text: existing?.smtpServer ?? 'mail.smartouch.com.my',
    );
    _smtpPortCtrl = TextEditingController(
      text: (existing?.smtpPort ?? 587).toString(),
    );
    _emailUserCtrl = TextEditingController(text: existing?.emailUser ?? '');
    _emailPasswordCtrl = TextEditingController();
    _toEmailsCtrl = TextEditingController(text: existing?.toEmails ?? '');
    _ccEmailsCtrl = TextEditingController(text: existing?.ccEmails ?? '');
    _emailUseTls = existing?.emailUseTls ?? true;
    _isActive = existing?.isActive ?? true;
    if (!_isEdit) {
      _loadDatabaseOptions();
    }
  }

  @override
  void dispose() {
    _databaseCtrl.dispose();
    _displayNameCtrl.dispose();
    _smtpServerCtrl.dispose();
    _smtpPortCtrl.dispose();
    _emailUserCtrl.dispose();
    _emailPasswordCtrl.dispose();
    _toEmailsCtrl.dispose();
    _ccEmailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final target = Target(
      databaseName: _databaseCtrl.text.trim(),
      displayName: _displayNameCtrl.text.trim(),
      smtpServer: _smtpServerCtrl.text.trim(),
      smtpPort: int.tryParse(_smtpPortCtrl.text.trim()) ?? 587,
      emailUser: _emailUserCtrl.text.trim(),
      emailPassword: _emailPasswordCtrl.text,
      emailUseTls: _emailUseTls,
      toEmails: _toEmailsCtrl.text.trim(),
      ccEmails: _ccEmailsCtrl.text.trim().isEmpty
          ? null
          : _ccEmailsCtrl.text.trim(),
      isActive: _isActive,
    );

    try {
      if (_isEdit) {
        await widget.client.updateTarget(
          target,
          updatePassword: _emailPasswordCtrl.text.isNotEmpty,
        );
      } else {
        await widget.client.addTarget(target);
      }
      if (mounted) Navigator.pop(context, true);
    } on DatabaseException catch (e) {
      setState(() => _isSaving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _loadDatabaseOptions() async {
    setState(() {
      _isLoadingDatabases = true;
      _databaseLoadError = null;
    });

    try {
      final options = await widget.client.getAvailableReportDatabases();
      if (!mounted) return;
      setState(() => _databaseOptions = options);
    } on DatabaseException catch (e) {
      if (!mounted) return;
      setState(() => _databaseLoadError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _databaseLoadError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingDatabases = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border, width: 1),
      ),
      child: Container(
        width: 620,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isEdit ? 'Edit Report Target' : 'Add Report Target',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Spacer(),
                    IconButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      icon: Icon(Icons.close, size: 20),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _databasePicker()),
                    SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        _displayNameCtrl,
                        'Display Name',
                        'Company display name',
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        _smtpServerCtrl,
                        'SMTP Server',
                        'mail.smartouch.com.my',
                        validator: _required,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        _smtpPortCtrl,
                        'SMTP Port',
                        '587',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        _emailUserCtrl,
                        'Email User',
                        'user@mail.com',
                        validator: _required,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _field(
                        _emailPasswordCtrl,
                        'Email Password',
                        _isEdit ? '(leave blank to keep current)' : 'password',
                        obscureText: _obscurePassword,
                        validator: _isEdit ? null : _required,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _field(
                  _toEmailsCtrl,
                  'To Emails',
                  'recipient@mail.com, another@mail.com',
                  validator: _required,
                ),
                SizedBox(height: 12),
                _field(_ccEmailsCtrl, 'CC Emails', 'optional@mail.com'),
                SizedBox(height: 16),
                Row(
                  children: [
                    _switch(
                      label: 'Use TLS',
                      value: _emailUseTls,
                      onChanged: (value) =>
                          setState(() => _emailUseTls = value),
                    ),
                    SizedBox(width: 24),
                    _switch(
                      label: 'Active',
                      value: _isActive,
                      onChanged: (value) => setState(() => _isActive = value),
                    ),
                    Spacer(),
                    OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      child: Text('Cancel'),
                    ),
                    SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isEdit ? 'Save' : 'Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  Widget _databasePicker() {
    if (_isEdit) {
      return _field(
        _databaseCtrl,
        'Database',
        'Database name',
        enabled: false,
        validator: _required,
      );
    }

    final selectedValue =
        _databaseOptions.any(
          (option) => option.databaseName == _databaseCtrl.text,
        )
        ? _databaseCtrl.text
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Database',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: selectedValue,
          isExpanded: true,
          menuMaxHeight: 320,
          items: _databaseOptions.map((option) {
            final status = option.stateDesc.isEmpty
                ? 'UNKNOWN'
                : option.stateDesc;
            return DropdownMenuItem<String>(
              value: option.databaseName,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      option.databaseName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    status,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: _isLoadingDatabases
              ? null
              : (value) {
                  setState(() {
                    _databaseCtrl.text = value ?? '';
                    if (_displayNameCtrl.text.trim().isEmpty && value != null) {
                      _displayNameCtrl.text = value;
                    }
                  });
                },
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Required' : null,
          decoration: InputDecoration(
            hintText: _isLoadingDatabases
                ? 'Loading databases...'
                : _databaseOptions.isEmpty
                ? 'No databases found'
                : 'Select database',
            suffixIcon: _isLoadingDatabases
                ? Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Refresh databases',
                    onPressed: _loadDatabaseOptions,
                    icon: Icon(Icons.refresh, size: 18),
                  ),
            isDense: true,
          ),
        ),
        if (_databaseLoadError != null) ...[
          SizedBox(height: 6),
          Text(
            _databaseLoadError!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.error, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool enabled = true,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffixIcon,
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _switch({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(value: value, onChanged: _isSaving ? null : onChanged),
        SizedBox(width: 6),
        Text(label, style: TextStyle(color: AppColors.textPrimary)),
      ],
    );
  }
}
