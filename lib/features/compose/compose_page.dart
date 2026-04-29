import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/account_store.dart';
import '../../data/providers.dart';
import '../../models/account.dart';
import '../../services/imap_service.dart';
import '../../services/smtp_service.dart';
import '../../services/voice_service.dart';

class ComposeExtra {
  final String? accountId;
  final String? toAddr;
  final String? ccAddr;
  final String? subject;
  final String? quoteBody;
  final String? inReplyTo;
  final String? references;
  final bool isForward;
  const ComposeExtra({
    this.accountId,
    this.toAddr,
    this.ccAddr,
    this.subject,
    this.quoteBody,
    this.inReplyTo,
    this.references,
    this.isForward = false,
  });
}

class ComposePage extends ConsumerStatefulWidget {
  final String? accountId;
  final String? toAddr;
  final String? ccAddr;
  final String? subject;
  final String? quoteBody;
  final String? inReplyTo;
  final String? references;
  final bool isForward;
  const ComposePage({
    super.key,
    this.accountId,
    this.toAddr,
    this.ccAddr,
    this.subject,
    this.quoteBody,
    this.inReplyTo,
    this.references,
    this.isForward = false,
  });

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  Account? _account;
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  final _attachments = <PlatformFile>[];
  bool _showCcBcc = false;
  bool _sending = false;
  bool _listening = false;
  String? _err;
  late final String _initialBody;
  late final String _initialSubject;
  late final String _initialTo;

  @override
  void initState() {
    super.initState();
    _to.text = widget.toAddr ?? '';
    _cc.text = widget.ccAddr ?? '';
    _showCcBcc = (widget.ccAddr ?? '').isNotEmpty;
    _subject.text = widget.subject ?? '';
    if (widget.quoteBody != null) {
      final quoted = widget.quoteBody!
          .replaceAllMapped(RegExp(r'^', multiLine: true), (_) => '> ');
      final marker = widget.isForward
          ? '\n\n---------- Forwarded message ----------\n'
          : '\n\nOn earlier date, wrote:\n';
      _body.text = '\n\n$marker$quoted';
    }
    _initialBody = _body.text;
    _initialSubject = _subject.text;
    _initialTo = _to.text;
    _loadAccount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.quoteBody != null) {
        _bodyFocus.requestFocus();
        _body.selection = const TextSelection.collapsed(offset: 0);
      }
    });
  }

  Future<void> _loadAccount() async {
    final id = widget.accountId;
    if (id != null) {
      final a = await AccountStore.instance.byId(id);
      if (mounted) setState(() => _account = a);
    } else {
      final all = await AccountStore.instance.all();
      if (all.isNotEmpty && mounted) setState(() => _account = all.first);
    }
  }

  @override
  void dispose() {
    for (final c in [_to, _cc, _bcc, _subject, _body]) {
      c.dispose();
    }
    _bodyFocus.dispose();
    VoiceService.instance.cancel();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await VoiceService.instance.stop();
      setState(() => _listening = false);
      return;
    }
    final base = _body.text;
    final ok = await VoiceService.instance.start(
      onResult: (text, isFinal) {
        _body.text =
            base.isEmpty ? text : (base.endsWith(' ') ? base + text : '$base $text');
        _body.selection =
            TextSelection.collapsed(offset: _body.text.length);
        if (isFinal) {
          setState(() => _listening = false);
        }
      },
    );
    if (!ok) {
      setState(() => _err = 'Microphone unavailable');
      return;
    }
    setState(() => _listening = true);
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: false);
    if (result == null) return;
    setState(() => _attachments.addAll(result.files));
  }

  bool _isDirty() {
    return _to.text != _initialTo ||
        _subject.text != _initialSubject ||
        _body.text != _initialBody ||
        _cc.text.isNotEmpty ||
        _bcc.text.isNotEmpty ||
        _attachments.isNotEmpty;
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_isDirty()) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text(
            'Your changes will be lost. Are you sure you want to leave?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep editing')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Discard')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _send() async {
    final account = _account;
    if (account == null) return;
    if (_to.text.trim().isEmpty) {
      setState(() => _err = 'Recipient required');
      return;
    }
    setState(() {
      _sending = true;
      _err = null;
    });
    try {
      final builder = MessageBuilder.prepareMultipartAlternativeMessage();
      builder.from = [MailAddress(account.name, account.email)];
      builder.to = _parseAddrs(_to.text);
      if (_cc.text.trim().isNotEmpty) builder.cc = _parseAddrs(_cc.text);
      if (_bcc.text.trim().isNotEmpty) builder.bcc = _parseAddrs(_bcc.text);
      builder.subject = _subject.text.trim();
      var body = _body.text;
      if (account.signature != null && account.signature!.isNotEmpty) {
        body = '$body\n\n--\n${account.signature}';
      }
      builder.addTextPlain(body);
      for (final a in _attachments) {
        if (a.path == null) continue;
        final f = File(a.path!);
        if (!await f.exists()) continue;
        final bytes = await f.readAsBytes();
        final mime = MediaType.guessFromFileName(a.name);
        builder.addBinary(bytes, mime, filename: a.name);
      }
      if (widget.inReplyTo != null) {
        builder.setHeader('In-Reply-To', widget.inReplyTo!);
        builder.setHeader(
            'References', widget.references ?? widget.inReplyTo!);
      }
      final msg = builder.buildMimeMessage();
      await SmtpService(account).send(msg);
      try {
        final imap = ImapService(account);
        await imap.appendToSent(msg);
        await imap.disconnect();
      } catch (_) {}
      if (mounted) {
        ref.invalidate(accountsProvider);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  List<MailAddress> _parseAddrs(String raw) {
    return raw
        .split(RegExp(r'[,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => MailAddress(null, s))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfDirty();
        if (ok && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Compose'),
          actions: [
            IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              onPressed: _sending ? null : _send,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              accountsAsync.when(
                data: (accounts) => DropdownButtonFormField<String>(
                  value: _account?.id,
                  items: accounts
                      .map((a) => DropdownMenuItem(
                          value: a.id, child: Text(a.email)))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    final a = await AccountStore.instance.byId(v);
                    setState(() => _account = a);
                  },
                  decoration: const InputDecoration(labelText: 'From'),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _to,
                decoration: InputDecoration(
                  labelText: 'To',
                  suffixIcon: TextButton(
                    onPressed: () =>
                        setState(() => _showCcBcc = !_showCcBcc),
                    child: Text(_showCcBcc ? 'hide cc/bcc' : 'cc/bcc'),
                  ),
                ),
              ),
              if (_showCcBcc) ...[
                TextField(
                    controller: _cc,
                    decoration: const InputDecoration(labelText: 'Cc')),
                TextField(
                    controller: _bcc,
                    decoration: const InputDecoration(labelText: 'Bcc')),
              ],
              TextField(
                controller: _subject,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _body,
                focusNode: _bodyFocus,
                minLines: 8,
                maxLines: 20,
                decoration: const InputDecoration(
                    labelText: 'Body', alignLabelWithHint: true),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _toggleVoice,
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                    tooltip: _listening
                        ? 'Stop dictation'
                        : 'Dictate message body',
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _pickAttachment,
                    icon: const Icon(Icons.attach_file),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      children: _attachments
                          .map((a) => Chip(
                                label: Text(a.name),
                                onDeleted: () =>
                                    setState(() => _attachments.remove(a)),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_err!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
