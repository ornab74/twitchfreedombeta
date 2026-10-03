import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../state/app_controller.dart';
import '../../streaming/streaming_backend_client.dart';
import '../theme.dart';
import '../widgets/glass_panel.dart';

/// Mobile-first control surface for playback, Twitch/Helix discovery and the
/// optional DigitalOcean streaming node.
///
/// This widget deliberately uses the existing [AppController] for Twitch,
/// playback, chat and secure-vault state. The remote node is an augmentation,
/// not a replacement for the local-first path.
final class StreamingSection extends StatefulWidget {
  const StreamingSection({
    super.key,
    required this.controller,
    StreamingBackendClient? backend,
  }) : _backend = backend;

  final AppController controller;
  final StreamingBackendClient? _backend;

  @override
  State<StreamingSection> createState() => _StreamingSectionState();
}

final class _StreamingSectionState extends State<StreamingSection>
    with WidgetsBindingObserver {
  late final StreamingBackendClient _backend;
  BackendHealth? _health;
  Object? _backendError;
  bool _checkingBackend = false;
  bool _appInBackground = false;
  Timer? _healthTimer;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backend = widget._backend ?? StreamingBackendClient.fromEnvironment();
    unawaited(_refreshBackendHealth());
    _healthTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(_refreshBackendHealth(silent: true)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background = switch (state) {
      AppLifecycleState.resumed => false,
      AppLifecycleState.inactive ||
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => true,
    };
    if (background == _appInBackground) return;
    setState(() => _appInBackground = background);
  }

  Future<void> _refreshBackendHealth({bool silent = false}) async {
    if (_checkingBackend) return;
    if (!silent && mounted) setState(() => _checkingBackend = true);
    try {
      final health = await _backend.health();
      if (!mounted) return;
      setState(() {
        _health = health;
        _backendError = null;
        _checkingBackend = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _backendError = error;
        _checkingBackend = false;
      });
    }
  }

  Future<void> _play(StreamRecord stream) async {
    await controller.selectStream(stream);
    if (!mounted) return;
    await controller.startPlayback(
      mode: stream.playbackMode,
      quality: stream.quality,
      preferNative: true,
    );
  }

  Future<void> _togglePlayback() async {
    if (controller.playback.playing) {
      await controller.stopPlayback();
      return;
    }
    await controller.startPlayback(preferNative: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        controller.shellRevision,
        controller.navigationRevision,
        controller.playback,
      ]),
      builder: (context, _) {
        final selected = controller.selected;
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              sliver: SliverList.list(
                children: <Widget>[
                  _NowStreamingCard(
                    controller: controller,
                    selected: selected,
                    appInBackground: _appInBackground,
                    onTogglePlayback: _togglePlayback,
                  ),
                  const SizedBox(height: 12),
                  _BackendCard(
                    backendUri: _backend.baseUri,
                    health: _health,
                    error: _backendError,
                    checking: _checkingBackend,
                    onRefresh: _refreshBackendHealth,
                  ),
                  const SizedBox(height: 12),
                  _HelixCard(controller: controller),
                  const SizedBox(height: 12),
                  Text(
                    'Saved streams',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (controller.streams.isEmpty)
                    const _EmptyStreamsCard()
                  else
                    ...controller.streams.map(
                      (stream) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SavedStreamTile(
                          stream: stream,
                          selected: selected?.id == stream.id,
                          onTap: () => controller.selectStream(stream),
                          onPlay: () => _play(stream),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget._backend == null) _backend.close();
    super.dispose();
  }
}

final class _NowStreamingCard extends StatelessWidget {
  const _NowStreamingCard({
    required this.controller,
    required this.selected,
    required this.appInBackground,
    required this.onTogglePlayback,
  });

  final AppController controller;
  final StreamRecord? selected;
  final bool appInBackground;
  final Future<void> Function() onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final tokens = freedomTokens(context);
    final playback = controller.playback;
    final playing = playback.playing;
    final buffering = playback.buffering;
    final streamName = selected?.displayName.isNotEmpty == true
        ? selected!.displayName
        : selected?.channel ?? 'No stream selected';

    return GlassPanel(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: playing
                      ? tokens.good.withValues(alpha: .14)
                      : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  playing ? Icons.graphic_eq_rounded : Icons.live_tv_rounded,
                  color: playing ? tokens.good : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      streamName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      buffering
                          ? 'Buffering…'
                          : playing
                          ? '${playback.variant?.qualityLabel ?? selected?.quality ?? 'auto'} • ${selected?.playbackMode == PlaybackMode.audioOnly ? 'audio' : 'video'}'
                          : 'Ready',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: selected == null ? null : onTogglePlayback,
                icon: Icon(
                  playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                ),
                tooltip: playing ? 'Stop stream' : 'Play stream',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _MiniChip(
                icon: Icons.memory_rounded,
                text: '${playback.cachePolicy.maximumMiB} MiB RAM buffer',
              ),
              _MiniChip(
                icon: Icons.speed_rounded,
                text: controller.preferences.lowLatency
                    ? 'Low latency'
                    : 'Stable buffer',
              ),
              _MiniChip(
                icon: appInBackground
                    ? Icons.phone_android_rounded
                    : Icons.phone_iphone_rounded,
                text: appInBackground ? 'Background' : 'Foreground',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Android background playback will be hosted by a foreground media service so navigation/delivery apps can stay on screen while this session keeps running.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

final class _BackendCard extends StatelessWidget {
  const _BackendCard({
    required this.backendUri,
    required this.health,
    required this.error,
    required this.checking,
    required this.onRefresh,
  });

  final Uri backendUri;
  final BackendHealth? health;
  final Object? error;
  final bool checking;
  final Future<void> Function({bool silent}) onRefresh;

  @override
  Widget build(BuildContext context) {
    final tokens = freedomTokens(context);
    final online = health?.reachable == true;
    return GlassPanel(
      radius: 22,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                color: online ? tokens.good : null,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Streaming node',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: checking ? null : () => onRefresh(silent: false),
                icon: checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Text(
            backendUri.host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (health != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _MiniChip(
                  icon: Icons.hub_rounded,
                  text: health!.websocketReady ? 'Realtime ready' : 'Realtime off',
                ),
                _MiniChip(
                  icon: Icons.live_tv_rounded,
                  text: health!.twitchReady ? 'Twitch ready' : 'Twitch pending',
                ),
                if (health!.region.isNotEmpty)
                  _MiniChip(
                    icon: Icons.public_rounded,
                    text: health!.region,
                  ),
              ],
            )
          else
            Text(
              error == null
                  ? 'Checking secure node…'
                  : 'Node unavailable. Local Twitch playback remains usable.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

final class _HelixCard extends StatefulWidget {
  const _HelixCard({required this.controller});

  final AppController controller;

  @override
  State<_HelixCard> createState() => _HelixCardState();
}

final class _HelixCardState extends State<_HelixCard> {
  bool _loading = false;
  String _message = 'Twitch Helix discovery is available from this section.';

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    final result = await widget.controller.searchDiscovery('');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _message = result.fold(
        success: (items) => items.isEmpty
            ? 'No followed channels are live.'
            : '${items.length} followed live channel${items.length == 1 ? '' : 's'} loaded.',
        failure: (failure) => failure.message,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 22,
      padding: const EdgeInsets.all(15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.radar_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Twitch Helix',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(_message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Refresh followed live channels',
          ),
        ],
      ),
    );
  }
}

final class _SavedStreamTile extends StatelessWidget {
  const _SavedStreamTile({
    required this.stream,
    required this.selected,
    required this.onTap,
    required this.onPlay,
  });

  final StreamRecord stream;
  final bool selected;
  final Future<void> Function() onTap;
  final Future<void> Function() onPlay;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        selected: selected,
        leading: CircleAvatar(
          child: Text(
            stream.displayName.isEmpty
                ? '?'
                : stream.displayName.characters.first.toUpperCase(),
          ),
        ),
        title: Text(
          stream.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${stream.quality} • ${stream.playbackMode == PlaybackMode.audioOnly ? 'audio' : 'video'} • ${stream.playCount} plays',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
        trailing: IconButton(
          onPressed: onPlay,
          icon: const Icon(Icons.play_arrow_rounded),
          tooltip: 'Play',
        ),
      ),
    );
  }
}

final class _EmptyStreamsCard extends StatelessWidget {
  const _EmptyStreamsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            const Icon(Icons.playlist_add_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Add a Twitch channel to start building the streaming workspace.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .55),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Text(text, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
