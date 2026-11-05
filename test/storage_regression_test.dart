import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_client/data/host_repository.dart';
import 'package:ssh_client/data/secret_store.dart';
import 'package:ssh_client/main.dart' as app;
import 'package:ssh_client/models/host.dart';
import 'package:ssh_client/screens/host_edit_screen.dart';
import 'package:ssh_client/screens/terminal_screen.dart';
import 'package:ssh_client/ssh/host_fingerprint.dart';

const host = Host(
  id: 'a',
  label: 'test',
  hostname: '127.0.0.1',
  username: 'audit',
);

class FakeSecrets extends SecretStore {
  bool failRead = false, failWrite = false;
  Completer<HostSecrets>? pending;
  int writes = 0;
  @override
  Future<HostSecrets> read(String id) async {
    if (failRead) throw PlatformException(code: 'keychain_unavailable');
    if (pending != null) return pending!.future;
    return const HostSecrets(password: 'test-only');
  }

  @override
  Future<void> write(String id, HostSecrets secrets) async {
    writes++;
    if (failWrite) throw PlatformException(code: 'keychain_unavailable');
  }

  @override
  Future<void> delete(String id) async {}
}

class DelayedWriteSecrets extends FakeSecrets {
  final completed = Completer<void>();
  @override
  Future<void> write(String id, HostSecrets secrets) async {
    writes++;
    await completed.future;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('legacy fingerprint preserves identity; arbitrary malformed pins stay untrusted', () {
    final canonical =
        'SHA256:${base64.encode(List<int>.generate(32, (i) => i)).replaceAll('=', '')}';
    final old =
        'SHA256:${base64.encode(utf8.encode(canonical)).replaceAll('=', '')}';
    expect(normalizeStoredFingerprint(old), canonical);
    expect(normalizeStoredFingerprint(canonical), canonical);
    for (final value in [
      'garbage',
      'SHA256:bad',
      'SHA256:${base64.encode(utf8.encode('SHA256:bad'))}',
    ]) {
      expect(normalizeStoredFingerprint(value), value);
    }
  });
  test(
    'corrupt JSON is retained, writes blocked, retry recovers existing format',
    () async {
      SharedPreferences.setMockInitialValues({'hosts.v1': '{broken'});
      final repo = HostRepository();
      await repo.load();
      expect(repo.loadError, isNotNull);
      await expectLater(repo.save(host), throwsStateError);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hosts.v1'), '{broken');
      await prefs.setString('hosts.v1', Host.encodeList([host]));
      await repo.load();
      expect(repo.loadError, isNull);
      expect(repo.hosts.single.toJson(), host.toJson());
    },
  );
  test('failed and stalled preferences release loading state', () async {
    final failed = HostRepository(
      preferences: () async => throw PlatformException(code: 'unavailable'),
    );
    await failed.load();
    expect(failed.isLoading, isFalse);
    expect(failed.loadError, isNotNull);
    final pending = Completer<SharedPreferences>();
    final stalled = HostRepository(
      preferences: () => pending.future,
      storageTimeout: const Duration(milliseconds: 20),
    );
    await stalled.load();
    expect(stalled.isLoading, isFalse);
    expect(stalled.loadError, isNotNull);
    pending.complete(await SharedPreferences.getInstance());
  });
  test(
    'failed secret write does not replace metadata; queue can retry',
    () async {
      final secrets = FakeSecrets();
      final repo = HostRepository(secrets: secrets);
      await repo.save(host);
      secrets.failWrite = true;
      await expectLater(
        repo.save(
          host.copyWith(label: 'bad'),
          newSecrets: const HostSecrets(password: 'new'),
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(repo.hosts.single.label, 'test');
      final prefs = await SharedPreferences.getInstance();
      expect(
        Host.decodeList(prefs.getString('hosts.v1')!).single.label,
        'test',
      );
      secrets.failWrite = false;
      await repo.save(host.copyWith(label: 'retried'));
      expect(repo.hosts.single.label, 'retried');
    },
  );
  test(
    'timed-out writes stay ordered and timed-out queued retries never write',
    () async {
      final secrets = DelayedWriteSecrets();
      final repo = HostRepository(
        secrets: secrets,
        storageTimeout: const Duration(milliseconds: 30),
      );
      await repo.save(host);
      final first = repo.save(
        host.copyWith(label: 'first'),
        newSecrets: const HostSecrets(password: 'first'),
      );
      await expectLater(first, throwsA(isA<TimeoutException>()));
      final second = repo.save(
        host.copyWith(label: 'cancelled'),
        newSecrets: const HostSecrets(password: 'cancelled'),
      );
      await expectLater(second, throwsA(isA<TimeoutException>()));
      expect(secrets.writes, 1);
      expect(repo.hosts.single.label, 'test');
      secrets.completed.complete();
      for (var i = 0; i < 100 && repo.hosts.single.label != 'first'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect(repo.hosts.single.label, 'first');
      expect(secrets.writes, 1);
      await repo.save(host.copyWith(label: 'recovered'));
      expect(repo.hosts.single.label, 'recovered');
    },
  );

  test('fingerprint save cannot resurrect a deleted host or overwrite an edited address', () async {
    final repo = HostRepository(secrets: FakeSecrets());
    await repo.save(host);
    await repo.save(host.copyWith(hostname: 'other.example'));
    await expectLater(
      repo.pinFingerprint(host, 'SHA256:test'),
      throwsStateError,
    );
    expect(repo.hosts.single.hostname, 'other.example');
    await repo.delete(host.id);
    await expectLater(
      repo.pinFingerprint(host, 'SHA256:test'),
      throwsStateError,
    );
    expect(repo.hosts, isEmpty);
  });
  testWidgets('main renders UI with recoverable error for malformed hosts', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({'hosts.v1': '{broken'});
    await app.main();
    await t.pumpAndSettle();
    expect(find.text('Hosts'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      t
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'terminal Keychain failure offers reconnect; leaving during retry is safe',
    (t) async {
      final secrets = FakeSecrets()..failRead = true;
      final repo = HostRepository(secrets: secrets);
      await repo.save(host);
      await t.pumpWidget(
        MaterialApp(
          home: TerminalScreen(repo: repo, host: host),
        ),
      );
      await t.pump();
      expect(
        find.textContaining('Could not read saved credentials'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Reconnect'), findsOneWidget);
      secrets.failRead = false;
      secrets.pending = Completer<HostSecrets>();
      await t.tap(find.byTooltip('Reconnect'));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      secrets.pending!.complete(const HostSecrets());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('stalled Keychain read times out instead of endless spinner', (
    t,
  ) async {
    final secrets = FakeSecrets()..pending = Completer<HostSecrets>();
    final repo = HostRepository(secrets: secrets);
    await repo.save(host);
    await t.pumpWidget(
      MaterialApp(
        home: TerminalScreen(repo: repo, host: host),
      ),
    );
    await t.pump();
    await t.pump(const Duration(seconds: 11));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('Reconnect'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    secrets.pending!.complete(const HostSecrets());
    await t.pump();
  });
  testWidgets(
    'edit cannot overwrite secrets after failed read, and retry restores form',
    (t) async {
      final secrets = FakeSecrets()..failRead = true;
      final repo = HostRepository(secrets: secrets);
      await repo.save(host);
      await t.pumpWidget(
        MaterialApp(
          home: HostEditScreen(repo: repo, host: host),
        ),
      );
      await t.pump();
      expect(
        t
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check))
            .onPressed,
        isNull,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(secrets.writes, 0);
      secrets.failRead = false;
      await t.tap(find.text('Retry'));
      await t.pump();
      expect(find.byType(Form), findsOneWidget);
      expect(
        t
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check))
            .onPressed,
        isNotNull,
      );
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    },
  );
}
