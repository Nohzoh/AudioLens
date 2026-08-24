#!/usr/bin/env bash
# Patches android/app/src/main/AndroidManifest.xml after `flutter create`
# bootstraps it fresh on every CI run (android/ is not committed).
#
# Extracted from build-android.yml (was the "Patch AndroidManifest" step)
# — behavior unchanged, only its location.
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"

if ! grep -q 'ACCESS_FINE_LOCATION' "$MANIFEST"; then
  sed -i 's/<application/<uses-permission android:name="android.permission.CAMERA"\/>\n    <uses-permission android:name="android.permission.INTERNET"\/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"\/>\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"\/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"\/>\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"\/>\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"\/>\n    <uses-feature android:name="android.hardware.camera" android:required="false"\/>\n    <application/' "$MANIFEST"
fi
sed -i 's/android:label="[^"]*"/android:label="AudioLens"/' "$MANIFEST"
# allowBackup=false (T80): history contains GPS coordinates and
# photos — Android's default is allowBackup=true, which would let
# adb backup extract it on an unlocked device with USB debugging.
# Guarded (T82 fix): re-running this against an already-patched
# manifest (e.g. a local build not starting from a fresh bootstrap)
# duplicated the attribute and broke manifest merging.
if ! grep -q 'allowBackup' "$MANIFEST"; then
  sed -i 's/android:label="AudioLens"/android:label="AudioLens" android:allowBackup="false"/' "$MANIFEST"
fi
# T89: Android 11+ (targetSdk 30+) hides other apps/services from
# package queries by default — without this <queries> entry,
# flutter_tts's isLanguageAvailable()/speak() can silently fail
# to find the system TTS engine on some devices.
if ! grep -q 'TextToSpeechService' "$MANIFEST"; then
  sed -i 's|</manifest>|<queries><intent><action android:name="android.speech.tts.engine.TextToSpeechService" /></intent></queries>\n</manifest>|' "$MANIFEST"
fi
# T85: a foreground service protects the app process's priority
# while an analysis is in flight — without it, Android can kill
# the process while backgrounded, silently dropping the analysis.
if ! grep -q 'FOREGROUND_SERVICE_DATA_SYNC' "$MANIFEST"; then
  sed -i 's|<application|<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application|' "$MANIFEST"
fi
if ! grep -q 'AnalysisForegroundService' "$MANIFEST"; then
  sed -i 's|</application>|    <service android:name=".AnalysisForegroundService" android:foregroundServiceType="dataSync" android:exported="false"/>\n    </application>|' "$MANIFEST"
fi
# T118/T21: a second, separate foreground service for lock-screen/
# notification playback controls (MediaSession) — different
# foreground service type from the analysis one above, Android
# 14+ enforces these strictly per declared type.
if ! grep -q 'FOREGROUND_SERVICE_MEDIA_PLAYBACK' "$MANIFEST"; then
  sed -i 's|<application|<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>\n    <application|' "$MANIFEST"
fi
if ! grep -q 'PlaybackForegroundService' "$MANIFEST"; then
  sed -i 's|</application>|    <service android:name=".PlaybackForegroundService" android:foregroundServiceType="mediaPlayback" android:exported="false"/>\n    </application>|' "$MANIFEST"
fi
# T97: register as a share target for photos from other apps
# (Gallery, etc.) — a second intent-filter on the same activity,
# right after the existing MAIN/LAUNCHER one.
#
# Must run before the QuickCaptureWidgetProvider <receiver> block
# below (#165): the sed pattern below matches any line containing
# `</intent-filter>`, and once the widget receiver — which has its
# own `<intent-filter>...</intent-filter>` for APPWIDGET_UPDATE — is
# in the file, that line matches too, silently duplicating the SEND
# intent-filter inside the widget's <receiver> instead of only the
# activity's. Running this step first means the widget's
# intent-filter doesn't exist yet, so there's only one line to match.
if ! grep -q 'android.intent.action.SEND' "$MANIFEST"; then
  sed -i 's|</intent-filter>|</intent-filter>\n            <intent-filter>\n                <action android:name="android.intent.action.SEND"/>\n                <category android:name="android.intent.category.DEFAULT"/>\n                <data android:mimeType="image/*"/>\n            </intent-filter>|' "$MANIFEST"
fi
# Home-screen quick-capture widget (new feature): jumps
# straight to the camera on tap, see QuickCaptureWidgetProvider.kt.
if ! grep -q 'QuickCaptureWidgetProvider' "$MANIFEST"; then
  sed -i 's|</application>|    <receiver android:name=".QuickCaptureWidgetProvider" android:exported="false"><intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter><meta-data android:name="android.appwidget.provider" android:resource="@xml/quick_capture_widget_info"/></receiver>\n    </application>|' "$MANIFEST"
fi
echo "Manifest patched (allowBackup=false, TTS engine query, foreground service, share target)"
