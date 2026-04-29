import 'dart:async';

import 'package:enough_mail/enough_mail.dart';
import 'package:sqflite/sqflite.dart';

import '../data/account_store.dart';
import '../data/db.dart';
import '../models/account.dart';

class ImapService {
  final Account account;
  ImapClient? _client;

  ImapService(this.account);

  Future<ImapClient> _connect() async {
    if (_client != null && _client!.isLoggedIn) return _client!;
    final pw = await AccountStore.instance.password(account.id);
    if (pw == null) {
      throw StateError('No password stored for account ${account.email}');
    }
    final c = ImapClient(isLogEnabled: false);
    await c.connectToServer(account.imapHost, account.imapPort,
        isSecure: account.imapSsl);
    await c.login(account.username, pw);
    _client = c;
    return c;
  }

  Future<void> disconnect() async {
    try {
      await _client?.logout();
    } catch (_) {}
    _client = null;
  }

  Future<List<Mailbox>> listFolders() async {
    final c = await _connect();
    return c.listMailboxes(recursive: true);
  }

  Future<void> syncFolders() async {
    final boxes = await listFolders();
    final d = await AppDb.instance.db;
    final batch = d.batch();
    for (final b in boxes) {
      String? role;
      if (b.isInbox) {
        role = 'inbox';
      } else if (b.isSent) {
        role = 'sent';
      } else if (b.isDrafts) {
        role = 'drafts';
      } else if (b.isTrash) {
        role = 'trash';
      } else if (b.isJunk) {
        role = 'junk';
      } else if (b.isArchive) {
        role = 'archive';
      }
      batch.insert(
        'folders',
        {
          'account_id': account.id,
          'path': b.path,
          'name': b.name,
          'role': role,
          'unread': 0,
          'total': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> syncFolder(String folderPath, {int limit = 50}) async {
    final c = await _connect();
    final box = await c.selectMailboxByPath(folderPath);
    final d = await AppDb.instance.db;
    await d.update(
      'folders',
      {
        'unread': box.messagesUnseen,
        'total': box.messagesExists,
        'uid_validity': box.uidValidity,
        'uid_next': box.uidNext,
      },
      where: 'account_id = ? AND path = ?',
      whereArgs: [account.id, folderPath],
    );
    if (box.messagesExists == 0) return 0;
    final from = box.messagesExists - limit + 1;
    final start = from < 1 ? 1 : from;
    final seq = MessageSequence.fromRange(start, box.messagesExists);
    final fetch = await c.fetchMessages(seq,
        '(UID FLAGS RFC822.SIZE ENVELOPE BODYSTRUCTURE)');
    int newCount = 0;
    final batch = d.batch();
    for (final m in fetch.messages) {
      final uid = m.uid;
      if (uid == null) continue;
      final env = m.envelope;
      final fromList = m.from ?? env?.from ?? const <MailAddress>[];
      final fromAddr = fromList.isNotEmpty ? fromList.first : null;
      final toList = m.to ?? env?.to ?? const <MailAddress>[];
      final ccList = m.cc ?? env?.cc ?? const <MailAddress>[];
      final hasAttach = _hasAttachments(m);
      final exists = await d.query('messages',
          columns: ['id'],
          where: 'account_id = ? AND folder_path = ? AND uid = ?',
          whereArgs: [account.id, folderPath, uid]);
      final seen = m.isSeen;
      final flagged = m.isFlagged;
      final answered = m.isAnswered;
      final dateMs = (m.decodeDate() ?? env?.date)?.millisecondsSinceEpoch;
      final subject = m.decodeSubject() ?? env?.subject;
      final messageId =
          m.getHeaderValue('message-id') ?? env?.messageId;
      final data = {
        'account_id': account.id,
        'folder_path': folderPath,
        'uid': uid,
        'message_id': messageId,
        'subject': subject,
        'from_addr': fromAddr?.email,
        'from_name': fromAddr?.personalName,
        'to_addrs': toList.isEmpty ? null : toList.map((a) => a.email).join(','),
        'cc_addrs': ccList.isEmpty ? null : ccList.map((a) => a.email).join(','),
        'date': dateMs,
        'seen': seen ? 1 : 0,
        'flagged': flagged ? 1 : 0,
        'answered': answered ? 1 : 0,
        'has_attachments': hasAttach ? 1 : 0,
        'size_bytes': m.size,
      };
      if (exists.isEmpty) {
        batch.insert('messages', data,
            conflictAlgorithm: ConflictAlgorithm.replace);
        newCount++;
      } else {
        batch.update('messages', {
          'seen': data['seen'],
          'flagged': data['flagged'],
          'answered': data['answered'],
        }, where: 'id = ?', whereArgs: [exists.first['id']]);
      }
    }
    await batch.commit(noResult: true);
    return newCount;
  }

  bool _hasAttachments(MimeMessage m) {
    final parts = m.allPartsFlat;
    for (final p in parts) {
      final disp = p.getHeaderContentDisposition();
      if (disp?.disposition == ContentDisposition.attachment) return true;
    }
    return false;
  }

  Future<int> prefetchBodies(String folderPath, {int limit = 25}) async {
    final c = await _connect();
    await c.selectMailboxByPath(folderPath);
    final d = await AppDb.instance.db;
    final rows = await d.query(
      'messages',
      columns: ['id', 'uid'],
      where:
          'account_id = ? AND folder_path = ? AND full_fetched = 0',
      whereArgs: [account.id, folderPath],
      orderBy: 'date DESC',
      limit: limit,
    );
    if (rows.isEmpty) return 0;
    int fetched = 0;
    for (final r in rows) {
      final uid = r['uid'] as int;
      final id = r['id'] as int;
      try {
        final res = await c.uidFetchMessages(
            MessageSequence.fromIds([uid], isUid: true), 'BODY.PEEK[]');
        if (res.messages.isEmpty) continue;
        final full = res.messages.first;
        final plain = full.decodeTextPlainPart();
        final html = full.decodeTextHtmlPart();
        await d.update(
            'messages',
            {
              'body_plain': plain,
              'body_html': html,
              'preview': plain == null
                  ? null
                  : (plain.length > 200 ? plain.substring(0, 200) : plain),
              'full_fetched': 1,
            },
            where: 'id = ?',
            whereArgs: [id]);
        fetched++;
      } catch (_) {
        // skip — try next on transient errors
      }
    }
    return fetched;
  }

  Future<MimeMessage> fetchFull(String folderPath, int uid) async {
    final c = await _connect();
    await c.selectMailboxByPath(folderPath);
    final res = await c.uidFetchMessages(
        MessageSequence.fromIds([uid], isUid: true), 'BODY.PEEK[]');
    if (res.messages.isEmpty) {
      throw StateError('Message $uid not found in $folderPath');
    }
    return res.messages.first;
  }

  Future<void> setFlag(String folderPath, int uid, String flag,
      {bool add = true}) async {
    final c = await _connect();
    await c.selectMailboxByPath(folderPath);
    final seq = MessageSequence.fromIds([uid], isUid: true);
    if (add) {
      await c.uidStore(seq, [flag], action: StoreAction.add);
    } else {
      await c.uidStore(seq, [flag], action: StoreAction.remove);
    }
  }

  Future<void> markSeen(String folderPath, int uid, bool seen) async {
    await setFlag(folderPath, uid, '\\Seen', add: seen);
    final d = await AppDb.instance.db;
    await d.update('messages', {'seen': seen ? 1 : 0},
        where: 'account_id = ? AND folder_path = ? AND uid = ?',
        whereArgs: [account.id, folderPath, uid]);
  }

  Future<void> markFlagged(String folderPath, int uid, bool flagged) async {
    await setFlag(folderPath, uid, '\\Flagged', add: flagged);
    final d = await AppDb.instance.db;
    await d.update('messages', {'flagged': flagged ? 1 : 0},
        where: 'account_id = ? AND folder_path = ? AND uid = ?',
        whereArgs: [account.id, folderPath, uid]);
  }

  Future<void> deleteMessage(String folderPath, int uid) async {
    final c = await _connect();
    await c.selectMailboxByPath(folderPath);
    final seq = MessageSequence.fromIds([uid], isUid: true);
    await c.uidStore(seq, ['\\Deleted'], action: StoreAction.add);
    await c.expunge();
    final d = await AppDb.instance.db;
    await d.delete('messages',
        where: 'account_id = ? AND folder_path = ? AND uid = ?',
        whereArgs: [account.id, folderPath, uid]);
  }

  Future<void> moveMessage(String fromPath, int uid, String toPath) async {
    final c = await _connect();
    await c.selectMailboxByPath(fromPath);
    await c.uidMove(MessageSequence.fromIds([uid], isUid: true),
        targetMailboxPath: toPath);
    final d = await AppDb.instance.db;
    await d.delete('messages',
        where: 'account_id = ? AND folder_path = ? AND uid = ?',
        whereArgs: [account.id, fromPath, uid]);
  }

  Future<void> appendToSent(MimeMessage msg) async {
    final boxes = await listFolders();
    final sent = boxes.firstWhere(
      (b) => b.isSent,
      orElse: () => boxes.firstWhere((b) => b.name.toLowerCase().contains('sent'),
          orElse: () => boxes.first),
    );
    final c = await _connect();
    await c.appendMessage(msg,
        targetMailbox: sent, flags: const ['\\Seen']);
  }
}
