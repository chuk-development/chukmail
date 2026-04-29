import 'dart:async';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/account_store.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../models/account.dart';
import '../../services/imap_service.dart';
import '../compose/compose_page.dart';
import 'address_actions.dart';

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
      if (!mounted) return;
      setState(() {
        _msg = msg;
        _account = account;
        _allowRemote = !(account?.blockRemote ?? true);
        _loading = false;
      });
      if (account == null) return;
      // Always refresh in background so attachments and full MIME are
      // available, but don't block the first paint.
      unawaited(_refreshFull());
      unawaited(_markSeen());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshFull() async {
    final a = _account;
    final m = _msg;
    if (a == null || m == null) return;
    final imap = ImapService(a);
    try {
      final full = await imap.fetchFull(m.folderPath, m.uid);
      if (!mounted) return;
      setState(() => _full = full);
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
      // Refresh _msg so cached body is also up to date
      final rows = await d
          .query('messages', where: 'id = ?', whereArgs: [m.id]);
      if (rows.isNotEmpty && mounted) {
        setState(() => _msg = StoredMessage.fromMap(rows.first));
      }
    } catch (_) {
      // Quiet — cached body is shown; only fail loud if no cache.
      if (mounted && _msg?.bodyHtml == null && _msg?.bodyPlain == null) {
        setState(() => _error = 'Could not load message body');
      }
    } finally {
      await imap.disconnect();
    }
  }

  Future<void> _markSeen({bool seen = true}) async {
    final a = _account;
    final m = _msg;
    if (a == null || m == null) return;
    if (m.seen == seen) return;
    final imap = ImapService(a);
    try {
      await imap.markSeen(m.folderPath, m.uid, seen);
      ref.invalidate(messagesProvider(MailboxKey(a.id, m.folderPath)));
      final d = await AppDb.instance.db;
      final rows = await d.query('messages',
          where: 'id = ?', whereArgs: [m.id]);
      if (rows.isNotEmpty && mounted) {
        setState(() => _msg = StoredMessage.fromMap(rows.first));
      }
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
      ref.invalidate(messagesProvider(MailboxKey(a.id, m.folderPath)));
    } finally {
      await imap.disconnect();
    }
  }

  Future<void> _moveToFolder() async {
    final a = _account;
    final m = _msg;
    if (a == null || m == null) return;
    final folders = await ref.read(foldersProvider(a.id).future);
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Move to folder',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ...folders
                .where((f) => f.path != m.folderPath)
                .map((f) => ListTile(
                      leading: Icon(_folderIcon(f.role ?? f.name)),
                      title: Text(f.name),
                      onTap: () => Navigator.of(ctx).pop(f.path),
                    )),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final imap = ImapService(a);
    try {
      await imap.moveMessage(m.folderPath, m.uid, selected);
      ref.invalidate(messagesProvider(MailboxKey(a.id, m.folderPath)));
      ref.invalidate(messagesProvider(MailboxKey(a.id, selected)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Moved to $selected'),
          duration: const Duration(seconds: 2),
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Move failed: $e')));
      }
    } finally {
      await imap.disconnect();
    }
  }

  IconData _folderIcon(String key) {
    final k = key.toLowerCase();
    if (k.contains('inbox')) return Icons.inbox_outlined;
    if (k.contains('sent')) return Icons.send_outlined;
    if (k.contains('draft')) return Icons.drafts_outlined;
    if (k.contains('trash') || k.contains('deleted')) {
      return Icons.delete_outline;
    }
    if (k.contains('junk') || k.contains('spam')) {
      return Icons.report_outlined;
    }
    if (k.contains('archive')) return Icons.archive_outlined;
    return Icons.folder_outlined;
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

  String _replySubject(String? original) {
    final s = (original ?? '').trim();
    if (s.toLowerCase().startsWith('re:')) return s;
    return 'Re: $s';
  }

  String _forwardSubject(String? original) {
    final s = (original ?? '').trim();
    final lower = s.toLowerCase();
    if (lower.startsWith('fwd:') || lower.startsWith('fw:')) return s;
    return 'Fwd: $s';
  }

  String _quoteBody() {
    final full = _full;
    final m = _msg;
    final plain = full?.decodeTextPlainPart() ?? m?.bodyPlain ?? '';
    final dateStr = m?.date != null
        ? DateFormat.yMMMd()
            .add_Hm()
            .format(DateTime.fromMillisecondsSinceEpoch(m!.date!))
        : '';
    final fromStr = m?.fromName?.isNotEmpty == true
        ? '${m!.fromName} <${m.fromAddr ?? ''}>'
        : (m?.fromAddr ?? '');
    return 'On $dateStr, $fromStr wrote:\n$plain';
  }

  String _forwardQuote() {
    final m = _msg;
    final full = _full;
    final plain = full?.decodeTextPlainPart() ?? m?.bodyPlain ?? '';
    final dateStr = m?.date != null
        ? DateFormat.yMMMd()
            .add_Hm()
            .format(DateTime.fromMillisecondsSinceEpoch(m!.date!))
        : '';
    final from = m?.fromAddr ?? '';
    final to = m?.toAddrs ?? '';
    final subject = m?.subject ?? '';
    return 'From: $from\nDate: $dateStr\nSubject: $subject\nTo: $to\n\n$plain';
  }

  void _reply({bool replyAll = false}) {
    final a = _account;
    final m = _msg;
    if (a == null || m == null) return;
    final to = m.fromAddr ?? '';
    String? cc;
    if (replyAll) {
      final all = <String>{};
      if (m.toAddrs != null) all.addAll(m.toAddrs!.split(','));
      if (m.ccAddrs != null) all.addAll(m.ccAddrs!.split(','));
      all.removeWhere((e) =>
          e.trim().isEmpty || e.trim().toLowerCase() == a.email.toLowerCase());
      if (all.isNotEmpty) cc = all.map((e) => e.trim()).join(', ');
    }
    final references = m.messageId ?? '';
    context.push('/compose', extra: ComposeExtra(
      accountId: a.id,
      toAddr: to,
      ccAddr: cc,
      subject: _replySubject(m.subject),
      quoteBody: _quoteBody(),
      inReplyTo: m.messageId,
      references: references.isEmpty ? null : references,
    ));
  }

  void _forward() {
    final a = _account;
    final m = _msg;
    if (a == null || m == null) return;
    context.push('/compose', extra: ComposeExtra(
      accountId: a.id,
      subject: _forwardSubject(m.subject),
      quoteBody: _forwardQuote(),
      isForward: true,
    ));
  }

  void _showHeaders() {
    final full = _full;
    if (full == null) return;
    final headers =
        full.headers?.map((h) => '${h.name}: ${h.value}').join('\n') ??
            '(no headers)';
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(ctx).size.width - 32,
              maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Headers',
                        style: Theme.of(ctx).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(headers,
                      style: const TextStyle(fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _onTapUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: $e')),
        );
      }
      return false;
    }
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
    final a = _account;
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
            icon: const Icon(Icons.reply),
            tooltip: 'Reply',
            onPressed: () => _reply(),
          ),
          IconButton(
            icon: const Icon(Icons.reply_all),
            tooltip: 'Reply all',
            onPressed: () => _reply(replyAll: true),
          ),
          IconButton(
            icon: const Icon(Icons.forward),
            tooltip: 'Forward',
            onPressed: _forward,
          ),
          IconButton(
            icon: Icon(m.flagged ? Icons.star : Icons.star_outline),
            tooltip: m.flagged ? 'Unstar' : 'Star',
            onPressed: _toggleFlag,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'unread':
                  _markSeen(seen: false);
                  break;
                case 'move':
                  _moveToFolder();
                  break;
                case 'delete':
                  _delete();
                  break;
                case 'headers':
                  _showHeaders();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'unread',
                  child: ListTile(
                      leading: Icon(Icons.markunread_outlined),
                      title: Text('Mark as unread'))),
              PopupMenuItem(
                  value: 'move',
                  child: ListTile(
                      leading: Icon(Icons.drive_file_move_outlined),
                      title: Text('Move to folder'))),
              PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'))),
              PopupMenuItem(
                  value: 'headers',
                  child: ListTile(
                      leading: Icon(Icons.code_outlined),
                      title: Text('Show headers'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(m.subject ?? '(no subject)',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (a != null) _buildHeader(context, m, a, dateStr),
          const Divider(height: 24),
          _buildBody(),
          if (_full != null) ..._buildAttachments(),
        ],
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, StoredMessage m, Account a, String dateStr) {
    final fromAddr = m.fromAddr ?? '';
    final fromName = m.fromName ?? '';
    final displayName = fromName.isNotEmpty ? fromName : fromAddr;
    final scheme = Theme.of(context).colorScheme;
    final mutedStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    return InkWell(
      onTap: () => AddressActions.show(
        context,
        email: fromAddr,
        name: fromName.isEmpty ? null : fromName,
        composeAccountId: a.id,
        onShowFullHeaders: _showHeaders,
      ),
      onLongPress: () => AddressActions.show(
        context,
        email: fromAddr,
        name: fromName.isEmpty ? null : fromName,
        composeAccountId: a.id,
        onShowFullHeaders: _showHeaders,
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Text(
                (displayName.characters.firstOrNull ?? '?').toUpperCase(),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (dateStr.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(dateStr, style: mutedStyle),
                      ],
                    ],
                  ),
                  if (fromName.isNotEmpty && fromAddr.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        fromAddr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mutedStyle,
                      ),
                    ),
                  if ((m.toAddrs ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _recipientLine(context, 'to', m.toAddrs!, a),
                    ),
                  if ((m.ccAddrs ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _recipientLine(context, 'cc', m.ccAddrs!, a),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recipientLine(
      BuildContext context, String label, String csv, Account a) {
    final scheme = Theme.of(context).colorScheme;
    final addrs = csv
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final summary = addrs.length <= 2
        ? addrs.join(', ')
        : '${addrs.first}, +${addrs.length - 1} more';
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        if (addrs.length == 1) {
          AddressActions.show(context,
              email: addrs.first, composeAccountId: a.id);
        } else {
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: Text('${label.toUpperCase()} (${addrs.length})',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const Divider(height: 1),
                  ...addrs.map((email) => ListTile(
                        leading: CircleAvatar(
                          child: Text(
                              (email.characters.firstOrNull ?? '?')
                                  .toUpperCase()),
                        ),
                        title: Text(email),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          AddressActions.show(context,
                              email: email, composeAccountId: a.id);
                        },
                      )),
                ],
              ),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '$label: $summary',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final m = _msg;
    final full = _full;
    final html = full?.decodeTextHtmlPart() ?? m?.bodyHtml;
    final plain = full?.decodeTextPlainPart() ?? m?.bodyPlain;
    if (html != null && html.isNotEmpty) {
      final hasRemote = _hasRemoteContent(html);
      final blocking = !_allowRemote && hasRemote;
      final htmlBody = blocking ? _stripRemote(html) : html;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (blocking)
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
            onTapUrl: _onTapUrl,
            renderMode: RenderMode.column,
          ),
        ],
      );
    }
    if (plain != null && plain.isNotEmpty) {
      return SelectableText(plain);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text('Loading body…',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  static final RegExp _remoteRegex = RegExp(
      r'''(?:src|background|poster)\s*=\s*["']?https?://|url\(\s*["']?https?://''',
      caseSensitive: false);

  bool _hasRemoteContent(String html) {
    return _remoteRegex.hasMatch(html);
  }

  String _stripRemote(String html) {
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
