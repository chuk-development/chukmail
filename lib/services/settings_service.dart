import 'package:sqflite/sqflite.dart';

import '../data/db.dart';

class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const kBlockRemoteGlobal = 'block_remote_global';
  static const kSyncMinutes = 'sync_minutes';
  static const kThemeMode = 'theme_mode';

  Future<String?> get(String k) async {
    final d = await AppDb.instance.db;
    final r = await d.query('settings', where: 'k = ?', whereArgs: [k]);
    if (r.isEmpty) return null;
    return r.first['v'] as String?;
  }

  Future<void> set(String k, String? v) async {
    final d = await AppDb.instance.db;
    await d.insert('settings', {'k': k, 'v': v},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> getBool(String k, {bool def = false}) async {
    final v = await get(k);
    if (v == null) return def;
    return v == '1' || v == 'true';
  }

  Future<int> getInt(String k, {int def = 0}) async {
    final v = await get(k);
    if (v == null) return def;
    return int.tryParse(v) ?? def;
  }

  Future<void> setBool(String k, bool v) => set(k, v ? '1' : '0');
  Future<void> setInt(String k, int v) => set(k, v.toString());
}
