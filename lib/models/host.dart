import 'dart:convert';

enum AuthMethod { password, key }

/// Host metadata. Secrets (password, private key, passphrase) are NOT stored
/// here; they live in the platform keystore, see [SecretStore].
class Host {
  final String id;
  final String label;
  final String hostname;
  final int port;
  final String username;
  final AuthMethod auth;

  /// Host key fingerprint pinned on first connect (trust on first use).
  final String? knownFingerprint;

  const Host({
    required this.id,
    required this.label,
    required this.hostname,
    this.port = 22,
    required this.username,
    this.auth = AuthMethod.password,
    this.knownFingerprint,
  });

  String get displayName => label.isNotEmpty ? label : '$username@$hostname';

  Host copyWith({
    String? label,
    String? hostname,
    int? port,
    String? username,
    AuthMethod? auth,
    String? knownFingerprint,
    bool clearFingerprint = false,
  }) {
    return Host(
      id: id,
      label: label ?? this.label,
      hostname: hostname ?? this.hostname,
      port: port ?? this.port,
      username: username ?? this.username,
      auth: auth ?? this.auth,
      knownFingerprint:
          clearFingerprint ? null : (knownFingerprint ?? this.knownFingerprint),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hostname': hostname,
        'port': port,
        'username': username,
        'auth': auth.name,
        'knownFingerprint': knownFingerprint,
      };

  factory Host.fromJson(Map<String, dynamic> json) => Host(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        hostname: json['hostname'] as String,
        port: json['port'] as int? ?? 22,
        username: json['username'] as String,
        auth: AuthMethod.values.byName(json['auth'] as String? ?? 'password'),
        knownFingerprint: json['knownFingerprint'] as String?,
      );

  static String encodeList(List<Host> hosts) =>
      jsonEncode(hosts.map((h) => h.toJson()).toList());

  static List<Host> decodeList(String raw) => (jsonDecode(raw) as List)
      .map((e) => Host.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Credentials for one host, kept in Keychain / Keystore.
class HostSecrets {
  final String? password;
  final String? privateKey;
  final String? passphrase;

  const HostSecrets({this.password, this.privateKey, this.passphrase});
}
