import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/host.dart';
import 'secret_store.dart';

/// Host metadata stays in hosts.v1; credentials stay in the existing Keychain keys.
class HostRepository extends ChangeNotifier {
  static const _prefsKey = 'hosts.v1';
  final SecretStore secrets;
  final Duration storageTimeout;
  final Future<SharedPreferences> Function() _preferences;
  List<Host> _hosts = [];
  Future<void> _mutations = Future<void>.value();
  bool isLoading = false;
  String? loadError;

  HostRepository({
    SecretStore? secrets,
    Future<SharedPreferences> Function()? preferences,
    this.storageTimeout = const Duration(seconds: 10),
  }) : secrets = secrets ?? SecretStore(),
       _preferences = preferences ?? SharedPreferences.getInstance;

  List<Host> get hosts => List.unmodifiable(_hosts);

  Future<void> load() async {
    if (isLoading) return;
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      final prefs = await _preferences().timeout(storageTimeout);
      final raw = prefs.getString(_prefsKey);
      final loaded = raw == null ? <Host>[] : Host.decodeList(raw);
      _hosts = loaded;
    } catch (_) {
      // Preserve both the stored bytes and the last successfully loaded list.
      loadError =
          'Could not read saved hosts. Your saved data has not been replaced.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _checkReady() {
    if (isLoading || loadError != null) {
      throw StateError('Saved hosts must be loaded before making changes.');
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    var started = false;
    var cancelled = false;
    final next = _mutations.then((_) async {
      if (cancelled) return;
      started = true;
      await action();
    });
    // Platform writes cannot be cancelled. Keep the queue locked until the
    // actual write settles, even if the caller has already seen a timeout.
    _mutations = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next.timeout(
      storageTimeout,
      onTimeout: () {
        if (!started) cancelled = true;
        throw TimeoutException(
          'Storage did not respond. Please retry.',
          storageTimeout,
        );
      },
    );
  }

  Future<void> save(Host host, {HostSecrets? newSecrets}) => _enqueue(() async {
    _checkReady();
    final next = [..._hosts];
    final i = next.indexWhere((h) => h.id == host.id);
    if (i >= 0) {
      next[i] = host;
    } else {
      next.add(host);
    }
    if (newSecrets != null) {
      await secrets.write(host.id, newSecrets);
    }
    await _persist(next);
  });

  /// Update the current entry, without resurrecting a deleted/edited server.
  Future<void> pinFingerprint(Host expected, String fingerprint) => _enqueue(
    () async {
      _checkReady();
      final i = _hosts.indexWhere((h) => h.id == expected.id);
      if (i < 0 ||
          _hosts[i].hostname != expected.hostname ||
          _hosts[i].port != expected.port) {
        throw StateError('The host changed while its key was being verified.');
      }
      final next = [..._hosts];
      next[i] = next[i].copyWith(knownFingerprint: fingerprint);
      await _persist(next);
    },
  );

  Future<void> delete(String id) => _enqueue(() async {
    _checkReady();
    await secrets.delete(id);
    await _persist(_hosts.where((h) => h.id != id).toList());
  });

  Future<void> _persist(List<Host> next) async {
    final prefs = await _preferences().timeout(storageTimeout);
    final saved = await prefs.setString(_prefsKey, Host.encodeList(next));
    if (!saved) throw StateError('Could not save host data.');
    _hosts = next;
    notifyListeners();
  }
}
