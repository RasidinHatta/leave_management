import 'package:flutter/material.dart';
import 'package:leave_management/core/db_client.dart';
import 'package:leave_management/core/theme.dart';
import 'package:leave_management/core/constants.dart';

class ManageUsersScreen extends StatefulWidget {
  final String adminUsername;

  const ManageUsersScreen({super.key, required this.adminUsername});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  List<dynamic> _users = [];
  List<dynamic> _filteredUsers = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';

  // Database targets
  List<Map<String, dynamic>> _targets = [];
  String? _selectedDatabase;
  bool _loadingDatabases = false;

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    if (kDatabaseName.isNotEmpty) {
      _selectedDatabase = kDatabaseName;
      _fetchUsers();
    } else {
      await _fetchDatabases();
    }
  }

  Future<void> _fetchDatabases() async {
    _targets = [];
    _selectedDatabase = kDatabaseName;
    setState(() => _loadingDatabases = false);
    if (_selectedDatabase != null && _selectedDatabase!.isNotEmpty) {
      _fetchUsers();
    }
  }

  Future<void> _fetchUsers() async {
    if (_selectedDatabase == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await DirectDbClient().getUsers(
        widget.adminUsername,
        _selectedDatabase!,
      );
      setState(() {
        _users = data
            .where(
              (u) =>
                  ((u as Map<String, dynamic>)['role'] as String? ?? 'USER')
                      .toUpperCase() !=
                  'ADMIN',
            )
            .toList();
        _filterUsers();
      });
    } on DatabaseException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'An unexpected error occurred: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterUsers() {
    setState(() {
      if (_searchQuery.trim().isEmpty) {
        _filteredUsers = List.from(_users);
      } else {
        final query = _searchQuery.toLowerCase().trim();
        _filteredUsers = _users.where((u) {
          final username = (u['username'] as String? ?? '').toLowerCase();
          final role = (u['role'] as String? ?? '').toLowerCase();
          return username.contains(query) || role.contains(query);
        }).toList();
      }
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        duration: Duration(seconds: 4),
      ),
    );
  }

  // ---- Dialogs ----

  void _showAddUserDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddUserDialog(
        dbClient: DirectDbClient(),
        adminUsername: widget.adminUsername,
        database: _selectedDatabase!,
        onSuccess: () {
          _showSnack('User added successfully.');
          _fetchUsers();
        },
      ),
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditUserDialog(
        dbClient: DirectDbClient(),
        adminUsername: widget.adminUsername,
        database: _selectedDatabase!,
        targetUser: user,
        onSuccess: () {
          _showSnack('User updated successfully.');
          _fetchUsers();
        },
      ),
    );
  }

  void _showDeleteConfirmDialog(String targetUsername) {
    if (targetUsername == widget.adminUsername) {
      _showSnack(
        'You cannot delete your own logged-in account.',
        isError: true,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm Deletion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete user "$targetUsername"?',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            SizedBox(height: 12),
            Text(
              '⚠️ This action is permanent and cannot be undone.',
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                await DirectDbClient().deleteUser(
                  widget.adminUsername,
                  targetUsername,
                  _selectedDatabase!,
                );
                _showSnack('User "$targetUsername" deleted successfully.');
                _fetchUsers();
              } on DatabaseException catch (e) {
                _showSnack(e.message, isError: true);
                setState(() => _isLoading = false);
              } catch (e) {
                _showSnack('Delete failed: ${e.toString()}', isError: true);
                setState(() => _isLoading = false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('Delete User'),
          ),
        ],
      ),
    );
  }

  // ---- Widgets ----

  Widget _buildRoleBadge(String role) {
    Color bg;
    Color text;
    IconData icon;

    switch (role.toUpperCase()) {
      case 'REPORT':
        bg = Color(0xFF78350F);
        text = Color(0xFFFDE68A);
        icon = Icons.fact_check_outlined;
        break;
      default: // USER
        bg = Color(0xFF064E3B); // Emerald background
        text = Color(0xFFA7F3D0); // Emerald text
        icon = Icons.person_outline;
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: text.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: text, size: 14),
          SizedBox(width: 6),
          Text(
            role,
            style: TextStyle(
              color: text,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            SizedBox(height: 20),
            _buildToolbar(),
            SizedBox(height: 16),
            Expanded(
              child: _isLoading && _users.isEmpty
                  ? Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _buildErrorWidget()
                  : _buildUsersTable(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.people_outline,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage Users',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'List, add, update roles/passwords, or delete users',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (_selectedDatabase != null && !_isLoading && _error == null)
          ElevatedButton.icon(
            onPressed: _showAddUserDialog,
            icon: Icon(Icons.person_add_outlined, size: 16),
            label: Text('Add User'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Search user field
        SizedBox(
          width: 300,
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search user or role...',
              prefixIcon: Icon(Icons.search, size: 16),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _searchQuery = '';
                          _filterUsers();
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
                _filterUsers();
              });
            },
          ),
        ),

        // Database switch dropdown (if multi-database is in play)
        if (kDatabaseName.isEmpty)
          SizedBox(
            width: 250,
            child: _loadingDatabases
                ? SizedBox(
                    height: 36,
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
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
                      labelText: 'Database',
                      prefixIcon: Icon(Icons.storage_outlined, size: 16),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
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
                      if (val != null) {
                        setState(() {
                          _selectedDatabase = val;
                        });
                        _fetchUsers();
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
                  size: 15,
                  color: AppColors.primaryLight,
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

        // Manual refresh button
        IconButton(
          icon: Icon(Icons.refresh, size: 18),
          color: AppColors.textSecondary,
          tooltip: 'Refresh user list',
          onPressed: _fetchUsers,
        ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: 450),
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
              onPressed: _fetchUsers,
              icon: Icon(Icons.refresh, size: 16),
              label: Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTable() {
    if (_filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.15),
            ),
            SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No users found matching "$_searchQuery"'
                  : 'No users registered in this system.',
              style: TextStyle(color: AppColors.textSecondary),
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
          // Header row
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
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
                    'USERNAME',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ACCESS ROLE',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'ACTIONS',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _filteredUsers.length,
              separatorBuilder: (ctx, index) => Divider(height: 1),
              itemBuilder: (ctx, index) {
                final user = _filteredUsers[index] as Map<String, dynamic>;
                final username = user['username'] as String? ?? '—';
                final role = user['role'] as String? ?? 'USER';
                final isSelf = username == widget.adminUsername;

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Icon(
                              Icons.account_circle_outlined,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                username,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSelf) ...[
                              SizedBox(width: 8),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'YOU',
                                  style: TextStyle(
                                    color: AppColors.primaryLight,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildRoleBadge(role),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit_outlined, size: 16),
                              color: AppColors.primaryLight,
                              tooltip: 'Edit User Role/Password',
                              onPressed: () => _showEditUserDialog(user),
                            ),
                            SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 16),
                              color: isSelf
                                  ? AppColors.textDisabled
                                  : AppColors.error,
                              tooltip: isSelf
                                  ? 'Cannot delete yourself'
                                  : 'Delete User',
                              onPressed: isSelf
                                  ? null
                                  : () => _showDeleteConfirmDialog(username),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Internal Add User Dialog
// =============================================================================
class _AddUserDialog extends StatefulWidget {
  final DirectDbClient dbClient;
  final String adminUsername;
  final String database;
  final VoidCallback onSuccess;

  const _AddUserDialog({
    required this.dbClient,
    required this.adminUsername,
    required this.database,
    required this.onSuccess,
  });

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _selectedRole = 'USER';
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.dbClient.addUser(
        widget.adminUsername,
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
        _selectedRole,
        widget.database,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
      }
    } on DatabaseException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Add user failed: ${e.toString()}';
        _isLoading = false;
      });
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
        width: 420,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add New User',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary,
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              Divider(height: 20),
              if (_errorMessage != null) ...[
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
                SizedBox(height: 16),
              ],
              Text(
                'Username',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 6),
              TextFormField(
                controller: _usernameCtrl,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter username',
                  prefixIcon: Icon(Icons.person_outline, size: 16),
                  isDense: true,
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Username is required'
                    : null,
              ),
              SizedBox(height: 16),
              Text(
                'Password',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 6),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter password',
                  prefixIcon: Icon(Icons.lock_outline, size: 16),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 16,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Password is required' : null,
              ),
              SizedBox(height: 16),
              Text(
                'Access Role',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                dropdownColor: AppColors.surfaceElevated,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'REPORT',
                    child: Text('Report (Leave Report Config only)'),
                  ),
                  DropdownMenuItem(
                    value: 'USER',
                    child: Text('User (Standard menu)'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedRole = val);
                  }
                },
              ),
              SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: Text('Cancel'),
                  ),
                  SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('Create User'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Internal Edit User Dialog
// =============================================================================
class _EditUserDialog extends StatefulWidget {
  final DirectDbClient dbClient;
  final String adminUsername;
  final String database;
  final Map<String, dynamic> targetUser;
  final VoidCallback onSuccess;

  const _EditUserDialog({
    required this.dbClient,
    required this.adminUsername,
    required this.database,
    required this.targetUser,
    required this.onSuccess,
  });

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  late String _selectedRole;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final role = (widget.targetUser['role'] as String? ?? 'USER')
        .toUpperCase()
        .trim();
    _selectedRole = role == 'REPORT' ? 'REPORT' : 'USER';
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final newPass = _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text;

    try {
      await widget.dbClient.updateUser(
        widget.adminUsername,
        widget.targetUser['username'] as String,
        newPass,
        _selectedRole,
        widget.database,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
      }
    } on DatabaseException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Update user failed: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.targetUser['username'] as String;

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border, width: 1),
      ),
      child: Container(
        width: 420,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Edit User: $username',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18),
                    color: AppColors.textSecondary,
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              Divider(height: 20),
              if (_errorMessage != null) ...[
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
                SizedBox(height: 16),
              ],
              Text(
                'Username (Read-Only)',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 6),
              TextFormField(
                initialValue: username,
                enabled: false,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.person_outline, size: 16),
                  isDense: true,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'New Password',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 6),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Leave empty to keep current password',
                  prefixIcon: Icon(Icons.lock_outline, size: 16),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 16,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Access Role',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                dropdownColor: AppColors.surfaceElevated,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'REPORT',
                    child: Text('Report (Leave Report Config only)'),
                  ),
                  DropdownMenuItem(
                    value: 'USER',
                    child: Text('User (Standard menu)'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedRole = val);
                  }
                },
              ),
              SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: Text('Cancel'),
                  ),
                  SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('Save Changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
