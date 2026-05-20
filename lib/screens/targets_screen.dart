import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leave_management/core/api_client.dart';
import 'package:leave_management/core/theme.dart';
import 'package:leave_management/models/target.dart';

// =============================================================================
// Targets Screen — CRUD for database target configurations
// =============================================================================
class TargetsScreen extends StatefulWidget {
  final ApiClient apiClient;
  const TargetsScreen({super.key, required this.apiClient});

  @override
  State<TargetsScreen> createState() => _TargetsScreenState();
}

class _TargetsScreenState extends State<TargetsScreen> {
  List<Target> _targets = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await widget.apiClient.getTargets();
      setState(() => _targets = data.map(Target.fromJson).toList());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showDialog(Target? existing) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _TargetDialog(apiClient: widget.apiClient, existing: existing),
    );
    if (ok == true) _load();
  }

  Future<void> _delete(Target t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Target'),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            children: [
              const TextSpan(text: 'Delete '),
              TextSpan(
                text: t.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: ' (${t.databaseName})',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const TextSpan(text: '?\n\nThis cannot be undone.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.apiClient.deleteTarget(t.databaseName);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted ${t.databaseName}')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              _buildError()
            else
              Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.storage_outlined,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Database Targets',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Manage company database & email configurations',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Refresh'),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () => _showDialog(null),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Target'),
        ),
      ],
    );
  }

  Expanded _buildError() {
    return Expanded(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.errorBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 40),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_targets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storage_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            const Text(
              'No database targets configured yet',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _showDialog(null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add First Target'),
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
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _targets.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _buildRow(_targets[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    const style = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('DATABASE', style: style)),
          Expanded(flex: 2, child: Text('DISPLAY NAME', style: style)),
          Expanded(flex: 2, child: Text('EMAIL', style: style)),
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

  Widget _buildRow(Target t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              t.databaseName,
              style: const TextStyle(
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
              t.displayName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              t.emailUser,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              t.toEmails,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.isActive
                      ? AppColors.successBg
                      : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: t.isActive
                        ? AppColors.success.withValues(alpha: 0.4)
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  t.isActive ? 'Active' : 'Inactive',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.isActive
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
                  onPressed: () => _showDialog(t),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  color: AppColors.primary,
                  tooltip: 'Edit',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  onPressed: () => _delete(t),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: AppColors.error,
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Add / Edit Dialog
// =============================================================================
class _TargetDialog extends StatefulWidget {
  final ApiClient apiClient;
  final Target? existing;
  const _TargetDialog({required this.apiClient, this.existing});

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _dbNameCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _smtpServerCtrl;
  late final TextEditingController _smtpPortCtrl;
  late final TextEditingController _emailUserCtrl;
  late final TextEditingController _emailPasswordCtrl;
  late final TextEditingController _toEmailsCtrl;
  late final TextEditingController _ccEmailsCtrl;

  bool _emailUseTls = false;
  bool _isActive = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _dbNameCtrl = TextEditingController(text: e?.databaseName ?? '');
    _displayNameCtrl = TextEditingController(text: e?.displayName ?? '');
    _smtpServerCtrl = TextEditingController(text: e?.smtpServer ?? 'mail.smartouch.com.my');
    _smtpPortCtrl = TextEditingController(text: e?.smtpPort?.toString() ?? '587');
    _emailUserCtrl = TextEditingController(text: e?.emailUser ?? '');
    _emailPasswordCtrl = TextEditingController(text: e?.emailPassword ?? '');
    _toEmailsCtrl = TextEditingController(text: e?.toEmails ?? '');
    _ccEmailsCtrl = TextEditingController(text: e?.ccEmails ?? '');
    _emailUseTls = e?.emailUseTls ?? true;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _dbNameCtrl,
      _displayNameCtrl,
      _smtpServerCtrl,
      _smtpPortCtrl,
      _emailUserCtrl,
      _emailPasswordCtrl,
      _toEmailsCtrl,
      _ccEmailsCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final data = <String, dynamic>{
      'databaseName': _dbNameCtrl.text.trim(),
      'displayName': _displayNameCtrl.text.trim(),
      'emailUser': _emailUserCtrl.text.trim().isEmpty ? 'username@mail.com' : _emailUserCtrl.text.trim(),
      'toEmails': _toEmailsCtrl.text.trim().isEmpty ? 'username@mail.com' : _toEmailsCtrl.text.trim(),
      'emailUseTls': _emailUseTls,
      'isActive': _isActive,
    };
    if (!_isEdit || _emailPasswordCtrl.text.isNotEmpty) {
      data['emailPassword'] = _emailPasswordCtrl.text.isEmpty ? 'password' : _emailPasswordCtrl.text;
    }
    if (_smtpServerCtrl.text.trim().isNotEmpty) {
      data['smtpServer'] = _smtpServerCtrl.text.trim();
    }
    if (_smtpPortCtrl.text.trim().isNotEmpty) {
      data['smtpPort'] = int.parse(_smtpPortCtrl.text.trim());
    }
    if (_ccEmailsCtrl.text.trim().isNotEmpty) {
      data['ccEmails'] = _ccEmailsCtrl.text.trim();
    }

    try {
      if (_isEdit) {
        await widget.apiClient.editTarget(widget.existing!.databaseName, data);
      } else {
        await widget.apiClient.addTarget(data);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      child: Container(
          width: 600,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isEdit ? 'Edit Target' : 'Add Target',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Configure the email settings for the HR leave report target.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 20),
                        color: AppColors.textSecondary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Fields grid
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _field(
                          _dbNameCtrl,
                          'Database Name',
                          'MYPAY_LCO',
                          enabled: !_isEdit,
                          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                          tooltip: 'The unique name of the target database (e.g. MYPAY_JSM).',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _field(
                          _displayNameCtrl,
                          'Display Name',
                          'Company Name',
                          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                          tooltip: 'The company or department display name (e.g. JSM SYNERGY SDN. BHD.).',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _field(
                          _smtpServerCtrl,
                          'SMTP Server',
                          'mail.smartouch.com.my',
                          tooltip: 'The outgoing SMTP server host address.',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _field(
                          _smtpPortCtrl,
                          'SMTP Port',
                          '587',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          tooltip: 'The connection port for the SMTP server (e.g. 587, 465, or 25).',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _field(
                          _emailUserCtrl,
                          'Email User',
                          'rasidin@smartouch.com.my',
                          tooltip: 'The email address username used to authenticate and send the reports.',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _field(
                          _emailPasswordCtrl,
                          'Email Password',
                          _isEdit ? '(leave blank to keep current)' : '••••••••',
                          obscureText: _obscurePassword,
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
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            splashRadius: 18,
                          ),
                          tooltip: 'The password or authentication key for the SMTP server. Leave blank when editing to keep current.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  _field(
                    _toEmailsCtrl,
                    'To Emails (comma-separated)',
                    'rasidinhatta7@gmail.com',
                    tooltip: 'The main recipient email addresses, separated by commas.',
                  ),
                  const SizedBox(height: 10),

                  _field(
                    _ccEmailsCtrl,
                    'CC Emails (comma-separated, optional)',
                    'rasidin@smartouch.com.my',
                    tooltip: 'Optional copy recipient email addresses, separated by commas.',
                  ),
                  const SizedBox(height: 16),

                  // Toggles and Save
                  Row(
                    children: [
                      _CustomToggleSwitch(
                        value: _emailUseTls,
                        onChanged: (v) => setState(() => _emailUseTls = v),
                        label: 'Use TLS',
                      ),
                      const SizedBox(width: 24),
                      _CustomToggleSwitch(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        label: 'Active',
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          disabledBackgroundColor: AppColors.textDisabled,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onPrimary,
                                ),
                              )
                            : Text(
                                _isEdit ? 'Save' : 'Add',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.onPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    bool enabled = true,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool obscureText = false,
    Widget? suffixIcon,
    String? tooltip,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (tooltip != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: tooltip,
                child: Icon(
                  Icons.info_outline,
                  size: 14 * (theme.textTheme.bodyMedium?.fontSize ?? 13) / 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          enabled: enabled,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          obscureText: obscureText,
          onFieldSubmitted: (_) => _save(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: enabled ? AppColors.textPrimary : AppColors.textDisabled,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            fillColor: enabled ? AppColors.surface : AppColors.surface.withValues(alpha: 0.5),
            filled: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            suffixIcon: suffixIcon,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border, width: 1.0),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border, width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error, width: 1.0),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Custom Toggle Switch Widget
// =============================================================================
class _CustomToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  const _CustomToggleSwitch({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: value ? AppColors.primary : AppColors.border,
                border: Border.all(
                  color: value ? AppColors.primary : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 150),
                    alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(1.0),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
