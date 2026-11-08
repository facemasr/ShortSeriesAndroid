import 'package:flutter/material.dart';

import 'yacine_ytv_link_presets.dart';

/// A local media URL editor inspired by the YTV Player's documented workflow,
/// not a copy of the third-party app's code, assets or proprietary decoder.
class YtvVideoEditorResult {
  const YtvVideoEditorResult(this.link, {this.useProvider = false});
  final YtvManualLink? link;
  final bool useProvider;
}

class YtvVideoUrlEditor {
  const YtvVideoUrlEditor._();

  static Future<YtvVideoEditorResult?> open(
    BuildContext context, {
    required bool ar,
    required String providerId,
    YtvManualLink? current,
  }) async {
    String label(String arabic, String english) => ar ? arabic : english;
    final url = TextEditingController(text: current?.url.toString() ?? '');
    final agent = TextEditingController(text: current?.userAgent ?? '');
    final referer = TextEditingController(text: current?.referer ?? '');
    String? error;
    try {
      return await showDialog<YtvVideoEditorResult>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (ctx, setLocalState) => AlertDialog(
            title: Text(label('EGY TV PRO · تحرير الرابط',
                'EGY TV PRO · Edit URL')),
            content: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label('شغّل رابط فيديو خاصًا بك. تُجلب روابط القنوات '
                      'تلقائيًا عند العودة إلى API.',
                    'Play a user-entered video link; switch back to API '
                      'for automatic TV channel resolution.')),
                const SizedBox(height: 12),
                TextField(controller: url, maxLines: 2,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: label('رابط الفيديو', 'Video URL'))),
                const SizedBox(height: 9),
                TextField(controller: agent, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'User-Agent')),
                const SizedBox(height: 9),
                TextField(controller: referer, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Referer')),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12)),
                ],
              ],
            )),
            actions: [
              TextButton(
                onPressed: () async {
                  await YtvManualLinkStore.remove(providerId);
                  if (dialog.mounted) Navigator.pop(dialog,
                      const YtvVideoEditorResult(null, useProvider: true));
                },
                child: Text(label('رابط القناة API', 'Use channel API')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(label('إلغاء', 'Cancel')),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    final link = YtvManualLink.parse(url.text,
                        userAgent: agent.text, referer: referer.text);
                    if (link.mayPersist) {
                      await YtvManualLinkStore.save(providerId, link);
                    } else {
                      // User-supplied signed links work in RAM only and
                      // never persist in local preferences.
                      await YtvManualLinkStore.remove(providerId);
                    }
                    if (dialog.mounted) Navigator.pop(dialog,
                        YtvVideoEditorResult(link));
                  } catch (_) {
                    setLocalState(() => error = label(
                      'رابط أو بيانات اتصال غير صالحة.',
                      'Invalid media URL or request headers.'));
                  }
                },
                child: Text(label('حفظ وتشغيل', 'Save and play')),
              ),
            ],
          ),
        ),
      );
    } finally {
      url.dispose();
      agent.dispose();
      referer.dispose();
    }
  }
}
