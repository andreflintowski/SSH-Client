import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_client/data/host_repository.dart';
import 'package:ssh_client/data/secret_store.dart';
import 'package:ssh_client/models/host.dart';
import 'package:ssh_client/screens/terminal_screen.dart';
import 'package:ssh_client/ssh/ssh_session.dart';
import 'package:ssh_client/widgets/extra_keys_bar.dart';

late Map<String, dynamic> config;
Host host({String? pin, AuthMethod auth = AuthMethod.password}) => Host(
  id: 'live',
  label: 'Loopback test',
  hostname: '127.0.0.1',
  port: config['port'],
  username: 'audit',
  knownFingerprint: pin,
  auth: auth,
);
SshSession session({
  Host? h,
  HostSecrets? credentials,
  HostKeyPrompt? prompt,
  Future<void> Function(String)? pin,
  Future<SSHSocket> Function()? open,
}) => SshSession(
  host: h ?? host(),
  secrets: credentials ?? HostSecrets(password: config['password']),
  onHostKey: prompt ?? ((a, b, c) async => true),
  onFingerprintAccepted: pin ?? ((_) async {}),
  openSocket: open,
);
Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Timed out waiting for SSH state');
}

Future<void> finish(SshSession s) async {
  if (s.state == SessionState.connected) {
    s.send('exit\r');
    await until(() => s.state == SessionState.disconnected);
  }
  s.dispose();
  await Future<void>.delayed(const Duration(milliseconds: 30));
}

class MemorySecrets extends SecretStore {
  @override
  Future<HostSecrets> read(String id) async =>
      HostSecrets(password: config['password']);
}

