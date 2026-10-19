import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/host.dart';

/// Wraps iOS Keychain / Android Keystore (via EncryptedSharedPreferences).
class SecretStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  String _key(String hostId, String field) => 'host.$hostId.$field';

  Future<HostSecrets> read(String hostId) async {
    return HostSecrets(
      password: await _storage.read(key: _key(hostId, 'password')),
      privateKey: await _storage.read(key: _key(hostId, 'privateKey')),
      passphrase: await _storage.read(key: _key(hostId, 'passphrase')),
    );
  }

  Future<void> write(String hostId, HostSecrets secrets) async {
    await _put(_key(hostId, 'password'), secrets.password);
    await _put(_key(hostId, 'privateKey'), secrets.privateKey);
    await _put(_key(hostId, 'passphrase'), secrets.passphrase);
  }

  Future<void> delete(String hostId) async {
    for (final f in ['password', 'privateKey', 'passphrase']) {
      await _storage.delete(key: _key(hostId, f));
    }
  }

  Future<void> _put(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }
}
