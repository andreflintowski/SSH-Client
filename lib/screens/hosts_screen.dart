import 'package:flutter/material.dart';

import '../data/host_repository.dart';
import '../models/host.dart';
import 'host_edit_screen.dart';
import 'terminal_screen.dart';

class HostsScreen extends StatelessWidget {
  final HostRepository repo;

  const HostsScreen({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hosts')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, null),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final hosts = repo.hosts;
          if (repo.loadError != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text("Couldn't load saved hosts:\n${repo.loadError}"),
              ),
            );
          }
          if (hosts.isEmpty) {
            return const Center(child: Text('No hosts yet. Tap + to add one.'));
          }
          return ListView.separated(
            itemCount: hosts.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final h = hosts[i];
              return ListTile(
                leading: Icon(
                    h.auth == AuthMethod.key ? Icons.vpn_key : Icons.password),
                title: Text(h.displayName),
                subtitle: Text('${h.username}@${h.hostname}:${h.port}'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TerminalScreen(repo: repo, host: h),
                )),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _edit(context, h);
                    if (v == 'delete') _confirmDelete(context, h);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _edit(BuildContext context, Host? host) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HostEditScreen(repo: repo, host: host),
    ));
  }

  Future<void> _confirmDelete(BuildContext context, Host host) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${host.displayName}?'),
        content: const Text('Saved password and key will be removed too.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await repo.delete(host.id);
  }
}
