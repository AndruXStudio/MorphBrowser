import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/browser_models.dart';

class StorageService {
  static const _kBookmarks = 'bookmarks';
  static const _kHistory = 'history';
  static const _kHome = 'home_url';
  static const _kSearchEngine = 'search_engine';

  Future<List<BookmarkItem>> loadBookmarks() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kBookmarks) ?? [];
    return raw
        .map((e) =>
            BookmarkItem.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveBookmarks(List<BookmarkItem> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _kBookmarks,
      items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<List<HistoryItem>> loadHistory() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kHistory) ?? [];
    return raw
        .map(
            (e) => HistoryItem.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveHistory(List<HistoryItem> items) async {
    final p = await SharedPreferences.getInstance();
    final trimmed = items.length > 500 ? items.sublist(0, 500) : items;
    await p.setStringList(
      _kHistory,
      trimmed.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<String> loadHomeUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kHome) ?? 'https://www.google.com';
  }

  Future<void> saveHomeUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHome, url);
  }

  Future<String> loadSearchEngine() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kSearchEngine) ?? 'google';
  }

  Future<void> saveSearchEngine(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSearchEngine, id);
  }
}
