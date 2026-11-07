/// A source being present in the provider API is different from its decoder
/// being able to play it. This is a decoder fallback, NOT an access bypass.
///
/// Native Media3 is still the preferred engine; embedded libVLC is tried
/// only after Media3 has actually attempted a fetched source and failed.
bool yacineShouldUseDesktopVlc({
  required int sourceCount,
  required bool media3Attempted,
  required bool manualSource,
  required bool healthyPlayer,
}) {
  return sourceCount > 0 &&
      media3Attempted &&
      !manualSource &&
      !healthyPlayer;
}

/// EGY TV Sport on Windows opens beIN SPORTS through embedded libVLC.
/// Starting that decoder before Media3 avoids a second playback attempt,
/// without changing sources or bypassing the provider's authorization.
bool yacinePreferEmbeddedVlcForProvider({
  required String channelName,
  required String packageName,
  required int sourceCount,
  required bool manualSource,
  required bool alreadyPlaying,
}) {
  final name = channelName.trim().toLowerCase();
  final category = packageName.trim().toLowerCase();
  final isBeinSports = name.startsWith('bein sports') ||
      (name.startsWith('bein ') && category.startsWith('bein sports'));
  return isBeinSports && sourceCount > 0 &&
      !manualSource && !alreadyPlaying;
}
