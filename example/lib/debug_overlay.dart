// A tiny, read-only debug HUD showing the SDK's main-isolate counters
// (Sessionly.debugStats). Toggle it with the bug button. It polls once a second
// and never affects capture — it only reads counters.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

/// Wraps [child] and floats a collapsible SDK-counter panel over it.
class DebugStatsOverlay extends StatefulWidget {
  const DebugStatsOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<DebugStatsOverlay> createState() => _DebugStatsOverlayState();
}

class _DebugStatsOverlayState extends State<DebugStatsOverlay> {
  bool _open = false;
  Map<String, int> _stats = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _stats = Sessionly.debugStats()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_open) _panel(),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    key: const ValueKey('debug_toggle'),
                    heroTag: 'sly_debug',
                    onPressed: () => setState(() => _open = !_open),
                    child: const Icon(Icons.bug_report),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel() {
    return Material(
      elevation: 6,
      color: Colors.black87,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.greenAccent,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SESSIONLY SDK',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              for (final entry in _stats.entries)
                Text('${entry.key.padRight(16)} ${entry.value}'),
              if (_stats.isEmpty) const Text('(not initialized)'),
            ],
          ),
        ),
      ),
    );
  }
}
