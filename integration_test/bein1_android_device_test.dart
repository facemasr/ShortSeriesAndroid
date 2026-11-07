import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:http/http.dart' as http;
import 'package:egyshow_mobile/native_api.dart';
import 'package:egyshow_mobile/yacine_channel_resolver.dart';
import 'package:egyshow_mobile/yacine_stream_diagnostics.dart';
import 'package:egyshow_mobile/yacine_vlc_options.dart';
import 'package:egyshow_mobile/yacine_vlc_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android native VLC decodes a local control clip', (tester) async {
    final controller = VlcPlayerController.network(
      'http://10.0.2.2:8765/egyshow_control.mp4',
      hwAcc: HwAcc.auto, autoPlay: true,
      options: yacineVlcOptions(const <String, String>{}),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: VlcPlayer(
        controller: controller, aspectRatio: 16 / 9,
        placeholder: const CircularProgressIndicator(),
      ))),
    ));
    await tester.runAsync(() async {
      final until = DateTime.now().add(const Duration(seconds: 28));
      while (!controller.value.isPlaying &&
          !controller.value.hasError && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    });
    await tester.pump();
    print('CONTROL_VLC playing=' + controller.value.isPlaying.toString() +
      ' initialized=' + controller.value.isInitialized.toString() +
      ' hasError=' + controller.value.hasError.toString());
    expect(controller.value.isPlaying, isTrue,
      reason: 'Native Android VLC must play a known-accessible local control video');
    await tester.pumpWidget(const SizedBox());
    await controller.dispose();
  });

  testWidgets('beIN SPORTS 1 ID 1424 real Android API/source diagnostics', (tester) async {
    final client = http.Client();
    List<YacinePlaybackSource> sources = <YacinePlaybackSource>[];
    YacineManifestDiagnostic? manifest;
    try {
      await tester.runAsync(() async {
        try {
          sources = await YacineChannelResolver(client).resolve('1424');
          if (sources.isNotEmpty) {
            manifest = await checkYacineManifest(client, sources.first);
          }
          print('BEIN1_ANDROID_API sourceCount=' + sources.length.toString() +
            ' hasProviderUserAgent=' +
              (sources.isNotEmpty && sources.first.headers.containsKey('User-Agent')).toString() +
            ' hasProviderReferer=' +
              (sources.isNotEmpty && sources.first.headers.containsKey('Referer')).toString() +
            ' streamHttp=' + (manifest?.httpStatus.toString() ?? 'none') +
            ' reason=' + (manifest?.reason ?? 'none'));
        } catch (error) {
          // Provider-side authentication/region errors are external facts.
          print('BEIN1_ANDROID_API unavailable=' + error.runtimeType.toString());
        }
      });
      final api = EgyApi();
      try {
        await tester.pumpWidget(MaterialApp(
          home: YacineVlcChannelPlayer(
            channel: LiveChannel(<String, dynamic>{
              'id': 1424, 'provider_id': '1424',
              'name_en': 'beIN SPORTS 1', 'name_ar': 'beIN SPORTS 1',
              'package_name': 'beIN SPORTS (1080P)',
            }), api: api, ar: false,
          ),
        ));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(seconds: 21));
        });
        await tester.pump();
        expect(find.byType(YacineVlcChannelPlayer), findsOneWidget);
        print('BEIN1_ANDROID_PLAYER screenAlive=true sourceDenied=' +
          (manifest?.denied ?? false).toString());
        await tester.pumpWidget(const SizedBox());
      } finally {
        api.dispose();
      }
    } finally {
      client.close();
    }
  });
}
