import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'add_stream_dialog.dart';
import 'explore_sheet.dart';
import 'help_sheet.dart';
import 'settings_sheet.dart';
import 'streaming/streaming_section.dart';
import 'widgets/ai_companion_panel.dart';
import 'widgets/chat_panel.dart';
import 'widgets/player_panel.dart';

/// Phone-first shell. Desktop keeps the existing multi-column [HomeScreen].
///
/// Streaming is intentionally the primary mobile destination because it owns
/// the cross-cutting session controls: Twitch/Helix, local playback, secure
/// backend health, buffering policy and future foreground-service state.
final class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

final class _MobileHomeScreenState extends State<MobileHomeScreen> {
  int _tab = 0;

  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final page = switch (_tab) {
      0 => StreamingSection(controller: controller),
      1 => PlayerPanel(controller: controller),
      2 => ChatPanel(controller: controller),
      _ => AiCompanionPanel(controller: controller),
    };

    return Scaffold(
      body: Listener(
        onPointerDown: (_) => controller.userActivity(),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _MobileCommandBar(
                controller: controller,
                onStreams: () => setState(() => _tab = 0),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                  child: RepaintBoundary(child: page),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub_rounded),
            label: 'Streaming',
          ),
          NavigationDestination(
            icon: Icon(Icons.live_tv_outlined),
            selectedIcon: Icon(Icons.live_tv_rounded),
            label: 'Player',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum_rounded),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'AI',
          ),
        ],
      ),
    );
  }
}

final class _MobileCommandBar extends StatelessWidget {
  const _MobileCommandBar({
    required this.controller,
    required this.onStreams,
  });

  final AppController controller;
  final VoidCallback onStreams;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(
        children: <Widget>[
          IconButton.filledTonal(
            onPressed: onStreams,
            icon: const Icon(Icons.hub_rounded),
            tooltip: 'Streaming',
          ),
          const SizedBox(width: 7),
          IconButton.filled(
            onPressed: () => showExploreSheet(context, controller),
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Explore Twitch',
          ),
          const Spacer(),
          IconButton.filledTonal(
            onPressed: () => showAddStreamDialog(context, controller),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add stream',
          ),
          const SizedBox(width: 7),
          IconButton.filledTonal(
            onPressed: () => showHelpSheet(context, controller),
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'Help',
          ),
          const SizedBox(width: 7),
          IconButton.filledTonal(
            onPressed: () => showSettingsSheet(context, controller),
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Control Center',
          ),
        ],
      ),
    );
  }
}
