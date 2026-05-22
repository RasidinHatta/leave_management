import 'package:flutter/material.dart';
import 'package:leave_management/core/constants.dart';
import 'package:leave_management/core/theme.dart';
import 'package:leave_management/screens/bring_forward_screen.dart';
import 'package:leave_management/screens/leave_taken_screen.dart';
import 'package:leave_management/screens/targets_screen.dart';
import 'package:leave_management/screens/manage_users_screen.dart';
import 'package:leave_management/main.dart';

// ---------------------------------------------------------------------------
// Navigation items
// ---------------------------------------------------------------------------
enum _Nav { bringForward, leaveTaken, targets, manageUsers }

class _SidebarItem {
  final IconData icon;
  final String label;
  final _Nav nav;
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.nav,
  });
}

// ---------------------------------------------------------------------------
// Home screen — shell with persistent left sidebar
// ---------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final String username;
  final String role;

  const HomeScreen({
    super.key,
    required this.onLogout,
    required this.username,
    required this.role,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Nav _current = _Nav.bringForward;

  @override
  void initState() {
    super.initState();
  }

  static const _mainItems = [
    _SidebarItem(
      icon: Icons.arrow_circle_right_outlined,
      label: 'Bring Forward',
      nav: _Nav.bringForward,
    ),
    _SidebarItem(
      icon: Icons.event_busy_outlined,
      label: 'Leave Taken',
      nav: _Nav.leaveTaken,
    ),
  ];

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: Text('Logout "${widget.username}"?'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _confirmLogout();
      },
      child: Scaffold(
        body: Row(
          children: [
            _buildSidebar(),
            Container(width: 1, color: AppColors.border),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  // ---- Sidebar -------------------------------------------------------------
  Widget _buildSidebar() {
    return Container(
      width: 232,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLogo(),
          const SizedBox(height: 4),
          _buildSection('MAIN', _mainItems),
          const SizedBox(height: 8),
          if (widget.role.toUpperCase() == 'ADMIN') ...[
            _buildSection('CONFIGURATION', [
              const _SidebarItem(
                icon: Icons.storage_outlined,
                label: 'DB Targets',
                nav: _Nav.targets,
              ),
              if (widget.role.toUpperCase() == 'ADMIN')
                const _SidebarItem(
                  icon: Icons.people_outline,
                  label: 'Manage Users',
                  nav: _Nav.manageUsers,
                ),
            ]),
            const SizedBox(height: 8),
          ],
          const Spacer(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.event_available,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HR Leave',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                'Management',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<_SidebarItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...items.map(_buildNavBtn),
      ],
    );
  }

  Widget _buildNavBtn(_SidebarItem item) {
    final selected = _current == item.nav;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        onTap: () => setState(() => _current = item.nav),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 16,
                color: selected
                    ? AppColors.primaryLight
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: selected
                        ? AppColors.primaryLight
                        : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (selected)
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kDatabaseName.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.storage_outlined,
                  size: 12,
                  color: AppColors.primaryLight,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'DB: $kDatabaseName',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$kServerName / $kDriverName',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: _showSettingsDialog,
                icon: const Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                tooltip: 'Settings',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _confirmLogout,
                icon: const Icon(
                  Icons.logout_outlined,
                  size: 16,
                  color: AppColors.error,
                ),
                tooltip: 'Logout ${widget.username}',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          child: Container(
            width: 400,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                const SizedBox(height: 16),
                Text(
                  'App Font Size',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<double>(
                  valueListenable: LeaveManagementApp.fontSizeNotifier,
                  builder: (context, factor, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: factor,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: AppColors.textSecondary,
                          ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textPrimary),
                          items: const [
                            DropdownMenuItem(
                              value: 0.75,
                              child: Text('Extra Small'),
                            ),
                            DropdownMenuItem(
                              value: 0.85,
                              child: Text('Small (Default)'),
                            ),
                            DropdownMenuItem(
                              value: 1.00,
                              child: Text('Medium'),
                            ),
                            DropdownMenuItem(value: 1.15, child: Text('Large')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              LeaveManagementApp.fontSizeNotifier.value = val;
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Close',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Content area --------------------------------------------------------
  Widget _buildContent() {
    switch (_current) {
      case _Nav.bringForward:
        return const BringForwardScreen();
      case _Nav.leaveTaken:
        return const LeaveTakenScreen();
      case _Nav.targets:
        return const TargetsScreen();
      case _Nav.manageUsers:
        return ManageUsersScreen(adminUsername: widget.username);
    }
  }
}
