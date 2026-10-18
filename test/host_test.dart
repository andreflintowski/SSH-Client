import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_client/models/host.dart';

void main() {
  test('host list survives a JSON round trip', () {
    const host = Host(
      id: 'a1',
      label: 'Home server',
      hostname: '192.168.1.10',
      port: 2222,
      username: 'andre',
      auth: AuthMethod.key,
      knownFingerprint: 'SHA256:abc',
    );
    final decoded = Host.decodeList(Host.encodeList([host])).single;
    expect(decoded.toJson(), host.toJson());
  });

  test('displayName falls back to user@host', () {
    const host = Host(id: 'b', label: '', hostname: 'example.com', username: 'root');
    expect(host.displayName, 'root@example.com');
  });
}
