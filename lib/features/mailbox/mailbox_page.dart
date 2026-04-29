import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/account_store.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../models/account.dart';
import '../../services/imap_service.dart';
import '../../services/sync_service.dart';
import '../accounts/add_account_page.dart';

class MailboxPage extends ConsumerStatefulWidget {
  const MailboxPage({super.key});
  @override
  ConsumerState<MailboxPage> createState() => _MailboxPageState();
}

class _MailboxPageState extends ConsumerState<MailboxPage> {
  String? _accountId;
  String _folderPath = 'INBOX';
  bool _syncing = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<int> _selected = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    if (_accountId == null) return;
    final a = await AccountStore.instance.byId(_accountId!);
    if (a == null) return;
    setState(() => _syncing = true);
    try {
      final n = await SyncService.syncAccount(a, folderPath: _folderPath);
      ref.invalidate(messagesProvider(MailboxKey(_accountId!, _folderPath)));
      ref.invalidate(foldersProvider(_accountId!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(n == 0
              ? 'Synced — no new mail'
              : 'Synced — $n new'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sync failed: $e'),
          duration: const Duration(seconds: 6),
        ));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _toggleSelect(int messageRowId) {
    setState(() {
      if (_selected.contains(messageRowId)) {
        _selected.remove(messageRowId);
      } else {
        _selected.add(messageRowId);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selected.clear());
  }

  Future<List<StoredMessage>> _selectedRows() async {
    final d = await AppDb.instance.db;
    final placeholders = List.filled(_selected.length, '?').join(',');
    final rows = await d.query('messages',
        where: 'id IN ($placeholders)',
        whereArgs: _selected.toList());
    return rows.map(StoredMessage.fromMap).toList();
  }

  Future<void> _bulkMarkSeen(bool seen) async {
    final account = await AccountStore.instance.byId(_accountId!);
    if (account == null) return;
    final rows = await _selectedRows();
    final imap = ImapService(account);
    try {
      for (final m in rows) {
        await imap.markSeen(m.folderPath, m.uid, seen);
      }
    } finally {
      await imap.disconnect();
    }
    ref.invalidate(messagesProvider(MailboxKey(account.id, _folderPath)));
    _clearSelection();
  }

  Future<void> _bulkToggleStar() async {
    final account = await AccountStore.instance.byId(_accountId!);
    if (account == null) return;
    final rows = await _selectedRows();
    final imap = ImapService(account);
    try {
      for (final m in rows) {
        await imap.markFlagged(m.folderPath, m.uid, !m.flagged);
      }
    } finally {
      await imap.disconnect();
    }
    ref.invalidate(messagesProvider(MailboxKey(account.id, _folderPath)));
    _clearSelection();
  }

  Future<void> _bulkDelete() async {
    final account = await AccountStore.instance.byId(_accountId!);
    if (account == null) return;
    final rows = await _selectedRows();
    final imap = ImapService(account);
    try {
      for (final m in rows) {
        await imap.deleteMessage(m.folderPath, m.uid);
      }
    } finally {
      await imap.disconnect();
    }
    ref.invalidate(messagesProvider(MailboxKey(account.id, _folderPath)));
    _clearSelection();
  }

  Future<void> _bulkMove() async {
    final account = await AccountStore.instance.byId(_accountId!);
    if (account == null) return;
    final folders = await ref.read(foldersProvider(account.id).future);
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
                .where((f) => f.path != _folderPath)
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
    final rows = await _selectedRows();
    final imap = ImapService(account);
    try {
      for (final m in rows) {
        await imap.moveMessage(m.folderPath, m.uid, selected);
      }
    } finally {
      await imap.disconnect();
    }
    ref.invalidate(messagesProvider(MailboxKey(account.id, _folderPath)));
    ref.invalidate(messagesProvider(MailboxKey(account.id, selected)));
    _clearSelection();
  }

  Future<void> _quickToggleStar(StoredMessage m) async {
    final account = await AccountStore.instance.byId(m.accountId);
    if (account == null) return;
    final imap = ImapService(account);
    try {
      await imap.markFlagged(m.folderPath, m.uid, !m.flagged);
    } finally {
      await imap.disconnect();
    }
    ref.invalidate(messagesProvider(MailboxKey(account.id, m.folderPath)));
  }

  Future<void> _swipeArchive(StoredMessage m,
      List<FolderRow> folders) async {
    final account = await AccountStore.instance.byId(m.accountId);
    if (account == null) return;
    String? targetPath;
    for (final f in folders) {
      if (f.role == 'archive') {
        targetPath = f.path;
        break;
      }
    }
    if (targetPath == null) {
      for (final f in folders) {
        if (f.role == 'trash') {
          targetPath = f.path;
          break;
        }
      }
    }
    if (targetPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No archive or trash folder available')));
      }
      return;
    }
    final imap = ImapService(account);
    try {
      await imap.moveMessage(m.folderPath, m.uid, targetPath);
    } finally {
      await imap.disconnect();
    }
    ref.invalidate(messagesProvider(MailboxKey(account.id, m.folderPath)));
    ref.invalidate(messagesProvider(MailboxKey(account.id, targetPath)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Archived to $targetPath'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _swipeDelete(StoredMessage m) async {
    final account = await AccountStore.instance.byId(m.accountId);
    if (account == null) return;
    final imap = ImapService(account);
    try {
      await imap.deleteMessage(m.folderPath, m.uid);
    } finally {
      await imap.disconnect();
    }
    ref.invalidate(messagesProvider(MailboxKey(account.id, m.folderPath)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Deleted'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    return accountsAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Error: $e'))),
      data: (accounts) {
        if (accounts.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chuk Mail')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mail_outline, size: 80),
                    const SizedBox(height: 16),
                    const Text('No accounts yet'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AddAccountPage()),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add account'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        _accountId ??= accounts.first.id;
        final acct = accounts.firstWhere((a) => a.id == _accountId,
            orElse: () => accounts.first);
        return _buildScaffold(context, accounts, acct);
      },
    );
  }

  Widget _buildScaffold(
      BuildContext context, List<Account> accounts, Account current) {
    final foldersAsync = ref.watch(foldersProvider(current.id));
    final mboxKey = MailboxKey(current.id, _folderPath);
    final messagesAsync = ref.watch(messagesProvider(mboxKey));
    final inSelection = _selected.isNotEmpty;

    return Scaffold(
      appBar: inSelection
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
              title: Text('${_selected.length} selected'),
              actions: [
                IconButton(
                  tooltip: 'Mark read',
                  icon: const Icon(Icons.mark_email_read_outlined),
                  onPressed: () => _bulkMarkSeen(true),
                ),
                IconButton(
                  tooltip: 'Mark unread',
                  icon: const Icon(Icons.markunread_outlined),
                  onPressed: () => _bulkMarkSeen(false),
                ),
                IconButton(
                  tooltip: 'Star',
                  icon: const Icon(Icons.star_outline),
                  onPressed: _bulkToggleStar,
                ),
                IconButton(
                  tooltip: 'Move',
                  icon: const Icon(Icons.drive_file_move_outlined),
                  onPressed: _bulkMove,
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _bulkDelete,
                ),
              ],
            )
          : AppBar(
              title: Text(_folderPath),
              actions: [
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: () => _openSearch(context, current),
                ),
                IconButton(
                  onPressed: _syncing ? null : _sync,
                  icon: _syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
                IconButton(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: current.id,
                items: accounts
                    .map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.email),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _accountId = v;
                      _folderPath = 'INBOX';
                      _clearSelection();
                    });
                    Navigator.of(context).pop();
                  }
                },
                decoration: const InputDecoration(
                    labelText: 'Account',
                    contentPadding: EdgeInsets.symmetric(horizontal: 16)),
              ),
              Expanded(
                child: foldersAsync.when(
                  data: (folders) => folders.isEmpty
                      ? const Center(child: Text('No folders synced yet'))
                      : ListView(
                          children: folders
                              .map((f) => ListTile(
                                    leading:
                                        Icon(_folderIcon(f.role ?? f.name)),
                                    title: Text(f.name),
                                    selected: f.path == _folderPath,
                                    trailing: f.unread > 0
                                        ? Text('${f.unread}')
                                        : null,
                                    onTap: () {
                                      setState(() {
                                        _folderPath = f.path;
                                        _clearSelection();
                                      });
                                      Navigator.of(context).pop();
                                    },
                                  ))
                              .toList(),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Err: $e')),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add account'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AddAccountPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/settings');
                },
              ),
            ],
          ),
        ),
      ),
      body: foldersAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (folders) => messagesAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (messages) {
            if (messages.isEmpty) {
              return RefreshIndicator(
                onRefresh: _sync,
                child: ListView(
                  children: const [
                    SizedBox(height: 200),
                    Center(child: Text('Empty — pull to sync')),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _sync,
              child: ListView.separated(
                itemCount: messages.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = messages[i];
                  final isSelected = _selected.contains(m.id);
                  return Dismissible(
                    key: ValueKey('msg-${m.id}'),
                    background: Container(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: const Icon(Icons.archive_outlined),
                    ),
                    secondaryBackground: Container(
                      color: Theme.of(context).colorScheme.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: const Icon(Icons.delete_outline),
                    ),
                    confirmDismiss: (dir) async {
                      if (inSelection) return false;
                      if (dir == DismissDirection.startToEnd) {
                        await _swipeArchive(m, folders);
                        return true;
                      } else if (dir == DismissDirection.endToStart) {
                        await _swipeDelete(m);
                        return true;
                      }
                      return false;
                    },
                    child: _MessageTile(
                      msg: m,
                      isSelected: isSelected,
                      inSelection: inSelection,
                      onTap: () {
                        if (inSelection) {
                          _toggleSelect(m.id);
                        } else {
                          context.push('/message/${m.id}');
                        }
                      },
                      onLongPress: () => _toggleSelect(m.id),
                      onStarTap: () => _quickToggleStar(m),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      floatingActionButton: inSelection
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/compose?account=${current.id}'),
              icon: const Icon(Icons.edit),
              label: const Text('Compose'),
            ),
    );
  }

  Future<void> _openSearch(BuildContext context, Account current) async {
    _searchCtrl.text = _searchQuery;
    final result = await showSearch<String?>(
      context: context,
      delegate: _MailSearchDelegate(
        accountId: current.id,
        folderPath: _folderPath,
      ),
    );
    if (result != null) {
      setState(() => _searchQuery = result);
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
}

String formatMessageDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  if (sameDay) return DateFormat('HH:mm').format(d);
  if (d.year == now.year) return DateFormat('MMM d').format(d);
  return DateFormat('MMM d, yyyy').format(d);
}

class _MessageTile extends StatelessWidget {
  final StoredMessage msg;
  final bool isSelected;
  final bool inSelection;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onStarTap;
  const _MessageTile({
    required this.msg,
    required this.isSelected,
    required this.inSelection,
    required this.onTap,
    required this.onLongPress,
    required this.onStarTap,
  });

  @override
  Widget build(BuildContext context) {
    final from = msg.fromName?.isNotEmpty == true
        ? msg.fromName!
        : (msg.fromAddr ?? 'Unknown');
    final subj = msg.subject?.isNotEmpty == true
        ? msg.subject!
        : '(no subject)';
    final date = msg.date != null ? formatMessageDate(msg.date!) : '';
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: isSelected,
      selectedTileColor:
          Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
      leading: isSelected
          ? CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.check, color: Colors.white),
            )
          : CircleAvatar(
              child: Text(from.isNotEmpty
                  ? from.characters.first.toUpperCase()
                  : '?'),
            ),
      title: Text(
        from,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontWeight: msg.seen ? FontWeight.normal : FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subj,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight:
                      msg.seen ? FontWeight.normal : FontWeight.w600)),
          if (msg.preview != null)
            Text(msg.preview!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(date, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (msg.hasAttachments)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.attach_file, size: 16),
              ),
            InkWell(
              onTap: inSelection ? null : onStarTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  msg.flagged ? Icons.star : Icons.star_outline,
                  size: 18,
                  color: msg.flagged
                      ? Colors.amber
                      : Theme.of(context).disabledColor,
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _MailSearchDelegate extends SearchDelegate<String?> {
  final String accountId;
  final String folderPath;
  _MailSearchDelegate({required this.accountId, required this.folderPath});

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  Future<List<StoredMessage>> _search(String q) async {
    final d = await AppDb.instance.db;
    if (q.isEmpty) {
      final rows = await d.query(
        'messages',
        where: 'account_id = ?',
        whereArgs: [accountId],
        orderBy: 'date DESC',
        limit: 50,
      );
      return rows.map(StoredMessage.fromMap).toList();
    }
    final like = '%$q%';
    final rows = await d.query(
      'messages',
      where:
          'account_id = ? AND (subject LIKE ? OR from_addr LIKE ? OR from_name LIKE ? OR preview LIKE ?)',
      whereArgs: [accountId, like, like, like, like],
      orderBy: 'date DESC',
      limit: 200,
    );
    return rows.map(StoredMessage.fromMap).toList();
  }

  Widget _buildResults(BuildContext context) {
    return FutureBuilder<List<StoredMessage>>(
      future: _search(query),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snap.data!;
        if (results.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(query.isEmpty
                  ? 'Type to search cached mail'
                  : 'No matches for "$query"'),
            ),
          );
        }
        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final m = results[i];
            final from = m.fromName?.isNotEmpty == true
                ? m.fromName!
                : (m.fromAddr ?? 'Unknown');
            final date =
                m.date != null ? formatMessageDate(m.date!) : '';
            return ListTile(
              leading: CircleAvatar(
                child: Text((from.characters.firstOrNull ?? '?')
                    .toUpperCase()),
              ),
              title: Text(from,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(m.subject ?? '(no subject)',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(date,
                  style: Theme.of(ctx).textTheme.bodySmall),
              onTap: () {
                close(ctx, query);
                ctx.push('/message/${m.id}');
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildResults(context);
}
