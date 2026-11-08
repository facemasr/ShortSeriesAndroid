import 'package:flutter/material.dart';

import 'native_api.dart';
import 'yacine_channel_groups.dart';
import 'yacine_channel_resolver.dart';

/// Shared, native-style settings for VLC/Media3 with channel choice, aspect,
/// speed and track selection. No server-side playback or media scraping.
class YacinePlaybackSettings extends StatefulWidget {
  const YacinePlaybackSettings({
    super.key,
    required this.ar,
    required this.engineName,
    required this.fit,
    required this.speed,
    required this.sources,
    required this.sourceIndex,
    required this.onFit,
    required this.onSpeed,
    required this.onSource,
    this.onExternal,
    this.onVlcExternal,
    this.onYtvProExternal,
    this.onOtherEngine,
    required this.onReconnect,
    this.qualityVariants = const [],
    this.currentProviderId = '',
    this.onQualityVariant,
    this.audioTracks,
    this.subtitleTracks,
    this.onAudioTrack,
    this.onSubtitleTrack,
    this.onEditSource,
    this.onDiagnostics,
  });

  final bool ar;
  final String engineName;
  final BoxFit fit;
  final double speed;
  final List<YacinePlaybackSource> sources;
  final int sourceIndex;
  final ValueChanged<BoxFit> onFit;
  final ValueChanged<double> onSpeed;
  final ValueChanged<int> onSource;
  final VoidCallback? onExternal;
  final VoidCallback? onVlcExternal;
  final VoidCallback? onYtvProExternal;
  final VoidCallback? onOtherEngine;
  final VoidCallback onReconnect;
  final List<LiveChannel> qualityVariants;
  final String currentProviderId;
  final ValueChanged<LiveChannel>? onQualityVariant;
  final Future<Map<int, String>> Function()? audioTracks;
  final Future<Map<int, String>> Function()? subtitleTracks;
  final ValueChanged<int>? onAudioTrack;
  final ValueChanged<int>? onSubtitleTrack;
  final VoidCallback? onEditSource;
  final VoidCallback? onDiagnostics;

  @override
  State<YacinePlaybackSettings> createState() =>
      _YacinePlaybackSettingsState();
}

class _YacinePlaybackSettingsState extends State<YacinePlaybackSettings> {
  late BoxFit fit = widget.fit;
  late double speed = widget.speed;
  late int sourceIndex = widget.sourceIndex;
  Future<Map<int, String>>? audioFuture;
  Future<Map<int, String>>? subtitleFuture;

  String t(String ar, String en) => widget.ar ? ar : en;

  @override
  void initState() {
    super.initState();
    if (widget.audioTracks != null) audioFuture = widget.audioTracks!();
    if (widget.subtitleTracks != null) subtitleFuture = widget.subtitleTracks!();
  }

