import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/host.dart';
import 'secret_store.dart';

/// Host list (metadata in SharedPreferences, secrets in [SecretStore]).
class HostRepository extends ChangeNotifier {
  static const _prefsKey = 'hosts.v1';

  final SecretStore secrets;
  List<Host> _hosts = [];

  HostRepository({SecretStore? secrets}) : secrets = secrets ?? SecretStore();

  List<Host> get hosts => List.unmodifiable(_hosts);

  /// Set when the saved host list could not be read.
  String? loadError;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 10));
      final raw = prefs.getString(_prefsKey);
      _hosts = raw == null ? [] : Host.decodeList(raw);
      loadError = null;
    } catch (e) {
      loadError = '$e';
    }
    notifyListeners();
  }

  Future<void> save(Host host, {HostSecrets? newSecrets}) async {
    final i = _hosts.indexWhere((h) => h.id == host.id);
    if (i >= 0) {
      _hosts[i] = host;
    } else {
      _hosts.add(host);
    }
    if (newSecrets != null) await secrets.write(host.id, newSecrets);
    await _persist();
  }

  Future<void> delete(String id) async {
    _hosts.removeWhere((h) => h.id == id);
    await secrets.delete(id);
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, Host.encodeList(_hosts));
    notifyListeners();
  }
}
