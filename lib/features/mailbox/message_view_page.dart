import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/account_store.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../models/account.dart';
import '../../services/imap_service.dart';

class MessageViewPage extends ConsumerStatefulWidget {
  final int messageRowId;
  const MessageViewPage({super.key, required this.messageRowId});

  @override
  ConsumerState<MessageViewPage> createState() => _MessageViewPageState();
}

class _MessageViewPageState extends ConsumerState<MessageViewPage> {
  StoredMessage? _msg;
  Account? _account;
  MimeMessage? _full;
  bool _loading = true;
  bool _allowRemote = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await AppDb.instance.db;
      final rows = await d.query('messages',
          where: 'id = ?', whereArgs: [widget.messageRowId]);
      if (rows.isEmpty) {
        setState(() {
          _error = 'Message not found';
          _loading = false;
        });
        return;
      }
      final msg = StoredMessage.fromMap(rows.first);
      final account = await AccountStore.instance.byId(msg.accountId);
      setState(() {
        _msg = msg;
        _account = account;
        _allowRemote = !(account?.blockRemote ?? true);
      });
      if (account != null) {
        await _fetchFull();
        await _markSeen();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchFull() async {
    final a = _account;
    final m = _msg;
    if (a == null || m == null) return;
    final imap = ImapService(a);
    try {
      final full = await imap.fetchFull(m.folderPath, m.uid);
      setState(() => _full = full);
      // Cache plain/html bodies
      final plain = full.decodeTextPlainPart();
      final html = full.decodeTextHtmlPart();
      final d = await AppDb.instance.db;
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
          whereArgs: [m.id]);
    } catch (e) {
      setState(() => _error = 'Fetch failed: $e');
    } finally {
      await imap.disconnect();
    }
  }

  Future<void> _markSeen() async {
    final a = _account;
    final m = _msg;
    if (a == null || m == null || m.seen) return;
    final imap = ImapService(a);
    try {
      await imap.markSeen(m.folderPath, m.uid, true);
      ref.invalidate(messagesProvider(MailboxKey(a.id, m.folderPath)));
    } catch (_) {} finally {
      await imap.disconnect();
    }
  }

  Future<void> _delete() async {
    final a = _account;
    final m = _msg;
    if (a == null || m == null) return;
    final imap = ImapService(a);
    try {
      await imap.deleteMessage(m.folderPath, m.uid);
      ref.invalidate(messagesProvider(MailboxKey(a.id, m.folderPath)));
      if (mounted) Navigator.of(context).pop();
    } finally {
      await imap.disconnect();
    }
  }

  Future<void> _toggleFlag() async {
    final a = _account;
    final m = _msg;
    if (a == null || m == null) return;
    final imap = ImapService(a);
    try {
      await imap.markFlagged(m.folderPath, m.uid, !m.flagged);
      final d = await AppDb.instance.db;
      final rows = await d.query('messages',
          where: 'id = ?', whereArgs: [m.id]);
      if (rows.isNotEmpty) {
        setState(() => _msg = StoredMessage.fromMap(rows.first));
      }
    } finally {
      await imap.disconnect();
    }
  }

  Future<void> _saveAttachment(ContentInfo info) async {
    final full = _full;
    if (full == null) return;
    final part = full.getPart(info.fetchId);
    if (part == null) return;
    final data = part.decodeContentBinary();
    if (data == null) return;
    final dir = await getTemporaryDirectory();
    final filename = info.fileName ?? 'attachment_${info.fetchId}';
    final path = p.join(dir.path, filename);
    await File(path).writeAsBytes(data);
    await OpenFilex.open(path);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
          appBar: AppBar(),
          body: Center(child: Text(_error!)));
    }
    final m = _msg!;
    final dateStr = m.date != null
        ? DateFormat.yMMMd()
            .add_Hm()
            .format(DateTime.fromMillisecondsSinceEpoch(m.date!))
        : '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message'),
        actions: [
          IconButton(
            icon: Icon(m.flagged ? Icons.star : Icons.star_outline),
            onPressed: _toggleFlag,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(m.subject ?? '(no subject)',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                child: Text(((m.fromName ?? m.fromAddr ?? '?')
                        .characters
                        .first)
                    .toUpperCase()),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.fromName ?? m.fromAddr ?? ''),
                    if (m.fromAddr != null && m.fromName != null)
                      Text(m.fromAddr!,
                          style: Theme.of(context).textTheme.bodySmall),
                    if (m.toAddrs != null)
                      Text('To: ${m.toAddrs}',
                          style: Theme.of(context).textTheme.bodySmall),
                    Text(dateStr,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          if (_full == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _buildBody(),
          if (_full != null) ..._buildAttachments(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final full = _full!;
    final html = full.decodeTextHtmlPart();
    final plain = full.decodeTextPlainPart();
    if (html != null && html.isNotEmpty) {
      String htmlBody;
      if (_allowRemote) {
        htmlBody = html;
      } else {
        htmlBody = _stripRemote(html);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_allowRemote)
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.image_not_supported_outlined),
                title: const Text('Remote content blocked'),
                subtitle: const Text(
                    'External images and trackers are hidden for privacy.'),
                trailing: TextButton(
                  onPressed: () => setState(() => _allowRemote = true),
                  child: const Text('Show'),
                ),
              ),
            ),
          HtmlWidget(
            htmlBody,
            onTapUrl: (_) async => true,
            renderMode: RenderMode.column,
          ),
          if (plain != null && plain.isEmpty) Text(plain),
        ],
      );
    }
    return SelectableText(plain ?? '(no body)');
  }

  String _stripRemote(String html) {
    // Remove img src, background, and url() pointing to http(s)
    return html
        .replaceAll(
            RegExp(r'(<img[^>]+?)src\s*=\s*"https?:[^"]*"',
                caseSensitive: false),
            r'$1src=""')
        .replaceAll(
            RegExp(r"(<img[^>]+?)src\s*=\s*'https?:[^']*'",
                caseSensitive: false),
            r"$1src=''")
        .replaceAll(
            RegExp(r'background\s*=\s*"https?:[^"]*"', caseSensitive: false),
            'background=""')
        .replaceAll(
            RegExp(r'url\(\s*https?:[^\)]*\)', caseSensitive: false), 'url()');
  }

  List<Widget> _buildAttachments() {
    final full = _full!;
    final attachments = full.findContentInfo();
    if (attachments.isEmpty) return const [];
    return [
      const Divider(height: 24),
      Text('Attachments',
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      ...attachments.map((info) => Card(
            child: ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(info.fileName ?? '(unnamed)'),
              subtitle: Text(_humanSize(info.size ?? 0)),
              trailing: IconButton(
                icon: const Icon(Icons.download),
                onPressed: () => _saveAttachment(info),
              ),
            ),
          ))
    ];
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