  void choose(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  Widget heading(String value) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 15, 12, 8),
    child: Text(value, style: const TextStyle(
        fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF34DBC9))),
  );

  Widget _tracks(Future<Map<int, String>>? future, ValueChanged<int>? onChoose,
      String label) {
    if (future == null || onChoose == null) return const SizedBox.shrink();
    return FutureBuilder<Map<int, String>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(minHeight: 2));
        }
        final tracks = snapshot.data ?? const <int, String>{};
        if (tracks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(t('لا توجد مسارات متاحة في البث الحالي.',
                'No tracks available in the current stream.'),
              style: const TextStyle(color: Colors.white54)));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading(label),
          for (final entry in tracks.entries)
            ListTile(
              dense: true,
              leading: const Icon(Icons.audiotrack_rounded),
              title: Text(entry.value),
              onTap: () => choose(() => onChoose(entry.key)),
            ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bounds = MediaQuery.sizeOf(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: bounds.height * .83),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 25),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 38, height: 4,
              margin: const EdgeInsets.only(bottom: 17),
              decoration: BoxDecoration(color: Colors.white38,
                  borderRadius: BorderRadius.circular(6)))),
            Row(children: [
              const Icon(Icons.tune_rounded, color: Color(0xFF34DBC9)),
              const SizedBox(width: 10),
              Expanded(child: Text(t('إعدادات المشغّل', 'Player settings'),
                style: const TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded)),
            ]),
            Text('EGY TV PRO · ' + widget.engineName,
              style: const TextStyle(color: Colors.white60)),
            if (widget.onEditSource != null) ...[
              heading(t('روابط الفيديو', 'Video links')),
              ListTile(
                tileColor: const Color(0xFF1B3038),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
                leading: const Icon(Icons.link_rounded,
                  color: Color(0xFF34DBC9)),
                title: Text(t('تشغيل أو تحرير رابط فيديو',
                  'Open or edit a video URL')),
                subtitle: Text(t('رابط الفيديو وUser-Agent وReferer',
                  'Video URL, User-Agent and Referer')),
                onTap: () => choose(widget.onEditSource!),
              ),
            ],
            if (widget.onDiagnostics != null)
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(t('تشخيص حالة تشغيل القناة',
                  'Channel playback diagnostics')),
                onTap: () => choose(widget.onDiagnostics!),
              ),
            heading(t('السيرفر / الجودة', 'Server / quality')),
            if (widget.sources.isEmpty)
              Padding(padding: const EdgeInsets.all(12),
                child: Text(t('سيظهر اختيار السيرفر بعد جلب الرابط.',
                    'Server choices appear after stream resolution.')))
            else
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (var i = 0; i < widget.sources.length; i++)
                  ChoiceChip(
                    label: Text(widget.sources[i].label),
                    selected: sourceIndex == i,
                    onSelected: (_) => choose(() => widget.onSource(i)),
                  ),
              ]),
            if (widget.onQualityVariant != null &&
                widget.qualityVariants.length > 1) ...[
              heading(t('جودة القناة', 'Channel resolution')),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final variant in widget.qualityVariants)
                  ChoiceChip(
                    label: Text(yacineChannelQuality(variant) == null
                      ? variant.title(widget.ar)
                      : yacineChannelQuality(variant).toString() + 'p'),
                    selected: variant.providerId == widget.currentProviderId,
                    onSelected: (_) =>
                        choose(() => widget.onQualityVariant!(variant)),
                  ),
              ]),
            ],
            heading(t('حجم الفيديو', 'Video fit')),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final mode in <BoxFit>[
                BoxFit.contain, BoxFit.cover, BoxFit.fill,
              ])
                ChoiceChip(
                  label: Text(mode == BoxFit.contain
                      ? t('الصورة كاملة', 'Fit')
                      : mode == BoxFit.cover
                          ? t('ملء الشاشة', 'Crop')
                          : t('تمديد', 'Stretch')),
                  selected: fit == mode,
                  onSelected: (_) {
                    setState(() => fit = mode);
                    widget.onFit(mode);
                  },
                ),
            ]),
            heading(t('سرعة التشغيل', 'Playback speed')),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final rate in <double>[0.75, 1.0, 1.25, 1.5, 2.0])
                ChoiceChip(
                  label: Text(rate.toString() + 'x'),
                  selected: speed == rate,
                  onSelected: (_) {
                    setState(() => speed = rate);
                    widget.onSpeed(rate);
                  },
                ),
            ]),
            _tracks(audioFuture, widget.onAudioTrack, t('الصوت', 'Audio tracks')),
            _tracks(subtitleFuture, widget.onSubtitleTrack,
                t('الترجمة', 'Subtitle tracks')),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF34DBC9)),
              title: Text(t('تحديث رابط القناة', 'Refresh channel link')),
              subtitle: Text(t('يطلب رابطًا مؤقتًا جديدًا من API',
                  'Request a fresh signed URL for the selected channel')),
              onTap: () => choose(widget.onReconnect),
            ),
            const Divider(),
            Text(t('مشغّل Media3 الداخلي واحد لجميع القنوات. تتجدد '
                'الروابط المؤقتة من المصدر المتاح دون التحويل إلى تطبيق آخر.',
                'One internal Media3 player for every channel. Temporary '
                'media URLs are refreshed without switching player apps.'),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
