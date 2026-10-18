import 'dart:math';

import 'package:flutter/material.dart';

import '../data/host_repository.dart';
import '../models/host.dart';

class HostEditScreen extends StatefulWidget {
  final HostRepository repo;
  final Host? host;

  const HostEditScreen({super.key, required this.repo, this.host});

  @override
  State<HostEditScreen> createState() => _HostEditScreenState();
}

class _HostEditScreenState extends State<HostEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.host?.label);
  late final _hostname = TextEditingController(text: widget.host?.hostname);
  late final _port =
      TextEditingController(text: '${widget.host?.port ?? 22}');
  late final _username = TextEditingController(text: widget.host?.username);
  final _password = TextEditingController();
  final _privateKey = TextEditingController();
  final _passphrase = TextEditingController();
  late AuthMethod _auth = widget.host?.auth ?? AuthMethod.password;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final h = widget.host;
    if (h != null) {
      widget.repo.secrets.read(h.id).then((s) {
        if (!mounted) return;
        _password.text = s.password ?? '';
        _privateKey.text = s.privateKey ?? '';
        _passphrase.text = s.passphrase ?? '';
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _label, _hostname, _port, _username, _password, _privateKey, _passphrase
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final old = widget.host;
    final hostname = _hostname.text.trim();
    final port = int.parse(_port.text.trim());
    final host = Host(
      id: old?.id ?? _newId(),
      label: _label.text.trim(),
      hostname: hostname,
      port: port,
      username: _username.text.trim(),
      auth: _auth,
      // A different server address means a different host key.
      knownFingerprint: (old != null &&
              old.hostname == hostname &&
              old.port == port)
          ? old.knownFingerprint
          : null,
    );
    await widget.repo.save(
      host,
      newSecrets: HostSecrets(
        password: _auth == AuthMethod.password ? _password.text : null,
        privateKey: _auth == AuthMethod.key ? _privateKey.text.trim() : null,
        passphrase: _auth == AuthMethod.key ? _passphrase.text : null,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.host == null ? 'New host' : 'Edit host'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label (optional)'),
            ),
            TextFormField(
              controller: _hostname,
              decoration: const InputDecoration(labelText: 'Host or IP'),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: _required,
            ),
            TextFormField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final p = int.tryParse(v ?? '');
                return (p == null || p < 1 || p > 65535) ? '1-65535' : null;
              },
            ),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
              autocorrect: false,
              validator: _required,
            ),
            const SizedBox(height: 16),
            SegmentedButton<AuthMethod>(
              segments: const [
                ButtonSegment(
                    value: AuthMethod.password, label: Text('Password')),
                ButtonSegment(value: AuthMethod.key, label: Text('SSH key')),
              ],
              selected: {_auth},
              onSelectionChanged: (s) => setState(() => _auth = s.first),
            ),
            const SizedBox(height: 8),
            if (_auth == AuthMethod.password)
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              )
            else ...[
              TextFormField(
                controller: _privateKey,
                decoration: const InputDecoration(
                  labelText: 'Private key (PEM / OpenSSH)',
                  hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                ),
                minLines: 4,
                maxLines: 10,
                autocorrect: false,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                validator: _required,
              ),
              TextFormField(
                controller: _passphrase,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Key passphrase (optional)'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Passwords and keys are stored in the iOS Keychain / Android Keystore.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
