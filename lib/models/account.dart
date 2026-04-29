class Account {
  final String id;
  final String name;
  final String email;
  final String imapHost;
  final int imapPort;
  final bool imapSsl;
  final String smtpHost;
  final int smtpPort;
  final bool smtpSsl;
  final String username;
  final String? signature;
  final bool blockRemote;
  final int syncMinutes;
  final int color;
  final int createdAt;

  Account({
    required this.id,
    required this.name,
    required this.email,
    required this.imapHost,
    required this.imapPort,
    required this.imapSsl,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSsl,
    required this.username,
    this.signature,
    this.blockRemote = true,
    this.syncMinutes = 15,
    this.color = 0,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'imap_host': imapHost,
        'imap_port': imapPort,
        'imap_ssl': imapSsl ? 1 : 0,
        'smtp_host': smtpHost,
        'smtp_port': smtpPort,
        'smtp_ssl': smtpSsl ? 1 : 0,
        'username': username,
        'signature': signature,
        'block_remote': blockRemote ? 1 : 0,
        'sync_minutes': syncMinutes,
        'color': color,
        'created_at': createdAt,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as String,
        name: m['name'] as String,
        email: m['email'] as String,
        imapHost: m['imap_host'] as String,
        imapPort: m['imap_port'] as int,
        imapSsl: (m['imap_ssl'] as int) == 1,
        smtpHost: m['smtp_host'] as String,
        smtpPort: m['smtp_port'] as int,
        smtpSsl: (m['smtp_ssl'] as int) == 1,
        username: m['username'] as String,
        signature: m['signature'] as String?,
        blockRemote: (m['block_remote'] as int) == 1,
        syncMinutes: m['sync_minutes'] as int,
        color: m['color'] as int,
        createdAt: m['created_at'] as int,
      );

  Account copyWith({
    String? name,
    String? email,
    String? signature,
    bool? blockRemote,
    int? syncMinutes,
    int? color,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        imapHost: imapHost,
        imapPort: imapPort,
        imapSsl: imapSsl,
        smtpHost: smtpHost,
        smtpPort: smtpPort,
        smtpSsl: smtpSsl,
        username: username,
        signature: signature ?? this.signature,
        blockRemote: blockRemote ?? this.blockRemote,
        syncMinutes: syncMinutes ?? this.syncMinutes,
        color: color ?? this.color,
        createdAt: createdAt,
      );
}

class StoredMessage {
  final int id;
  final String accountId;
  final String folderPath;
  final int uid;
  final String? messageId;
  final String? subject;
  final String? fromAddr;
  final String? fromName;
  final String? toAddrs;
  final String? ccAddrs;
  final String? bccAddrs;
  final int? date;
  final String? preview;
  final String? bodyPlain;
  final String? bodyHtml;
  final bool seen;
  final bool flagged;
  final bool answered;
  final bool hasAttachments;
  final int? sizeBytes;
  final bool fullFetched;

  StoredMessage({
    required this.id,
    required this.accountId,
    required this.folderPath,
    required this.uid,
    this.messageId,
    this.subject,
    this.fromAddr,
    this.fromName,
    this.toAddrs,
    this.ccAddrs,
    this.bccAddrs,
    this.date,
    this.preview,
    this.bodyPlain,
    this.bodyHtml,
    this.seen = false,
    this.flagged = false,
    this.answered = false,
    this.hasAttachments = false,
    this.sizeBytes,
    this.fullFetched = false,
  });

  factory StoredMessage.fromMap(Map<String, Object?> m) => StoredMessage(
        id: m['id'] as int,
        accountId: m['account_id'] as String,
        folderPath: m['folder_path'] as String,
        uid: m['uid'] as int,
        messageId: m['message_id'] as String?,
        subject: m['subject'] as String?,
        fromAddr: m['from_addr'] as String?,
        fromName: m['from_name'] as String?,
        toAddrs: m['to_addrs'] as String?,
        ccAddrs: m['cc_addrs'] as String?,
        bccAddrs: m['bcc_addrs'] as String?,
        date: m['date'] as int?,
        preview: m['preview'] as String?,
        bodyPlain: m['body_plain'] as String?,
        bodyHtml: m['body_html'] as String?,
        seen: (m['seen'] as int) == 1,
        flagged: (m['flagged'] as int) == 1,
        answered: (m['answered'] as int) == 1,
        hasAttachments: (m['has_attachments'] as int) == 1,
        sizeBytes: m['size_bytes'] as int?,
        fullFetched: (m['full_fetched'] as int) == 1,
      );
}

class FolderRow {
  final int id;
  final String accountId;
  final String path;
  final String name;
  final String? role;
  final int unread;
  final int total;

  FolderRow({
    required this.id,
    required this.accountId,
    required this.path,
    required this.name,
    this.role,
    this.unread = 0,
    this.total = 0,
  });

  factory FolderRow.fromMap(Map<String, Object?> m) => FolderRow(
        id: m['id'] as int,
        accountId: m['account_id'] as String,
        path: m['path'] as String,
        name: m['name'] as String,
        role: m['role'] as String?,
        unread: m['unread'] as int,
        total: m['total'] as int,
      );
}
