import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'chukmail.db');
    _db = await openDatabase(
      path,
      version: 1,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE accounts(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            imap_host TEXT NOT NULL,
            imap_port INTEGER NOT NULL,
            imap_ssl INTEGER NOT NULL,
            smtp_host TEXT NOT NULL,
            smtp_port INTEGER NOT NULL,
            smtp_ssl INTEGER NOT NULL,
            username TEXT NOT NULL,
            signature TEXT,
            block_remote INTEGER NOT NULL DEFAULT 1,
            sync_minutes INTEGER NOT NULL DEFAULT 15,
            color INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');
        await d.execute('''
          CREATE TABLE folders(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id TEXT NOT NULL,
            path TEXT NOT NULL,
            name TEXT NOT NULL,
            role TEXT,
            unread INTEGER NOT NULL DEFAULT 0,
            total INTEGER NOT NULL DEFAULT 0,
            uid_validity INTEGER,
            uid_next INTEGER,
            FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE,
            UNIQUE(account_id, path)
          )
        ''');
        await d.execute('''
          CREATE TABLE messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id TEXT NOT NULL,
            folder_path TEXT NOT NULL,
            uid INTEGER NOT NULL,
            message_id TEXT,
            subject TEXT,
            from_addr TEXT,
            from_name TEXT,
            to_addrs TEXT,
            cc_addrs TEXT,
            bcc_addrs TEXT,
            date INTEGER,
            preview TEXT,
            body_plain TEXT,
            body_html TEXT,
            seen INTEGER NOT NULL DEFAULT 0,
            flagged INTEGER NOT NULL DEFAULT 0,
            answered INTEGER NOT NULL DEFAULT 0,
            has_attachments INTEGER NOT NULL DEFAULT 0,
            size_bytes INTEGER,
            full_fetched INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE,
            UNIQUE(account_id, folder_path, uid)
          )
        ''');
        await d.execute('CREATE INDEX idx_msg_folder ON messages(account_id, folder_path, date DESC)');
        await d.execute('CREATE INDEX idx_msg_seen ON messages(account_id, seen)');
        await d.execute('''
          CREATE TABLE attachments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message_id INTEGER NOT NULL,
            filename TEXT,
            mime_type TEXT,
            size_bytes INTEGER,
            content_id TEXT,
            fetch_id TEXT,
            local_path TEXT,
            FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
          )
        ''');
        await d.execute('''
          CREATE TABLE drafts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id TEXT NOT NULL,
            to_addrs TEXT,
            cc_addrs TEXT,
            bcc_addrs TEXT,
            subject TEXT,
            body TEXT,
            in_reply_to TEXT,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
          )
        ''');
        await d.execute('''
          CREATE TABLE outbox(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id TEXT NOT NULL,
            mime_data BLOB NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at INTEGER NOT NULL,
            FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
          )
        ''');
        await d.execute('''
          CREATE TABLE settings(
            k TEXT PRIMARY KEY,
            v TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
