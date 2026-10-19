import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../ssh/ssh_session.dart';

/// Keys that the phone keyboard lacks: Esc, Tab, sticky Ctrl, arrows, symbols.
class ExtraKeysBar extends StatelessWidget {
  final SshSession session;

  const ExtraKeysBar({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final t = session.terminal;
    return Material(
      color: const Color(0xFF1E1E1E),
      child: SizedBox(
        height: 44,
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _key('Esc', () => t.keyInput(TerminalKey.escape)),
              _key('Tab', () => t.keyInput(TerminalKey.tab)),
              _key('Ctrl', session.toggleCtrl, active: session.ctrlArmed),
              _key('↑', () => t.keyInput(TerminalKey.arrowUp)),
              _key('↓', () => t.keyInput(TerminalKey.arrowDown)),
              _key('←', () => t.keyInput(TerminalKey.arrowLeft)),
              _key('→', () => t.keyInput(TerminalKey.arrowRight)),
              for (final s in ['|', '-', '/', '~', ':', '*', '&'])
                _key(s, () => session.send(s)),
              _key('Home', () => t.keyInput(TerminalKey.home)),
              _key('End', () => t.keyInput(TerminalKey.end)),
              _key('PgUp', () => t.keyInput(TerminalKey.pageUp)),
              _key('PgDn', () => t.keyInput(TerminalKey.pageDown)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _key(String label, VoidCallback onTap, {bool active = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: active ? Colors.blueGrey : null,
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
      ),
    );
  }
}
