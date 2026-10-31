#!/usr/bin/env bash
set -euo pipefail

APK="egytube-v050/app/build/outputs/apk/debug/app-debug.apk"
PKG="com.egytube.official.audio90"
CRASH_LOG="/tmp/egytube-crash.log"
test -s "$APK"
adb install -r "$APK"
adb logcat -c
echo "START: EGYTUBE activity"
adb shell am start -W -n "$PKG/com.egytube.rebuilt.MainActivity"
sleep 5
adb shell pidof "$PKG"
echo "START: Media3 session service (regression for missing CustomAction display name)"
adb shell am startservice -n "$PKG/com.egytube.rebuilt.PlaybackService"
sleep 5
adb shell pidof "$PKG"
adb logcat -d -b crash > "$CRASH_LOG"
if grep -E 'FATAL EXCEPTION|You must specify a name to build a CustomAction|Unable to create service' "$CRASH_LOG"; then
  cat "$CRASH_LOG"
  exit 1
fi
echo "PASS: activity and Media3 service remained alive without fatal exceptions."
