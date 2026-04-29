import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../background/workmanager_dispatcher.dart';
import '../../data/account_store.dart';
import '../../data/providers.dart';
import '../../models/account.dart';

class AddAccountPage extends ConsumerStatefulWidget {
  const AddAccountPage({super.key});

  @override
  ConsumerState<AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends ConsumerState<AddAccountPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  bool _imapSsl = true;
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '465');
  bool _smtpSsl = true;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    for (final c in [
      _name,
      _email,
      _password,
      _imapHost,
      _imapPort,
      _smtpHost,
      _smtpPort
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _autoDiscover() async {
    final em = _email.text.trim();
    if (!em.contains('@')) return;
    setState(() => _busy = true);
    try {
      final cfg = await Discover.discover(em);
      if (cfg != null && cfg.preferredIncomingImapServer != null) {
        final inc = cfg.preferredIncomingImapServer!;
        final out = cfg.preferredOutgoingSmtpServer;
        _imapHost.text = inc.hostname;
        _imapPort.text = inc.port.toString();
        _imapSsl = inc.socketType == SocketType.ssl;
        if (out != null) {
          _smtpHost.text = out.hostname;
          _smtpPort.text = out.port.toString();
          _smtpSsl = out.socketType == SocketType.ssl;
        }
        setState(() {});
      }
    } catch (_) {}
    setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final id = const Uuid().v4();
    final account = Account(
      id: id,
      name: _name.text.trim(),
      email: _email.text.trim(),
      imapHost: _imapHost.text.trim(),
      imapPort: int.parse(_imapPort.text.trim()),
      imapSsl: _imapSsl,
      smtpHost: _smtpHost.text.trim(),
      smtpPort: int.parse(_smtpPort.text.trim()),
      smtpSsl: _smtpSsl,
      username: _email.text.trim(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      // Quick login probe
      final c = ImapClient(isLogEnabled: false);
      await c.connectToServer(account.imapHost, account.imapPort,
          isSecure: account.imapSsl);
      await c.login(account.username, _password.text);
      await c.logout();
      await AccountStore.instance.insert(account, _password.text);
      await BackgroundSync.schedule(minutes: account.syncMinutes);
      ref.invalidate(accountsProvider);
      if (mounted) Navigator.of(context).pop(account);
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add account')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
                ),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  onEditingComplete: _autoDiscover,
                  validator: (v) =>
                      (v ?? '').contains('@') ? null : 'Invalid',
                ),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextFormField(
                    controller: _imapHost,
                    decoration:
                        const InputDecoration(labelText: 'IMAP host'),
                  )),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextFormField(
                      controller: _imapPort,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Port'),
                    ),
                  ),
                ]),
                SwitchListTile(
                  title: const Text('IMAP SSL/TLS'),
                  value: _imapSsl,
                  onChanged: (v) => setState(() => _imapSsl = v),
                ),
                Row(children: [
                  Expanded(
                      child: TextFormField(
                    controller: _smtpHost,
                    decoration:
                        const InputDecoration(labelText: 'SMTP host'),
                  )),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextFormField(
                      controller: _smtpPort,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Port'),
                    ),
                  ),
                ]),
                SwitchListTile(
                  title: const Text('SMTP SSL/TLS'),
                  value: _smtpSsl,
                  onChanged: (v) => setState(() => _smtpSsl = v),
                ),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_err!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('Save & connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
