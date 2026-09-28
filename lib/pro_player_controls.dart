part of 'main.dart';

class ProVideoControls extends StatefulWidget {
  final VideoState state;
  final String title;
  final String subtitle;
  final bool hasSources;
  final bool hasSubtitles;
  final bool hasEpisodes;
  final bool hasPrevious;
  final bool hasNext;
  final bool refreshingSource;
  final VoidCallback onSources;
  final VoidCallback onSubtitles;
  final VoidCallback onSpeed;
  final VoidCallback onEpisodes;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRefreshSource;

  const ProVideoControls({
    super.key,
    required this.state,
    required this.title,
    required this.subtitle,
    required this.hasSources,
    required this.hasSubtitles,
    required this.hasEpisodes,
    required this.hasPrevious,
    required this.hasNext,
    required this.refreshingSource,
    required this.onSources,
    required this.onSubtitles,
    required this.onSpeed,
    required this.onEpisodes,
    required this.onPrevious,
    required this.onNext,
    required this.onRefreshSource,
  });

  @override
  State<ProVideoControls> createState() => _ProVideoControlsState();
}

class _ProVideoControlsState extends State<ProVideoControls> {
  late final Player player;
  StreamSubscription<bool>? playingSub;
  StreamSubscription<bool>? bufferingSub;
  StreamSubscription<Duration>? positionSub;
  StreamSubscription<Duration>? durationSub;

  bool visible = true;
  bool playing = false;
  bool buffering = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Timer? hideTimer;

  @override
  void initState() {
    super.initState();
    player = widget.state.widget.controller.player;
    playing = player.state.playing;
    buffering = player.state.buffering;
    position = player.state.position;
    duration = player.state.duration;

    playingSub = player.stream.playing.listen((v) {
      if (mounted) setState(() => playing = v);
      _scheduleHide();
    });
    bufferingSub = player.stream.buffering.listen((v) {
      if (mounted) setState(() => buffering = v);
    });
    positionSub = player.stream.position.listen((v) {
      if (mounted) setState(() => position = v);
    });
    durationSub = player.stream.duration.listen((v) {
      if (mounted) setState(() => duration = v);
    });
    _scheduleHide();
  }

  void _scheduleHide() {
    hideTimer?.cancel();
    if (!playing) return;
    hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => visible = false);
    });
  }

  void _showControls() {
    setState(() => visible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    setState(() => visible = !visible);
    if (visible) _scheduleHide();
  }

  Future<void> _seekBy(int seconds) async {
    final target = position + Duration(seconds: seconds);
    final max = duration;
    final safe = target < Duration.zero
        ? Duration.zero
        : (max > Duration.zero && target > max ? max : target);
    await player.seek(safe);
    _showControls();
  }

  Future<void> _seekTo(double milliseconds) async {
    await player.seek(Duration(milliseconds: milliseconds.round()));
    _showControls();
  }

  String _time(Duration value) {
    final total = value.inSeconds < 0 ? 0 : value.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    hideTimer?.cancel();
    playingSub?.cancel();
    bufferingSub?.cancel();
    positionSub?.cancel();
    durationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds.toDouble();
    final posMs = position.inMilliseconds.clamp(
      0,
      duration.inMilliseconds > 0 ? duration.inMilliseconds : 0,
    ).toDouble();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () => _seekBy(-10),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () => _seekBy(10),
                  ),
                ),
              ],
            ),
          ),
          AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !visible,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xB8000000),
                          Color(0x22000000),
                          Color(0xCC000000),
                        ],
                        stops: [0, .48, 1],
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    start: 10,
                    end: 10,
                    top: 8,
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (widget.subtitle.isNotEmpty)
                                  Text(
                                    widget.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10.5,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.hasEpisodes)
                            _ControlIcon(
                              tooltip: Api.I.ar ? 'الحلقات' : 'Episodes',
                              icon: Icons.format_list_numbered_rounded,
                              onTap: widget.onEpisodes,
                            ),
                          if (widget.hasSources)
                            _ControlIcon(
                              tooltip: Api.I.ar ? 'السيرفرات' : 'Servers',
                              icon: Icons.dns_outlined,
                              onTap: widget.onSources,
                            ),
                          if (widget.hasSubtitles)
                            _ControlIcon(
                              tooltip: Api.I.ar ? 'الترجمة' : 'Subtitles',
                              icon: Icons.subtitles_rounded,
                              onTap: widget.onSubtitles,
                            ),
                          _ControlIcon(
                            tooltip: Api.I.ar ? 'السرعة' : 'Speed',
                            icon: Icons.speed_rounded,
                            onTap: widget.onSpeed,
                          ),
                          _ControlIcon(
                            tooltip: Api.I.ar ? 'تحديث المصدر' : 'Refresh source',
                            icon: widget.refreshingSource
                                ? Icons.sync_rounded
                                : Icons.refresh_rounded,
                            onTap: widget.refreshingSource
                                ? () {}
                                : widget.onRefreshSource,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.hasPrevious)
                          _RoundControl(
                            icon: Icons.skip_previous_rounded,
                            onTap: widget.onPrevious,
                            size: 46,
                          ),
                        _RoundControl(
                          icon: Icons.replay_10_rounded,
                          onTap: () => _seekBy(-10),
                          size: 48,
                        ),
                        const SizedBox(width: 8),
                        _RoundControl(
                          icon: playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          onTap: () async {
                            await player.playOrPause();
                            _showControls();
                          },
                          size: 66,
                          strong: true,
                        ),
                        const SizedBox(width: 8),
                        _RoundControl(
                          icon: Icons.forward_10_rounded,
                          onTap: () => _seekBy(10),
                          size: 48,
                        ),
                        if (widget.hasNext)
                          _RoundControl(
                            icon: Icons.skip_next_rounded,
                            onTap: widget.onNext,
                            size: 46,
                          ),
                      ],
                    ),
                  ),
                  PositionedDirectional(
                    start: 10,
                    end: 10,
                    bottom: 5,
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                            ),
                            child: Slider(
                              value: totalMs > 0 ? posMs.clamp(0, totalMs).toDouble() : 0.0,
                              max: totalMs > 0 ? totalMs : 1,
                              onChangeStart: (_) {
                                hideTimer?.cancel();
                                setState(() => visible = true);
                              },
                              onChanged: (v) {
                                setState(() {
                                  position = Duration(milliseconds: v.round());
                                });
                              },
                              onChangeEnd: _seekTo,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '${_time(position)} / ${_time(duration)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              if (buffering)
                                const Padding(
                                  padding: EdgeInsetsDirectional.only(end: 8),
                                  child: SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              _ControlIcon(
                                tooltip: Api.I.ar ? 'ملء الشاشة' : 'Fullscreen',
                                icon: isFullscreen(context)
                                    ? Icons.fullscreen_exit_rounded
                                    : Icons.fullscreen_rounded,
                                onTap: () => toggleFullscreen(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!visible && !playing)
            Center(
              child: _RoundControl(
                icon: Icons.play_arrow_rounded,
                onTap: () async {
                  await player.play();
                  _showControls();
                },
                size: 62,
                strong: true,
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _ControlIcon({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 22),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool strong;

  const _RoundControl({
    required this.icon,
    required this.onTap,
    required this.size,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: strong ? const Color(0xE6FFFFFF) : const Color(0x99000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: strong ? size * .54 : size * .48,
              color: strong ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
