import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks EGYSHOW's verified APK releases. Android installs updates only
/// after explicit user action and OS confirmation.
class EgyshowAppUpdates {
  static DateTime? _lastCheck;
  static bool _busy = false;
  static bool _dialogVisible = false;
  static const _interval = Duration(minutes: 15);
  static const _laterInterval = Duration(hours: 24);

  static void _message(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  static Future<void> check(
    BuildContext context, {
    required bool ar,
    bool manual = false,
  }) async {
    if (_busy || _dialogVisible) return;
    if (!manual && _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < _interval) return;
    _busy = true;
    try {
      final installed = await PackageInfo.fromPlatform();
      final installedCode = int.tryParse(installed.buildNumber) ?? 0;
      if (installedCode < 1) return;
      final feed = Uri.https('egyshow.com', '/api/v1/app/updates', {
        'platform': 'android',
        'version_code': installedCode.toString(),
      });
      final response = await http.get(feed, headers: {
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        if (manual) _message(context, ar ? 'تعذر التحقق من التحديثات' : 'Cannot check updates');
        return;
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic> || payload['ok'] != true) return;
      _lastCheck = DateTime.now();
      final newest = (payload['latest_code'] as num?)?.toInt() ?? 0;
      if (payload['update_available'] != true || newest <= installedCode) {
        if (manual) _message(context, ar ? 'التطبيق مُحدّث بالفعل' : 'App is up to date');
        return;
      }

      final packageName = payload['package_name']?.toString() ?? '';
      if (packageName.isNotEmpty && packageName != installed.packageName) return;
      final url = Uri.tryParse(payload['download_url']?.toString() ?? '');
      if (url == null || url.scheme != 'https' || url.host != 'egyshow.com' ||
          url.userInfo.isNotEmpty || url.hasFragment ||
          !RegExp(r'^/downloads/EGYSHOW-Android-v\d+\.\d+\.\d+\.apk$')
              .hasMatch(url.path)) return;
      final forced = payload['mandatory'] == true;
      final storage = await SharedPreferences.getInstance();
      final laterVersion = storage.getInt('egyshow.update.later.version') ?? 0;
      final laterAt = storage.getInt('egyshow.update.later.at') ?? 0;
      if (!manual && !forced && laterVersion == newest &&
          DateTime.now().millisecondsSinceEpoch - laterAt <
              _laterInterval.inMilliseconds) return;
      if (!context.mounted) return;
      _dialogVisible = true;
      try {
        final notes = payload['notes'];
        final releaseNotes = notes is Map ?
            (notes[ar ? 'ar' : 'en']?.toString() ?? '') : '';
        await showDialog<void>(
          context: context,
          barrierDismissible: !forced,
          builder: (dialogContext) => PopScope(
            canPop: !forced,
            child: AlertDialog(
              title: Text(ar ? 'تحديث جديد لتطبيق EGYSHOW' : 'EGYSHOW update available'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(ar
                    ? 'الإصدار ' + (payload['latest_version']?.toString() ?? '') + ' متاح الآن'
                    : 'Version ' + (payload['latest_version']?.toString() ?? '') + ' is available'),
                if (releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(releaseNotes),
                ],
                if (forced) ...[
                  const SizedBox(height: 10),
                  Text(ar ? 'يجب التحديث للمتابعة' : 'Update required to continue'),
                ],
              ]),
              actions: [
                if (!forced)
                  TextButton(
                    onPressed: () async {
                      await storage.setInt('egyshow.update.later.version', newest);
                      await storage.setInt('egyshow.update.later.at',
                          DateTime.now().millisecondsSinceEpoch);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: Text(ar ? 'لاحقًا' : 'Later'),
                  ),
                FilledButton.icon(
                  icon: const Icon(Icons.system_update_alt),
                  label: Text(ar ? 'تنزيل التحديث' : 'Download update'),
                  onPressed: () async {
                    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
                    if (!opened) {
                      if (dialogContext.mounted) {
                        _message(dialogContext, ar
                            ? 'تعذر فتح المتصفح لتحميل التحديث'
                            : 'Cannot open browser for update');
                      }
                      return;
                    }
                    if (!forced && dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                ),
              ],
            ),
          ),
        );
      } finally {
        _dialogVisible = false;
      }
    } catch (_) {
      if (manual) _message(context, ar ? 'تعذر الاتصال بخدمة التحديثات' : 'Update service unavailable');
    } finally {
      _busy = false;
    }
  }
}
