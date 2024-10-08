import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sizzle_starter/src/core/utils/persisted_entry.dart';
import 'package:sizzle_starter/src/feature/app/model/app_theme.dart';

/// {@template theme_datasource}
/// [ThemeDataSource] is a data source that provides theme data.
///
/// This is used to set and get theme.
/// {@endtemplate}
abstract interface class ThemeDataSource {
  /// Set theme
  Future<void> setTheme(AppTheme theme);

  /// Get current theme from cache
  Future<AppTheme?> getTheme();
}

/// {@macro theme_datasource}
final class ThemeDataSourceLocal implements ThemeDataSource {
  /// {@macro theme_datasource}
  ThemeDataSourceLocal({
    required this.sharedPreferences,
    required this.codec,
  });

  /// The instance of [SharedPreferences] used to read and write values.
  final SharedPreferencesAsync sharedPreferences;

  /// Codec for [ThemeMode]
  final Codec<ThemeMode, String> codec;

  late final _seedColor = IntPreferencesEntry(
    sharedPreferences: sharedPreferences,
    key: 'theme.seed',
  );

  late final _themeMode = StringPreferencesEntry(
    sharedPreferences: sharedPreferences,
    key: 'theme.mode',
  );

  @override
  Future<void> setTheme(AppTheme theme) async {
    await _seedColor.setIfNullRemove(theme.seed.value);
    await _themeMode.setIfNullRemove(codec.encode(theme.mode));
  }

  @override
  Future<AppTheme?> getTheme() async {
    final seedColor = await _seedColor.read();
    final type = await _themeMode.read();

    if (type == null || seedColor == null) return null;

    return AppTheme(seed: Color(seedColor), mode: codec.decode(type));
  }
}
