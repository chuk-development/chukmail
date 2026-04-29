import 'package:enough_mail/enough_mail.dart';

import '../data/account_store.dart';
import '../models/account.dart';

class SmtpService {
  final Account account;
  SmtpService(this.account);

  Future<void> send(MimeMessage msg) async {
    final pw = await AccountStore.instance.password(account.id);
    if (pw == null) {
      throw StateError('No password stored for account ${account.email}');
    }
    final c = SmtpClient('chukmail', isLogEnabled: false);
    try {
      await c.connectToServer(account.smtpHost, account.smtpPort,
          isSecure: account.smtpSsl);
      await c.ehlo();
      if (!account.smtpSsl) {
        try {
          await c.startTls();
        } catch (_) {}
      }
      await c.authenticate(account.username, pw, AuthMechanism.login);
      await c.sendMessage(msg);
    } finally {
      try {
        await c.quit();
      } catch (_) {}
    }
  }
}
