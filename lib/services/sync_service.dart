import '../data/account_store.dart';
import '../data/db.dart';
import '../models/account.dart';
import 'imap_service.dart';
import 'notification_service.dart';

class SyncService {
  static Future<int> syncAccount(
    Account a, {
    int limit = 50,
    String? folderPath,
  }) async {
    final imap = ImapService(a);
    int total = 0;
    try {
      await imap.syncFolders();
      final d = await AppDb.instance.db;
      String targetPath;
      if (folderPath != null) {
        targetPath = folderPath;
      } else {
        final folders = await d.query('folders',
            where: 'account_id = ?', whereArgs: [a.id]);
        targetPath = 'INBOX';
        for (final f in folders) {
          if (f['role'] == 'inbox') targetPath = f['path'] as String;
        }
      }
      final newCount = await imap.syncFolder(targetPath, limit: limit);
      total += newCount;
      if (newCount > 0) {
        await NotificationService.instance.showNewMail(
          id: a.id.hashCode & 0x7fffffff,
          title: '${a.name}: $newCount new',
          body: a.email,
        );
      }
    } finally {
      await imap.disconnect();
    }
    return total;
  }

  static Future<int> syncAll() async {
    int total = 0;
    final accounts = await AccountStore.instance.all();
    for (final a in accounts) {
      try {
        total += await syncAccount(a);
      } catch (_) {
        // ignore per-account errors during background sync
      }
    }
    return total;
  }
}
