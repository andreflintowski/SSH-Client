import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../models/host.dart';
import 'host_fingerprint.dart';

enum SessionState { connecting, connected, disconnected, failed }

/// Asked when the server's host key is new or differs from the pinned one.
/// Return true to trust (and pin) it.
typedef HostKeyPrompt = Future<bool> Function(
  String keyType,
  String fingerprint,
  String? previous,
);

/// One interactive SSH shell bound to an xterm [Terminal].
class SshSession extends ChangeNotifier {
  final Host host;
  final HostSecrets secrets;
  final HostKeyPrompt onHostKey;

  /// Called after the user accepts a new host key, so it can be pinned.
  final Future<void> Function(String fingerprint) onFingerprintAccepted;

  final terminal = Terminal(maxLines: 10000);

  SessionState state = SessionState.connecting;
  String? error;

  final Future<SSHSocket> Function()? openSocket;
  SSHSocket? _socket;
  bool _closed = false;
  bool _disposed = false;
  bool _connecting = false;
  final _cancelled = Completer<void>();
  SSHClient? _client;
  SSHSession? _shell;
  final _subs = <StreamSubscription>[];

  SshSession({
    required this.host,
    required this.secrets,
    required this.onHostKey,
    required this.onFingerprintAccepted,
    this.openSocket,
  });

  Future<void> connect() async {
    if (_closed || _connecting || _client != null) return;
    _connecting = true;
    _setState(SessionState.connecting);
    terminal.write('Connecting to ${host.hostname}:${host.port}...\r\n');
    try {
      // Decode before opening a socket, so invalid keys cannot leak a connection.
      final identities = _identities();
      final socket =
          await (openSocket?.call() ??
              SSHSocket.connect(
                host.hostname,
                host.port,
                timeout: const Duration(seconds: 10),
              ));
      if (_closed) {
        socket.close();
        return;
      }
      _socket = socket;
      final client = SSHClient(
        socket,
        username: host.username,
        onVerifyHostKey: _verifyHostKey,
        onPasswordRequest: () => secrets.password ?? '',
        identities: identities,
      );
      _client = client;
      final shell = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
      if (_closed) {
        shell.close();
        return;
      }
      _shell = shell;
      for (final output in [shell.stdout, shell.stderr]) {
        _subs.add(
          output
              .cast<List<int>>()
              .transform(const Utf8Decoder(allowMalformed: true))
              .listen((data) {
                if (!_closed) terminal.write(data);
              }, onError: (Object e) => _fail(e)),
        );
      }
      terminal.onOutput = send;
      terminal.onResize = (w, h, pw, ph) {
        if (!_closed) shell.resizeTerminal(w, h, pw, ph);
      };
      _setState(SessionState.connected);
      unawaited(
        shell.done.then<void>((_) {
          if (_closed) return;
          terminal.write('\r\n[Connection closed]\r\n');
          _setState(SessionState.disconnected);
          close();
        }, onError: (Object e, StackTrace _) => _fail(e)),
      );
    } catch (e) {
      _fail(e);
    } finally {
      _connecting = false;
    }
  }

  void _fail(Object e) {
    if (_closed) return;
    error = e.toString();
    terminal.write('\r\n\x1b[31mError: $error\x1b[0m\r\n');
    _setState(SessionState.failed);
    close();
  }

  /// Sticky Ctrl from the extra-keys bar: applies to the next typed character.
  bool ctrlArmed = false;

  void toggleCtrl() {
    if (_closed) return;
    ctrlArmed = !ctrlArmed;
    notifyListeners();
  }

  void send(String data) {
    final shell = _shell;
    if (_closed || state != SessionState.connected || shell == null) return;
    if (ctrlArmed && data.length == 1) {
      final c = data.toLowerCase().codeUnitAt(0);
      // a-z and [\]^_ map to 0x01..0x1f
      if ((c >= 0x61 && c <= 0x7a) || (c >= 0x5b && c <= 0x5f)) {
        data = String.fromCharCode(c & 0x1f);
      }
      ctrlArmed = false;
      notifyListeners();
    }
    shell.write(Uint8List.fromList(utf8.encode(data)));
  }

  List<SSHKeyPair>? _identities() {
    if (host.auth != AuthMethod.key) return null;
    final pem = secrets.privateKey;
    if (pem == null || pem.isEmpty) return null;
    final passphrase = (secrets.passphrase?.isEmpty ?? true)
        ? null
        : secrets.passphrase;
    return SSHKeyPair.fromPem(pem, passphrase);
  }

  Future<bool> _verifyHostKey(String type, Uint8List fingerprintBytes) async {
    if (_closed) return false;
    // dartssh2 4.1 supplies the OpenSSH fingerprint as UTF-8, not digest bytes.
    final fp = utf8.decode(fingerprintBytes);
    final stored = host.knownFingerprint;
    final previous = stored == null ? null : normalizeStoredFingerprint(stored);
    if (previous == fp) {
      if (stored != fp) return _pinFingerprint(fp);
      return !_closed;
    }
    final ok = await Future.any<bool>([
      onHostKey(type, fp, previous),
      _cancelled.future.then((_) => false),
    ]);
    if (!ok || _closed) return false;
    // Do not start authentication with a key which failed to persist.
    return _pinFingerprint(fp);
  }

  Future<bool> _pinFingerprint(String fingerprint) async {
    try {
      await onFingerprintAccepted(fingerprint);
      return !_closed;
    } catch (e) {
      // dartssh2 otherwise turns callback failures into a generic auth abort.
      _fail(e);
      return false;
    }
  }

  void _setState(SessionState s) {
    if (_closed) return;
    state = s;
    notifyListeners();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _cancelled.complete();
    terminal.onOutput = null;
    terminal.onResize = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _shell?.close();
    _client?.close();
    _socket?.close();
    _shell = null;
    _client = null;
    _socket = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    close();
    super.dispose();
  }
}
