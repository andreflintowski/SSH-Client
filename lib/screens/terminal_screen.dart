import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../data/host_repository.dart';
import '../models/host.dart';
import '../ssh/ssh_session.dart';
import '../widgets/extra_keys_bar.dart';

class TerminalScreen extends StatefulWidget {
  final HostRepository repo;
  final Host host;

  const TerminalScreen({super.key, required this.repo, required this.host});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  SshSession? _session;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final secrets = await widget.repo.secrets.read(widget.host.id);
    if (!mounted) return;
    final session = SshSession(
      host: widget.host,
      secrets: secrets,
      onHostKey: _askHostKey,
      onFingerprintAccepted: (fp) {
        widget.repo.save(widget.host.copyWith(knownFingerprint: fp));
      },
    );
    setState(() => _session = session);
    await session.connect();
  }

  Future<bool> _askHostKey(
      String type, String fingerprint, String? previous) async {
    if (!mounted) return false;
    final changed = previous != null;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(changed ? 'Host key CHANGED' : 'Unknown host'),
        content: SelectableText(
          changed
              ? 'The server key differs from the saved one. This may be an '
                  'attack (MITM) or a reinstalled server.\n\n'
                  'Old: $previous\nNew ($type): $fingerprint'
              : 'First connection to ${widget.host.hostname}.\n\n'
                  '$type\n$fingerprint\n\nTrust this key?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(changed ? 'Trust new key' : 'Trust')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _reconnect() async {
    _session?.dispose();
    setState(() => _session = null);
    await _start();
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.host.displayName),
        actions: [
          if (session != null)
            ListenableBuilder(
              listenable: session,
              builder: (_, _) => session.state == SessionState.connected
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Reconnect',
                      onPressed:
                          session.state == SessionState.connecting
                              ? null
                              : _reconnect,
                    ),
            ),
        ],
      ),
      body: session == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: TerminalView(
                      session.terminal,
                      autofocus: true,
                      keyboardType: TextInputType.visiblePassword,
                      textStyle: const TerminalStyle(fontSize: 13),
                    ),
                  ),
                  ExtraKeysBar(session: session),
                ],
              ),
            ),
    );
  }
}
