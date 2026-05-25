import 'package:flutter/material.dart';
import 'package:leave_management/core/constants.dart';
import 'package:leave_management/core/db_client.dart';
import 'package:leave_management/core/theme.dart';

class TargetsScreen extends StatefulWidget {
  const TargetsScreen({super.key});

  @override
  State<TargetsScreen> createState() => _TargetsScreenState();
}

class _TargetsScreenState extends State<TargetsScreen> {
  bool _isTesting = false;
  String? _resultMessage;
  bool _isSuccess = false;

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _resultMessage = null;
    });

    try {
      await DirectDbClient().ensureConnected();
      setState(() {
        _isSuccess = true;
        _resultMessage = 'Connected to $kDatabaseName on $kServerName.';
      });
    } on DatabaseException catch (e) {
      setState(() {
        _isSuccess = false;
        _resultMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _resultMessage = e.toString();
      });
    } finally {
      setState(() => _isTesting = false);
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
            _buildConfigCard(),
            if (_resultMessage != null) ...[
              SizedBox(height: 16),
              _buildResultBanner(),
            ],
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
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.storage_outlined,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Database Configuration',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Loaded directly from config.ini',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        Spacer(),
        ElevatedButton.icon(
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
      ],
    );
  }

  Widget _buildConfigCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Server', kServerName),
          Divider(height: 22),
          _row('Database', kDatabaseName),
          Divider(height: 22),
          _row('Driver', kDriverName),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontFamily: 'monospace',
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultBanner() {
    return Container(
      width: double.infinity,
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
        ],
      ),
    );
  }
}
