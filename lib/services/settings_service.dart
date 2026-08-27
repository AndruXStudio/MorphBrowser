import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const _kTheme = 'theme_mode';
  static const _kZoom = 'page_zoom';
  static const _kAiBase = 'ai_base_url';
  static const _kAiModel = 'ai_model';
  static const _kSearchEngine = 'search_engine';

  ThemeMode themeMode = ThemeMode.system;
  double pageZoom = 1.0;
  String aiBaseUrl = 'http://127.0.0.1:11434';
  String aiModel = 'llama3.2';
  String searchEngine = 'google';
  bool ready = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_kTheme) ?? 'system';
    themeMode = switch (t) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    pageZoom = p.getDouble(_kZoom) ?? 1.0;
    aiBaseUrl = p.getString(_kAiBase) ?? 'http://127.0.0.1:11434';
    aiModel = p.getString(_kAiModel) ?? 'llama3.2';
    searchEngine = p.getString(_kSearchEngine) ?? 'google';
    ready = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kTheme,
      mode == ThemeMode.light
          ? 'light'
          : mode == ThemeMode.dark
              ? 'dark'
              : 'system',
    );
    notifyListeners();
  }

  Future<void> setZoom(double z) async {
    pageZoom = z.clamp(0.5, 3.0);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kZoom, pageZoom);
    notifyListeners();
  }

  Future<void> setAiBase(String url) async {
    aiBaseUrl = url.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAiBase, aiBaseUrl);
    notifyListeners();
  }

  Future<void> setAiModel(String model) async {
    aiModel = model.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAiModel, aiModel);
    notifyListeners();
  }

  Future<void> setSearchEngine(String id) async {
    searchEngine = id;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSearchEngine, id);
    notifyListeners();
  }
}
