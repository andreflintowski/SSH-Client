import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../models/host.dart';

enum SessionState { connecting, connected, disconnected, failed }

/// Asked when the server's host key is new or differs from the pinned one.
/// Return true to trust (and pin) it.
typedef HostKeyPrompt = Future<bool> Function(
    String keyType, String fingerprint, String? previous);

/// One interactive SSH shell bound to an xterm [Terminal].
class SshSession extends ChangeNotifier {
  final Host host;
  final HostSecrets secrets;
  final HostKeyPrompt onHostKey;

  /// Called after the user accepts a new host key, so it can be pinned.
  final void Function(String fingerprint) onFingerprintAccepted;

  final terminal = Terminal(maxLines: 10000);

  SessionState state = SessionState.connecting;
  String? error;

  SSHClient? _client;
  SSHSession? _shell;
  final _subs = <StreamSubscription>[];

  SshSession({
    required this.host,
    required this.secrets,
    required this.onHostKey,
    required this.onFingerprintAccepted,
  });

  Future<void> connect() async {
    _setState(SessionState.connecting);
    terminal.write('Connecting to ${host.hostname}:${host.port}...\r\n');
    try {
      final socket = await SSHSocket.connect(
        host.hostname,
        host.port,
        timeout: const Duration(seconds: 10),
      );

      final client = SSHClient(
        socket,
        username: host.username,
        onVerifyHostKey: _verifyHostKey,
        onPasswordRequest: () => secrets.password ?? '',
        identities: _identities(),
      );
      _client = client;

      final shell = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
      _shell = shell;

      // UTF-8 can be split across packets, so decode as a stream.
      _subs.add(shell.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write));
      _subs.add(shell.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write));

      terminal.onOutput = send;
      terminal.onResize = (w, h, pw, ph) {
        shell.resizeTerminal(w, h, pw, ph);
      };

      _setState(SessionState.connected);

      shell.done.whenComplete(() {
        terminal.write('\r\n[Connection closed]\r\n');
        _setState(SessionState.disconnected);
      });
    } catch (e) {
      error = e.toString();
      terminal.write('\r\n\x1b[31mError: $error\x1b[0m\r\n');
      _setState(SessionState.failed);
    }
  }

  /// Sticky Ctrl from the extra-keys bar: applies to the next typed character.
  bool ctrlArmed = false;

  void toggleCtrl() {
    ctrlArmed = !ctrlArmed;
    notifyListeners();
  }

  void send(String data) {
    final shell = _shell;
    if (shell == null) return;
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
    final passphrase =
        (secrets.passphrase?.isEmpty ?? true) ? null : secrets.passphrase;
    return SSHKeyPair.fromPem(pem, passphrase);
  }

  Future<bool> _verifyHostKey(String type, Uint8List fingerprintBytes) async {
    // Same format as `ssh-keygen -lf`: SHA256:<base64 without padding>.
    final fp = 'SHA256:${base64.encode(fingerprintBytes).replaceAll('=', '')}';
    if (host.knownFingerprint == fp) return true;
    final ok = await onHostKey(type, fp, host.knownFingerprint);
    if (ok) onFingerprintAccepted(fp);
    return ok;
  }

  void _setState(SessionState s) {
    state = s;
    notifyListeners();
  }

  void close() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _shell?.close();
    _client?.close();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
