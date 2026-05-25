import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:leave_management/core/theme.dart';

class AppSettingsData {
  final AppAppearance appearance;
  final double fontScale;

  const AppSettingsData({required this.appearance, required this.fontScale});

  static const defaults = AppSettingsData(
    appearance: AppAppearance(),
    fontScale: 0.85,
  );
}

class AppSettings {
  static Future<AppSettingsData> load() async {
    if (kIsWeb) return AppSettingsData.defaults;

    try {
      final file = await _settingsFile();
      if (!await file.exists()) return AppSettingsData.defaults;

      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;

      return AppSettingsData(
        appearance: AppAppearance(
          mode: _themeModeFromName(json['themeMode']?.toString()),
          palette: _paletteFromName(json['palette']?.toString()),
        ),
        fontScale:
            (json['fontScale'] as num?)?.toDouble() ??
            AppSettingsData.defaults.fontScale,
      );
    } catch (_) {
      return AppSettingsData.defaults;
    }
  }

  static Future<void> save(AppSettingsData settings) async {
    if (kIsWeb) return;

    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      JsonEncoder.withIndent('  ').convert({
        'themeMode': settings.appearance.mode.name,
        'palette': settings.appearance.palette.name,
        'fontScale': settings.fontScale,
      }),
    );
  }

  static Future<File> _settingsFile() async {
    final appData = Platform.environment['APPDATA'];
    final basePath = appData != null && appData.trim().isNotEmpty
        ? appData
        : File(Platform.resolvedExecutable).parent.path;
    return File(
      '$basePath${Platform.pathSeparator}leave_management'
      '${Platform.pathSeparator}settings.json',
    );
  }

  static AppThemeMode _themeModeFromName(String? name) {
    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => AppSettingsData.defaults.appearance.mode,
    );
  }

  static AppPalette _paletteFromName(String? name) {
    return AppPalette.values.firstWhere(
      (palette) => palette.name == name,
      orElse: () => AppSettingsData.defaults.appearance.palette,
    );
  }
}
