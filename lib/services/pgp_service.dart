import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openpgp/openpgp.dart';

class PgpKeys {
  final String publicKey;
  final String privateKey;
  PgpKeys(this.publicKey, this.privateKey);
}

class PgpService {
  PgpService._();
  static final PgpService instance = PgpService._();
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _pubKey(String accountId) => 'pgp_pub_$accountId';
  String _privKey(String accountId) => 'pgp_priv_$accountId';
  String _passKey(String accountId) => 'pgp_pass_$accountId';

  Future<PgpKeys> generate({
    required String accountId,
    required String name,
    required String email,
    required String passphrase,
  }) async {
    final opts = Options()
      ..name = name
      ..email = email
      ..passphrase = passphrase
      ..keyOptions = (KeyOptions()..rsaBits = 3072);
    final pair = await OpenPGP.generate(options: opts);
    await _store.write(key: _pubKey(accountId), value: pair.publicKey);
    await _store.write(key: _privKey(accountId), value: pair.privateKey);
    await _store.write(key: _passKey(accountId), value: passphrase);
    return PgpKeys(pair.publicKey, pair.privateKey);
  }

  Future<PgpKeys?> load(String accountId) async {
    final pub = await _store.read(key: _pubKey(accountId));
    final priv = await _store.read(key: _privKey(accountId));
    if (pub == null || priv == null) return null;
    return PgpKeys(pub, priv);
  }

  Future<void> import({
    required String accountId,
    required String publicKey,
    required String privateKey,
    required String passphrase,
  }) async {
    await _store.write(key: _pubKey(accountId), value: publicKey);
    await _store.write(key: _privKey(accountId), value: privateKey);
    await _store.write(key: _passKey(accountId), value: passphrase);
  }

  Future<void> delete(String accountId) async {
    await _store.delete(key: _pubKey(accountId));
    await _store.delete(key: _privKey(accountId));
    await _store.delete(key: _passKey(accountId));
  }

  Future<String> encrypt(String plaintext, String recipientPublicKey) {
    return OpenPGP.encrypt(plaintext, recipientPublicKey);
  }

  Future<String> decrypt(String ciphertext, String accountId) async {
    final priv = await _store.read(key: _privKey(accountId));
    final pass = await _store.read(key: _passKey(accountId)) ?? '';
    if (priv == null) throw StateError('No private key for $accountId');
    return OpenPGP.decrypt(ciphertext, priv, pass);
  }

  Future<String> sign(String text, String accountId) async {
    final priv = await _store.read(key: _privKey(accountId));
    final pass = await _store.read(key: _passKey(accountId)) ?? '';
    if (priv == null) throw StateError('No private key for $accountId');
    return OpenPGP.sign(text, priv, pass);
  }
}
