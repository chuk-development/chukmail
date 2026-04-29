import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../background/workmanager_dispatcher.dart';
import '../../data/account_store.dart';
import '../../data/providers.dart';
import '../../models/account.dart';

enum _Step { credentials, review }

class AddAccountPage extends ConsumerStatefulWidget {
  const AddAccountPage({super.key});

  @override
  ConsumerState<AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends ConsumerState<AddAccountPage> {
  final _credForm = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  bool _imapSsl = true;
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '465');
  bool _smtpSsl = true;

  _Step _step = _Step.credentials;
  bool _busy = false;
  bool _autoDetected = false;
  String? _err;
  String? _info;

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

  Future<void> _detectAndContinue() async {
    if (!_credForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _err = null;
      _info = 'Detecting server settings…';
    });
    final email = _email.text.trim();
    try {
      final cfg = await Discover.discover(email);
      if (cfg == null || cfg.preferredIncomingImapServer == null) {
        setState(() {
          _err = 'Could not auto-detect IMAP/SMTP servers for this domain.\n'
              'Enter them manually below.';
          _autoDetected = false;
          _step = _Step.review;
        });
        return;
      }
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
      setState(() {
        _autoDetected = true;
        _step = _Step.review;
      });
    } catch (e) {
      setState(() {
        _err = 'Auto-detect failed: $e\nEnter settings manually.';
        _autoDetected = false;
        _step = _Step.review;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_imapHost.text.trim().isEmpty || _smtpHost.text.trim().isEmpty) {
      setState(() => _err = 'IMAP and SMTP host are required');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
      _info = 'Connecting…';
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
      setState(() => _err = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add account'),
        leading: _step == _Step.review
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _step = _Step.credentials;
                          _err = null;
                          _info = null;
                        }),
              )
            : null,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _step == _Step.credentials
              ? _buildCredentials(context)
              : _buildReview(context),
        ),
      ),
    );
  }

  Widget _buildCredentials(BuildContext context) {
    return Form(
      key: _credForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sign in', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Enter your name, email, and password. We\'ll auto-detect your '
            'IMAP and SMTP servers from the domain.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email),
            ),
            validator: (v) =>
                (v ?? '').contains('@') ? null : 'Enter a valid email',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            onFieldSubmitted: (_) => _detectAndContinue(),
          ),
          const SizedBox(height: 24),
          if (_info != null && _busy)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_info!)),
                ],
              ),
            ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_err!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _detectAndContinue,
            icon: const Icon(Icons.search),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildReview(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: _autoDetected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: Icon(
                _autoDetected ? Icons.check_circle_outline : Icons.warning_amber),
            title: Text(_autoDetected
                ? 'Server settings auto-detected'
                : 'Auto-detect failed'),
            subtitle: Text(_autoDetected
                ? 'Review and tap Accept, or edit below.'
                : 'Enter your IMAP and SMTP server details manually.'),
          ),
        ),
        const SizedBox(height: 16),
        Text('Incoming (IMAP)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
            controller: _imapHost,
            decoration: const InputDecoration(
                labelText: 'IMAP host',
                prefixIcon: Icon(Icons.dns_outlined)),
          )),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _imapPort,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            ),
          ),
        ]),
        SwitchListTile(
          title: const Text('SSL/TLS'),
          value: _imapSsl,
          onChanged: (v) => setState(() => _imapSsl = v),
        ),
        const SizedBox(height: 16),
        Text('Outgoing (SMTP)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
            controller: _smtpHost,
            decoration: const InputDecoration(
                labelText: 'SMTP host',
                prefixIcon: Icon(Icons.dns_outlined)),
          )),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _smtpPort,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            ),
          ),
        ]),
        SwitchListTile(
          title: const Text('SSL/TLS'),
          value: _smtpSsl,
          onChanged: (v) => setState(() => _smtpSsl = v),
        ),
        const SizedBox(height: 16),
        if (_info != null && _busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text(_info!)),
              ],
            ),
          ),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_err!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
          ),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text('Accept & connect'),
        ),
      ],
    );
  }
}
