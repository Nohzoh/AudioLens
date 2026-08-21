#!/usr/bin/env bash
#
# Build local de l'APK AudioLens (debug) — reproduit .github/workflows/build-android.yml
# Usage : bash scripts/build_android_local.sh
#
# Prérequis (1 seule fois, voir README de build) :
#   brew install --cask temurin@17
#   brew install --cask android-commandlinetools
#   brew install gnu-sed
#
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Vérification des prérequis"

command -v flutter >/dev/null 2>&1 || { echo "❌ flutter introuvable (brew install --cask flutter)"; exit 1; }
command -v java >/dev/null 2>&1 || { echo "❌ java introuvable (brew install --cask temurin@17)"; exit 1; }
# macOS ships BSD sed, dont -i et les commandes multi-lignes (a\, \n dans le
# remplacement) ont une syntaxe incompatible avec le GNU sed utilisé par la
# CI (ubuntu-latest) — sans ça, chaque `$SED -i` ci-dessous échoue ou patche
# le mauvais fichier silencieusement.
command -v gsed >/dev/null 2>&1 || { echo "❌ gsed introuvable (brew install gnu-sed) — requis pour un comportement identique à la CI"; exit 1; }
SED="gsed"

JAVA_MAJOR="$(java -version 2>&1 | awk -F'"' '/version/ {print $2}' | cut -d. -f1)"
echo "   Java $(java -version 2>&1 | head -1)"
[ "$JAVA_MAJOR" -ge 17 ] || { echo "❌ Java doit être >= 17 (installe Temurin 17)"; exit 1; }

# JAVA_HOME pour Gradle
if [ -z "${JAVA_HOME:-}" ] && [ -x /usr/libexec/java_home ]; then
  export JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
  [ -n "$JAVA_HOME" ] && echo "   JAVA_HOME=$JAVA_HOME"
fi

# ANDROID_HOME + sdkmanager
if [ -z "${ANDROID_HOME:-}" ]; then
  for cand in /opt/homebrew/share/android-commandlinetools /usr/local/share/android-commandlinetools "$HOME/Library/Android/sdk"; do
    [ -d "$cand" ] && export ANDROID_HOME="$cand" && break
  done
fi
[ -n "${ANDROID_HOME:-}" ] || { echo "❌ ANDROID_HOME introuvable (brew install --cask android-commandlinetools)"; exit 1; }
echo "   ANDROID_HOME=$ANDROID_HOME"

SDKMANAGER="$(ls "$ANDROID_HOME"/cmdline-tools/*/bin/sdkmanager 2>/dev/null | head -1 || true)"
[ -n "$SDKMANAGER" ] || { echo "❌ sdkmanager introuvable dans $ANDROID_HOME/cmdline-tools"; exit 1; }
echo "   sdkmanager: $SDKMANAGER"

echo "==> Installation des composants SDK (idempotent, peut être long)"
"$SDKMANAGER" --install "platform-tools" "platforms;android-37.0" "build-tools;37.0.0" "ndk;28.2.13676358"
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true

echo "==> Bootstrap Android (flutter create)"
flutter create --project-name audiolens --org io.nohzoh --platforms android . 2>&1 | tail -3 || true

echo "==> Patch build.gradle.kts (SDK / NDK / dépendances natives)"
FILE="android/app/build.gradle.kts"
[ -f "$FILE" ] || FILE="android/app/build.gradle"

# compileSdk 37 (T103): flutter_secure_storage 11.x requires compileSdk
# >= 37 (its AAR metadata check fails the build otherwise). targetSdk
# stays at 36 — compileSdk (API surface available at compile time) and
# targetSdk (runtime behavior opt-in) are independent.
$SED -i 's|^\s*compileSdk\s*=.*|    compileSdk = 37|' "$FILE"
$SED -i 's|^\s*minSdk\s*=.*|        minSdk = 26|' "$FILE"
$SED -i 's|^\s*targetSdk\s*=.*|        targetSdk = 36|' "$FILE"
$SED -i 's|^\s*compileSdkVersion\s.*|    compileSdkVersion 37|' "$FILE"
$SED -i 's|^\s*minSdkVersion\s.*|        minSdkVersion 26|' "$FILE"
$SED -i 's|^\s*targetSdkVersion\s.*|        targetSdkVersion 36|' "$FILE"

if grep -q 'ndkVersion' "$FILE"; then
  $SED -i 's|ndkVersion = "[^"]*"|ndkVersion = "28.2.13676358"|; s|ndkVersion = flutter.ndkVersion|ndkVersion = "28.2.13676358"|' "$FILE"
else
  $SED -i '/compileSdk = 37/a\        ndkVersion = "28.2.13676358"' "$FILE"
fi

# T82: com.google.mediapipe:tasks-genai dropped — only used by the dead
# MediaPipePlugin.kt. Gemini Nano uses com.google.mlkit:genai-prompt instead.
if ! grep -q 'genai-prompt' "$FILE"; then
  cat >> "$FILE" << 'DEPS'

dependencies {
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta1")
    implementation("com.google.guava:guava:32.1.3-android")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")
    implementation("com.google.android.gms:play-services-location:21.3.0")
}
DEPS
fi

# T118/T21: MediaSessionCompat/PlaybackStateCompat/MediaButtonReceiver for
# lock-screen/notification playback controls.
if ! grep -q 'androidx.media:media' "$FILE"; then
  cat >> "$FILE" << 'DEPS'

