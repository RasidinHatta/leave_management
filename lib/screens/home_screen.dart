import 'package:flutter/material.dart';
import 'package:leave_management/core/constants.dart';
import 'package:leave_management/core/theme.dart';
import 'package:leave_management/screens/bring_forward_screen.dart';
import 'package:leave_management/screens/leave_taken_screen.dart';
import 'package:leave_management/screens/leave_report_config_screen.dart';
import 'package:leave_management/screens/targets_screen.dart';
import 'package:leave_management/screens/manage_users_screen.dart';
import 'package:leave_management/main.dart';

// ---------------------------------------------------------------------------
// Navigation items
// ---------------------------------------------------------------------------
enum _Nav { bringForward, leaveTaken, targets, leaveReportConfig, manageUsers }

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
  static const _settingsAmber = Color(0xFFF59E0B);
  static const _settingsAmberTintDark = Color(0xFF2D2008);
  static const _settingsAmberTintLight = Color(0xFFFFF7E6);

  final ScrollController _settingsScrollCtrl = ScrollController();
  _Nav _current = _Nav.bringForward;

  @override
  void initState() {
    super.initState();
    if (_role == 'REPORT') {
      _current = _Nav.leaveReportConfig;
    }
  }

  @override
  void dispose() {
    _settingsScrollCtrl.dispose();
    super.dispose();
  }

  String get _role => widget.role.toUpperCase().trim();

  static final _mainItems = [
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
        title: Text('Confirm Logout'),
        content: Text('Logout "${widget.username}"?'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('Logout'),
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
          SizedBox(height: 4),
          if (_role == 'ADMIN' || _role == 'USER') ...[
            _buildSection('MAIN', _mainItems),
            SizedBox(height: 8),
          ],
          if (_role == 'ADMIN') ...[
            _buildSection('CONFIGURATION', [
              _SidebarItem(
                icon: Icons.storage_outlined,
                label: 'DB Targets',
                nav: _Nav.targets,
              ),
              _SidebarItem(
                icon: Icons.fact_check_outlined,
                label: 'Leave Report Config',
                nav: _Nav.leaveReportConfig,
              ),
              _SidebarItem(
                icon: Icons.people_outline,
                label: 'Manage Users',
                nav: _Nav.manageUsers,
              ),
            ]),
            SizedBox(height: 8),
          ] else if (_role == 'REPORT') ...[
            _buildSection('CONFIGURATION', [
              _SidebarItem(
                icon: Icons.fact_check_outlined,
                label: 'Leave Report Config',
                nav: _Nav.leaveReportConfig,
              ),
            ]),
            SizedBox(height: 8),
          ],
          Spacer(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.event_available, color: Colors.white, size: 18),
          ),
          SizedBox(width: 10),
          Column(
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
          padding: EdgeInsets.fromLTRB(18, 8, 18, 4),
          child: Text(
            title,
            style: TextStyle(
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
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        onTap: () => setState(() => _current = item.nav),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
              SizedBox(width: 10),
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
                  decoration: BoxDecoration(
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
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kDatabaseName.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.storage_outlined,
                  size: 12,
                  color: AppColors.primaryLight,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'DB: $kDatabaseName',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
          ],
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$kServerName / $kDriverName',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: _showSettingsDialog,
                icon: Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                tooltip: 'Settings',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
              SizedBox(width: 12),
              IconButton(
                onPressed: _confirmLogout,
                icon: Icon(
                  Icons.logout_outlined,
                  size: 16,
                  color: AppColors.error,
                ),
                tooltip: 'Logout ${widget.username}',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
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
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: AppColors.border, width: 1),
          ),
          child: Container(
            width: 500,
            constraints: BoxConstraints(maxHeight: 660),
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: RawScrollbar(
                    controller: _settingsScrollCtrl,
                    thumbVisibility: true,
                    radius: Radius.circular(999),
                    thickness: 6,
                    thumbColor: AppColors.border,
                    crossAxisMargin: 2,
                    child: SingleChildScrollView(
                      controller: _settingsScrollCtrl,
                      padding: EdgeInsets.only(right: 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Settings',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: Icon(Icons.close, size: 20),
                                color: AppColors.textSecondary,
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(
                                  minWidth: 42,
                                  minHeight: 34,
                                ),
                                splashRadius: 20,
                              ),
                            ],
                          ),
                          SizedBox(height: 26),
                          _sectionLabel('Display Mode'),
                          SizedBox(height: 10),
                          ValueListenableBuilder<AppAppearance>(
                            valueListenable:
                                LeaveManagementApp.appearanceNotifier,
                            builder: (context, appearance, child) {
                              return Row(
                                children: [
                                  Expanded(
                                    child: _appearanceOption(
                                      label: 'Dark',
                                      icon: Icons.dark_mode_outlined,
                                      selected:
                                          appearance.mode == AppThemeMode.dark,
                                      onTap: () {
                                        LeaveManagementApp
                                            .appearanceNotifier
                                            .value = appearance.copyWith(
                                          mode: AppThemeMode.dark,
                                        );
                                      },
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: _appearanceOption(
                                      label: 'Light',
                                      icon: Icons.light_mode_outlined,
                                      selected:
                                          appearance.mode == AppThemeMode.light,
                                      onTap: () {
                                        LeaveManagementApp
                                            .appearanceNotifier
                                            .value = appearance.copyWith(
                                          mode: AppThemeMode.light,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          SizedBox(height: 26),
                          _sectionLabel('Color Theme'),
                          SizedBox(height: 12),
                          ValueListenableBuilder<AppAppearance>(
                            valueListenable:
                                LeaveManagementApp.appearanceNotifier,
                            builder: (context, appearance, child) {
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                itemCount: AppPalette.values.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                      childAspectRatio: 2.35,
                                    ),
                                itemBuilder: (context, index) {
                                  final palette = AppPalette.values[index];
                                  return _paletteOption(
                                    palette: palette,
                                    selected: appearance.palette == palette,
                                    onTap: () {
                                      LeaveManagementApp
                                          .appearanceNotifier
                                          .value = appearance.copyWith(
                                        palette: palette,
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                          SizedBox(height: 26),
                          _sectionLabel('App Font Size'),
                          SizedBox(height: 10),
                          ValueListenableBuilder<double>(
                            valueListenable:
                                LeaveManagementApp.fontSizeNotifier,
                            builder: (context, factor, child) {
                              return Container(
                                padding: EdgeInsets.symmetric(horizontal: 12),
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
                                    icon: Icon(
                                      Icons.keyboard_arrow_down,
                                      color: AppColors.textSecondary,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: AppColors.textPrimary,
                                        ),
                                    items: [
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
                                      DropdownMenuItem(
                                        value: 1.15,
                                        child: Text('Large'),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        LeaveManagementApp
                                                .fontSizeNotifier
                                                .value =
                                            val;
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _settingsAmber,
                      foregroundColor: Colors.white,
                      side: BorderSide(color: _settingsAmber),
                      padding: EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.7,
      ),
    );
  }

  Widget _appearanceOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? (AppColors.isDark
                    ? _settingsAmberTintDark
                    : _settingsAmberTintLight)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _settingsAmber : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? _settingsAmber : AppColors.textSecondary,
            ),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paletteOption({
    required AppPalette palette,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final swatches = _paletteSwatches(palette);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? (AppColors.isDark
                    ? _settingsAmberTintDark
                    : _settingsAmberTintLight)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _settingsAmber : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: swatches
                  .map(
                    (color) => Expanded(
                      child: Container(
                        height: 22,
                        margin: EdgeInsets.only(
                          right: color == swatches.last ? 0 : 6,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            SizedBox(height: 9),
            Text(
              _paletteLabel(palette),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 3),
            Text(
              _paletteDescription(palette),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Color> _paletteSwatches(AppPalette palette) {
    switch (palette) {
      case AppPalette.amberSunset:
        return [
          Color(0xFFF59E0B),
          Color(0xFFEF4444),
          Color(0xFFF97316),
          Color(0xFFFCD34D),
        ];
      case AppPalette.oceanBreeze:
        return [
          Color(0xFF3B82F6),
          Color(0xFF06B6D4),
          Color(0xFF0EA5E9),
          Color(0xFF93C5FD),
        ];
      case AppPalette.forestWalk:
        return [
          Color(0xFF10B981),
          Color(0xFF34D399),
          Color(0xFF6EE7B7),
          Color(0xFF065F46),
        ];
      case AppPalette.lavenderDusk:
        return [
          Color(0xFF8B5CF6),
          Color(0xFFEC4899),
          Color(0xFFA78BFA),
          Color(0xFFF9A8D4),
        ];
      case AppPalette.slatePro:
        return [
          Color(0xFF475569),
          Color(0xFF64748B),
          Color(0xFF94A3B8),
          Color(0xFFCBD5E1),
        ];
      case AppPalette.roseGold:
        return [
          Color(0xFFFB7185),
          Color(0xFFF43F5E),
          Color(0xFFFBBF24),
          Color(0xFFFDE68A),
        ];
    }
  }

  String _paletteLabel(AppPalette palette) {
    switch (palette) {
      case AppPalette.amberSunset:
        return 'Amber sunset';
      case AppPalette.oceanBreeze:
        return 'Ocean breeze';
      case AppPalette.forestWalk:
        return 'Forest walk';
      case AppPalette.lavenderDusk:
        return 'Lavender dusk';
      case AppPalette.slatePro:
        return 'Slate pro';
      case AppPalette.roseGold:
        return 'Rose gold';
    }
  }

  String _paletteDescription(AppPalette palette) {
    switch (palette) {
      case AppPalette.amberSunset:
        return 'Warm oranges & reds';
      case AppPalette.oceanBreeze:
        return 'Cool blues & cyans';
      case AppPalette.forestWalk:
        return 'Fresh greens & teal';
      case AppPalette.lavenderDusk:
        return 'Purples & pinks';
      case AppPalette.slatePro:
        return 'Neutral grays';
      case AppPalette.roseGold:
        return 'Pinks & warm golds';
    }
  }

  // ---- Content area --------------------------------------------------------
  Widget _buildContent() {
    switch (_current) {
      case _Nav.bringForward:
        return BringForwardScreen();
      case _Nav.leaveTaken:
        return LeaveTakenScreen();
      case _Nav.targets:
        return TargetsScreen();
      case _Nav.leaveReportConfig:
        return LeaveReportConfigScreen();
      case _Nav.manageUsers:
        return ManageUsersScreen(adminUsername: widget.username);
    }
  }
}
