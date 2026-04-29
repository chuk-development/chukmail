import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../background/workmanager_dispatcher.dart';
import '../../data/account_store.dart';
import '../../data/providers.dart';
import '../../models/account.dart';
import '../../services/settings_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _blockRemoteGlobal = true;
  int _syncMinutes = 15;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _blockRemoteGlobal = await SettingsService.instance
        .getBool(SettingsService.kBlockRemoteGlobal, def: true);
    _syncMinutes = await SettingsService.instance
        .getInt(SettingsService.kSyncMinutes, def: 15);
    setState(() => _loaded = true);
  }

  Future<void> _saveSync(int minutes) async {
    setState(() => _syncMinutes = minutes);
    await SettingsService.instance
        .setInt(SettingsService.kSyncMinutes, minutes);
    await BackgroundSync.schedule(minutes: minutes);
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Block remote content (default)'),
                  subtitle: const Text(
                      'Hide external images and trackers in HTML mails'),
                  value: _blockRemoteGlobal,
                  onChanged: (v) async {
                    setState(() => _blockRemoteGlobal = v);
                    await SettingsService.instance.setBool(
                        SettingsService.kBlockRemoteGlobal, v);
                  },
                ),
                ListTile(
                  title: const Text('Background sync interval'),
                  subtitle: Text('Every $_syncMinutes minutes'),
                  trailing: PopupMenuButton<int>(
                    onSelected: _saveSync,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 15, child: Text('15 min')),
                      PopupMenuItem(value: 30, child: Text('30 min')),
                      PopupMenuItem(value: 60, child: Text('1 hour')),
                      PopupMenuItem(value: 180, child: Text('3 hours')),
                    ],
                    child: const Icon(Icons.schedule),
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Accounts',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                accountsAsync.when(
                  data: (accounts) => Column(
                    children: accounts
                        .map((a) => _AccountTile(account: a))
                        .toList(),
                  ),
                  loading: () =>
                      const Padding(padding: EdgeInsets.all(16),
                          child: LinearProgressIndicator()),
                  error: (e, _) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('$e')),
                ),
              ],
            ),
    );
  }
}

class _AccountTile extends ConsumerStatefulWidget {
  final Account account;
  const _AccountTile({required this.account});

  @override
  ConsumerState<_AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends ConsumerState<_AccountTile> {
  bool _expanded = false;
  late final TextEditingController _signature;
  late bool _blockRemote;

  @override
  void initState() {
    super.initState();
    _signature =
        TextEditingController(text: widget.account.signature ?? '');
    _blockRemote = widget.account.blockRemote;
  }

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final updated = widget.account.copyWith(
      signature: _signature.text,
      blockRemote: _blockRemote,
    );
    await AccountStore.instance.update(updated);
    ref.invalidate(accountsProvider);
    if (mounted) setState(() => _expanded = false);
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text('Remove ${widget.account.email} from this device?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await AccountStore.instance.delete(widget.account.id);
    ref.invalidate(accountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(widget.account.email),
          subtitle: Text(
              '${widget.account.imapHost}:${widget.account.imapPort}'),
          trailing: IconButton(
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                TextField(
                  controller: _signature,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Signature'),
                ),
                SwitchListTile(
                  title: const Text('Block remote content for this account'),
                  value: _blockRemote,
                  onChanged: (v) => setState(() => _blockRemote = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _delete,
                      style: TextButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.error),
                      child: const Text('Delete'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                        onPressed: _save, child: const Text('Save')),
                  ],
                ),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}
