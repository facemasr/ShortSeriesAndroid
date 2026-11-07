/// Rotate a live input only when it has failed or its CURRENT signed URL
/// approaches expiry. Routine provider metadata refresh must not interrupt
/// a healthy native ExoPlayer, including when URL/header text changes.
bool yacineHotSwapNeeded({
  required Uri? activeUri,
  required Map<String, String>? activeHeaders,
  required Uri updatedUri,
  required Map<String, String> updatedHeaders,
  required DateTime? activeSince,
  required DateTime now,
  required bool healthy,
}) {
  if (activeUri == null) return true;
  if (!healthy) return true;
  if (activeUri == updatedUri &&
      activeHeaders != null &&
      activeHeaders.length == updatedHeaders.length &&
      updatedHeaders.entries.every((e) => activeHeaders[e.key] == e.value)) {
    return false;
  }
  final raw = activeUri.queryParameters['e'] ??
      activeUri.queryParameters['expires'] ?? activeUri.queryParameters['exp'];
  final parsed = int.tryParse(raw ?? '');
  final expiry = parsed != null && parsed >= 1700000000
      ? (parsed > 9999999999 ? parsed ~/ 1000 : parsed) : null;
  if (expiry != null) {
    return expiry <= now.millisecondsSinceEpoch ~/ 1000 + 120;
  }
  // Unspecified expiry: keep the healthy stream. The player error/watchdog
  // path performs recovery when the origin actually stops sending media.
  return false;
}
