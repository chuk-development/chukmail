import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/account_store.dart';
import '../../data/providers.dart';
import '../../models/account.dart';
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

  Future<void> _sync() async {
    if (_accountId == null) return;
    final a = await AccountStore.instance.byId(_accountId!);
    if (a == null) return;
    setState(() => _syncing = true);
    try {
      await SyncService.syncAccount(a);
      ref.invalidate(messagesProvider(MailboxKey(_accountId!, _folderPath)));
      ref.invalidate(foldersProvider(_accountId!));
    } finally {
      if (mounted) setState(() => _syncing = false);
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
            appBar: AppBar(title: const Text('chukmail')),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_folderPath),
        actions: [
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
                                      setState(() => _folderPath = f.path);
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
      body: messagesAsync.when(
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
                return _MessageTile(
                  msg: m,
                  onTap: () => context.push('/message/${m.id}'),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/compose?account=${current.id}'),
        icon: const Icon(Icons.edit),
        label: const Text('Compose'),
      ),
    );
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

class _MessageTile extends StatelessWidget {
  final StoredMessage msg;
  final VoidCallback onTap;
  const _MessageTile({required this.msg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final from = msg.fromName?.isNotEmpty == true
        ? msg.fromName!
        : (msg.fromAddr ?? 'Unknown');
    final subj = msg.subject?.isNotEmpty == true
        ? msg.subject!
        : '(no subject)';
    final date = msg.date != null
        ? DateFormat('MMM d HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(msg.date!))
        : '';
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        child: Text(from.isNotEmpty ? from.characters.first.toUpperCase() : '?'),
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
          if (msg.hasAttachments) const Icon(Icons.attach_file, size: 16),
          if (msg.flagged)
            const Icon(Icons.star, size: 16, color: Colors.amber),
        ],
      ),
    );
  }
}
