import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android Media3 plays authenticated-by-headers HLS fixture',
      (tester) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('http://10.0.2.2:8765/control.m3u8'),
      httpHeaders: const {
        'User-Agent': 'EGYSHOW-Android-Control/1.0',
        'Referer': 'https://provider.example/player',
      },
      formatHint: VideoFormat.hls,
    );
    try {
      await tester.runAsync(() async {
        await controller.initialize().timeout(const Duration(seconds: 30));
        await controller.play();
        final limit = DateTime.now().add(const Duration(seconds: 12));
        while (!controller.value.isPlaying &&
            DateTime.now().isBefore(limit)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      });
      expect(controller.value.isInitialized, isTrue,
          reason: 'Native Android video plugin could not open HLS manifest');
      expect(controller.value.isPlaying, isTrue,
          reason: 'Native Android player could not begin HLS playback');
      print('EGYSHOW_NATIVE_HLS_OK');
    } finally {
      await controller.dispose();
    }
  });
}
