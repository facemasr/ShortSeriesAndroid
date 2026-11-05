/// Policy for quietly rotating the current live stream without resetting a
/// working player on every per-channel API refresh.
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
  if (activeUri == updatedUri &&
      activeHeaders != null &&
      activeHeaders.length == updatedHeaders.length &&
      updatedHeaders.entries.every((e) => activeHeaders[e.key] == e.value)) {
    return false;
  }
  if (!healthy) return true;
  final raw = activeUri.queryParameters['e'] ??
      activeUri.queryParameters['expires'] ?? activeUri.queryParameters['exp'];
  final parsed = int.tryParse(raw ?? '');
  final expiry = parsed != null && parsed >= 1700000000
      ? (parsed > 9999999999 ? parsed ~/ 1000 : parsed) : null;
  if (expiry != null) {
    return expiry <= now.millisecondsSinceEpoch ~/ 1000 + 120;
  }
  return activeSince != null &&
      now.difference(activeSince) >= const Duration(minutes: 3);
}
