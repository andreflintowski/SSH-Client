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
  String? _startError;
  bool _starting = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_starting) return;
    final attempt = ++_attempt;
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      final host = widget.repo.hosts.firstWhere((h) => h.id == widget.host.id);
      final secrets = await widget.repo.secrets
          .read(host.id)
          .timeout(widget.repo.storageTimeout);
      if (!mounted || attempt != _attempt) return;
      final session = SshSession(
        host: host,
        secrets: secrets,
        onHostKey: _askHostKey,
        onFingerprintAccepted: (fp) => widget.repo.pinFingerprint(host, fp),
      );
      setState(() {
        _session = session;
        _starting = false;
      });
      await session.connect();
    } catch (_) {
      if (mounted && attempt == _attempt) {
        setState(() {
          _starting = false;
          _startError = 'Could not read saved credentials. Unlock your device and try reconnecting.';
        });
      }
    }
  }

  Future<bool> _askHostKey(
    String type,
    String fingerprint,
    String? previous,
  ) async {
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
              : 'First connection to ${_session?.host.hostname ?? widget.host.hostname}.\n\n'
                    '$type\n$fingerprint\n\nTrust this key?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(changed ? 'Trust new key' : 'Trust'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _reconnect() async {
    if (_starting) return;
    _session?.dispose();
    setState(() => _session = null);
    await _start();
  }

  @override
  void dispose() {
    _attempt++;
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
          if (_startError != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reconnect',
              onPressed: _reconnect,
            ),
          if (session != null)
            ListenableBuilder(
              listenable: session,
              builder: (_, _) => session.state == SessionState.connected
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Reconnect',
                      onPressed: session.state == SessionState.connecting
                          ? null
                          : _reconnect,
                    ),
            ),
        ],
      ),
      body: _startError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_startError!),
              ),
            )
          : session == null
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
