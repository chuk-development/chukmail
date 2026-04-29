import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import 'account_store.dart';
import 'db.dart';

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  return AccountStore.instance.all();
});

final accountByIdProvider =
    FutureProvider.family<Account?, String>((ref, id) async {
  return AccountStore.instance.byId(id);
});

final foldersProvider =
    FutureProvider.family<List<FolderRow>, String>((ref, accountId) async {
  final d = await AppDb.instance.db;
  final rows = await d.query('folders',
      where: 'account_id = ?', whereArgs: [accountId], orderBy: 'name ASC');
  return rows.map(FolderRow.fromMap).toList();
});

class MailboxKey {
  final String accountId;
  final String folderPath;
  const MailboxKey(this.accountId, this.folderPath);

  @override
  bool operator ==(Object other) =>
      other is MailboxKey &&
      other.accountId == accountId &&
      other.folderPath == folderPath;
  @override
  int get hashCode => Object.hash(accountId, folderPath);
}

final messagesProvider =
    FutureProvider.family<List<StoredMessage>, MailboxKey>((ref, key) async {
  final d = await AppDb.instance.db;
  final rows = await d.query('messages',
      where: 'account_id = ? AND folder_path = ?',
      whereArgs: [key.accountId, key.folderPath],
      orderBy: 'date DESC',
      limit: 200);
  return rows.map(StoredMessage.fromMap).toList();
});

final refreshTickProvider = StateProvider<int>((ref) => 0);