Future<void> waitUi(WidgetTester t, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(const Duration(milliseconds: 50));
    if (ready()) return;
  }
  throw StateError('Timed out waiting for SSH widget');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['SSH_AUDIT_CONFIG'];
  group(
    'loopback SSH',
    () {
      setUpAll(() => config = jsonDecode(File(path!).readAsStringSync()));
      test(
        'fingerprint equals ssh-keygen and shell waits for durable pin',
        () async {
          final saved = Completer<void>();
          var called = false;
          String? actual;
          final s = session(
            prompt: (a, b, c) async {
              actual = b;
              return true;
            },
            pin: (fp) async {
              called = true;
              await saved.future;
            },
          );
          final connecting = s.connect();
          await until(() => called);
          expect(actual, config['fingerprint']);
          expect(s.state, SessionState.connecting);
          saved.complete();
          await connecting;
          expect(s.state, SessionState.connected, reason: s.error);
          await finish(s);
        },
      );
      test(
        'legacy pin migrates only for same key, canonical pin needs no prompt',
        () async {
          final fp = config['fingerprint'] as String;
          final old =
              'SHA256:${base64.encode(utf8.encode(fp)).replaceAll('=', '')}';
          for (final stored in [old, fp]) {
            var prompts = 0;
            String? saved;
            final s = session(
              h: host(pin: stored),
              prompt: (a, b, c) async {
                prompts++;
                return false;
              },
              pin: (value) async {
                saved = value;
              },
            );
            await s.connect();
            expect(s.state, SessionState.connected, reason: s.error);
            expect(prompts, 0);
            expect(saved, stored == old ? fp : null);
            await finish(s);
          }
        },
      );
      test('changed key and first-connection refusal stay blocked', () async {
        for (final previous in <String?>[null, 'SHA256:old-key']) {
          String? shown;
          var prompts = 0;
          final s = session(
            h: host(pin: previous),
            prompt: (a, b, c) async {
              prompts++;
              shown = c;
              expect(b, config['fingerprint']);
              return false;
            },
          );
          await s.connect();
          expect(prompts, 1);
          expect(shown, previous);
          expect(s.state, SessionState.failed);
          s.dispose();
        }
      });
      test(
        'pin persistence failure fails visibly before opening shell',
        () async {
          final s = session(
            pin: (_) async => throw StateError('pin storage unavailable'),
          );
          await s.connect();
          expect(s.state, SessionState.failed);
          expect(s.error, contains('pin storage unavailable'));
          s.dispose();
        },
      );
      test(
        'late TCP completion after dispose closes socket without notifications',
        () async {
          final server = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          final accepted = Completer<Socket>();
          server.listen(accepted.complete);
          final socket = await SSHSocket.connect('127.0.0.1', server.port);
          final peer = await accepted.future;
          final ended = Completer<void>();
          peer.listen((_) {}, onDone: ended.complete);
          final pending = Completer<SSHSocket>();
          final s = session(open: () => pending.future);
          final connecting = s.connect();
          s.dispose();
          pending.complete(socket);
          await connecting;
          await ended.future.timeout(const Duration(seconds: 2));
          peer.destroy();
          await server.close();
          s.dispose();
        },
      );
      test(
        'dispose during handshake and trust prompt cancels safely',
        () async {
          final server = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          final accepted = Completer<Socket>();
          server.listen(accepted.complete);
          final s = session(h: host().copyWith(port: server.port));
          final connecting = s.connect();
          final peer = await accepted.future;
          s.dispose();
          peer.destroy();
          await server.close();
          await connecting.timeout(const Duration(seconds: 2));
          var prompted = false;
          var pins = 0;
          final decision = Completer<bool>();
          final trust = session(
            prompt: (a, b, c) {
              prompted = true;
              return decision.future;
            },
            pin: (_) async {
              pins++;
            },
          );
          final trusting = trust.connect();
          await until(() => prompted);
          trust.dispose();
          await trusting.timeout(const Duration(seconds: 2));
          decision.complete(true);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(pins, 0);
        },
      );
      test(
        'password, encrypted key, UTF8, PTY resize, Ctrl-C and clean exit',
        () async {
          for (final credentials in [
            HostSecrets(password: config['password']),
            HostSecrets(
              privateKey: File(config['client_key']).readAsStringSync(),
            ),
            HostSecrets(
              privateKey: File(config['encrypted_key']).readAsStringSync(),
              passphrase: config['passphrase'],
            ),
          ]) {
            final s = session(
              h: host(
                auth: credentials.privateKey == null
                    ? AuthMethod.password
                    : AuthMethod.key,
              ),
              credentials: credentials,
            );
            s.terminal.resize(80, 24);
            await s.connect();
            expect(s.state, SessionState.connected, reason: s.error);
            s.send("printf '\\033[31mПроверка-✓\\033[0m\\n'; stty size\r");
            await until(() => s.terminal.buffer.getText().contains('24 80'));
            expect(s.terminal.buffer.getText(), contains('Проверка-✓'));
            s.terminal.resize(100, 30);
            s.send('stty size\r');
            await until(() => s.terminal.buffer.getText().contains('30 100'));
            s.send('sleep 10\r');
            await Future<void>.delayed(const Duration(milliseconds: 100));
            s.toggleCtrl();
            s.send('c');
            s.send("printf 'CTRL_OK\\n'\r");
            await until(
              () => s.terminal.buffer.getText().contains('CTRL_OK\n'),
            );
            expect(s.ctrlArmed, isFalse);
            await finish(s);
          }
        },
      );
      test(
        'incorrect password and passphrase fail without leaking a session',
        () async {
          for (final credentials in [
            const HostSecrets(password: 'wrong'),
            HostSecrets(
              privateKey: File(config['encrypted_key']).readAsStringSync(),
              passphrase: 'wrong',
            ),
          ]) {
            final s = session(
              h: host(
                auth: credentials.privateKey == null
                    ? AuthMethod.password
                    : AuthMethod.key,
              ),
              credentials: credentials,
            );
            await s.connect();
            expect(s.state, SessionState.failed);
            expect(s.error, isNotEmpty);
            s.dispose();
          }
        },
      );
      testWidgets(
        'Reconnect uses persisted pin, exits and closes without another prompt',
        (t) async {
          SharedPreferences.setMockInitialValues({});
          final repo = HostRepository(secrets: MemorySecrets());
          final h = host();
          await repo.save(h);
          await t.pumpWidget(
            MaterialApp(
              home: TerminalScreen(repo: repo, host: h),
            ),
          );
          await waitUi(
            t,
            () => find.text('Unknown host').evaluate().isNotEmpty,
          );
          await t.tap(find.text('Trust'));
          await t.pump();
          SshSession current() =>
              t.widget<ExtraKeysBar>(find.byType(ExtraKeysBar)).session;
          await waitUi(t, () => current().state != SessionState.connecting);
          expect(
            current().state,
            SessionState.connected,
            reason: current().error,
          );
          expect(repo.hosts.single.knownFingerprint, config['fingerprint']);
          current().send('exit\r');
          await waitUi(t, () => current().state == SessionState.disconnected);
          await t.tap(find.byTooltip('Reconnect'));
          await t.pump();
          await waitUi(t, () => current().state != SessionState.connecting);
          expect(find.text('Unknown host'), findsNothing);
          expect(
            current().state,
            SessionState.connected,
            reason: current().error,
          );
          await t.pumpWidget(const SizedBox());
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await t.pump();
          expect(t.takeException(), isNull);
        },
      );
    },
    skip: path == null
        ? 'Set SSH_AUDIT_CONFIG to a disposable loopback fixture config.'
        : false,
  );
}