dependencies {
    implementation("androidx.media:media:1.7.0")
}
DEPS
fi

# T85: flutter_local_notifications requires core library desugaring.
if ! grep -q 'isCoreLibraryDesugaringEnabled' "$FILE"; then
  $SED -i 's|compileOptions {|compileOptions {\n        isCoreLibraryDesugaringEnabled = true|' "$FILE"
fi
if ! grep -q 'coreLibraryDesugaring' "$FILE"; then
  cat >> "$FILE" << 'DEPS'

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
DEPS
fi

echo "==> Patch version Kotlin (2.2.20)"
for f in android/settings.gradle android/settings.gradle.kts android/build.gradle android/build.gradle.kts; do
  [ -f "$f" ] && $SED -i 's/org.jetbrains.kotlin.android" version "[^"]*"/org.jetbrains.kotlin.android" version "2.2.20"/' "$f"
  [ -f "$f" ] && $SED -i 's/id("org.jetbrains.kotlin.android") version "[^"]*"/id("org.jetbrains.kotlin.android") version "2.2.20"/' "$f"
done

echo "==> Patch AndroidManifest.xml (permissions + label + FileProvider)"
MANIFEST="android/app/src/main/AndroidManifest.xml"
if ! grep -q 'ACCESS_FINE_LOCATION' "$MANIFEST"; then
  $SED -i 's|<application|<uses-permission android:name="android.permission.CAMERA"/>\n    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>\n    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application|' "$MANIFEST"
fi
$SED -i 's/android:label="[^"]*"/android:label="AudioLens"/' "$MANIFEST"
# Guarded (T82 fix): re-running against an already-patched manifest (no
# fresh bootstrap) duplicated this attribute and broke manifest merging.
if ! grep -q 'allowBackup' "$MANIFEST"; then
  $SED -i 's/android:label="AudioLens"/android:label="AudioLens" android:allowBackup="false"/' "$MANIFEST"
fi
# T89: Android 11+ (targetSdk 30+) hides other apps/services from package
# queries by default — without this <queries> entry, flutter_tts's
# isLanguageAvailable()/speak() can silently fail to find the system TTS
# engine on some devices.
if ! grep -q 'TextToSpeechService' "$MANIFEST"; then
  $SED -i 's|</manifest>|<queries><intent><action android:name="android.speech.tts.engine.TextToSpeechService" /></intent></queries>\n</manifest>|' "$MANIFEST"
fi
# T85: a foreground service protects the app process's priority while an
# analysis is in flight — without it, Android can kill the process while
# backgrounded, silently dropping the analysis.
if ! grep -q 'FOREGROUND_SERVICE_DATA_SYNC' "$MANIFEST"; then
  $SED -i 's|<application|<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application|' "$MANIFEST"
fi
if ! grep -q 'AnalysisForegroundService' "$MANIFEST"; then
  $SED -i 's|</application>|    <service android:name=".AnalysisForegroundService" android:foregroundServiceType="dataSync" android:exported="false"/>\n    </application>|' "$MANIFEST"
fi
# T118/T21: a second, separate foreground service for lock-screen/
# notification playback controls (MediaSession) — different foreground
# service type from the analysis one above, Android 14+ enforces these
# strictly per declared type.
if ! grep -q 'FOREGROUND_SERVICE_MEDIA_PLAYBACK' "$MANIFEST"; then
  $SED -i 's|<application|<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>\n    <application|' "$MANIFEST"
fi
if ! grep -q 'PlaybackForegroundService' "$MANIFEST"; then
  $SED -i 's|</application>|    <service android:name=".PlaybackForegroundService" android:foregroundServiceType="mediaPlayback" android:exported="false"/>\n    </application>|' "$MANIFEST"
fi
# T97: register as a share target for photos from other apps.
if ! grep -q 'android.intent.action.SEND' "$MANIFEST"; then
  $SED -i 's|</intent-filter>|</intent-filter>\n            <intent-filter>\n                <action android:name="android.intent.action.SEND"/>\n                <category android:name="android.intent.category.DEFAULT"/>\n                <data android:mimeType="image/*"/>\n            </intent-filter>|' "$MANIFEST"
fi
if ! grep -q 'FileProvider' "$MANIFEST"; then
  $SED -i 's|</application>|    <provider android:name="androidx.core.content.FileProvider" android:authorities="${applicationId}.fileprovider" android:exported="false" android:grantUriPermissions="true"><meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/file_paths"/></provider>\n    </application>|' "$MANIFEST"
fi
mkdir -p android/app/src/main/res/xml
cat > android/app/src/main/res/xml/file_paths.xml << 'XML'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <external-path name="external_files" path="."/>
    <cache-path name="cache" path="."/>
</paths>
XML

echo "==> flutter pub get"
flutter pub get

echo "==> Build APK (debug)"
BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
flutter build apk --debug --dart-define=BUILD_DATE="$BUILD_DATE"

APK="build/app/outputs/flutter-apk/app-debug.apk"
echo ""
echo "✅ APK prêt : $APK"
echo "   Taille : $(du -h "$APK" | cut -f1)"
echo ""
echo "Installation sur téléphone (USB debugging activé) :"
echo "   $ANDROID_HOME/platform-tools/adb install -r $APK"
