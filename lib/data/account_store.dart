import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import 'db.dart';

class AccountStore {
  AccountStore._();
  static final AccountStore instance = AccountStore._();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _pwKey(String accountId) => 'pw_$accountId';

  Future<List<Account>> all() async {
    final d = await AppDb.instance.db;
    final rows = await d.query('accounts', orderBy: 'created_at ASC');
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> byId(String id) async {
    final d = await AppDb.instance.db;
    final rows = await d.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Account.fromMap(rows.first);
  }

  Future<void> insert(Account a, String password) async {
    final d = await AppDb.instance.db;
    await d.insert('accounts', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _secure.write(key: _pwKey(a.id), value: password);
  }

  Future<void> update(Account a, {String? newPassword}) async {
    final d = await AppDb.instance.db;
    await d.update('accounts', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
    if (newPassword != null) {
      await _secure.write(key: _pwKey(a.id), value: newPassword);
    }
  }

  Future<void> delete(String id) async {
    final d = await AppDb.instance.db;
    await d.delete('accounts', where: 'id = ?', whereArgs: [id]);
    await _secure.delete(key: _pwKey(id));
  }

  Future<String?> password(String id) => _secure.read(key: _pwKey(id));
}
