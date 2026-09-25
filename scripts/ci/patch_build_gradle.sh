#!/usr/bin/env bash
# Patches android/app/build.gradle(.kts) after `flutter create` bootstraps
# it fresh on every CI run (android/ is not committed to the repo — see
# build-android.yml's "Bootstrap Flutter project" step).
#
# Extracted from build-android.yml (was the "Patch build.gradle.kts" step)
# to keep the workflow file itself short — this script's own behavior is
# unchanged, only its location.
set -euo pipefail

FILE="android/app/build.gradle.kts"
[ ! -f "$FILE" ] && FILE="android/app/build.gradle"
echo "Patching $FILE"

# Replace full lines containing flutter.xxxSdkVersion or plain numbers
# compileSdk 37 (T103): flutter_secure_storage 11.x requires
# compileSdk >= 37 (its AAR metadata check fails the build
# otherwise). targetSdk stays at 36 — compileSdk (API surface
# available at compile time) and targetSdk (runtime behavior
# opt-in) are independent.
sed -i 's|^\s*compileSdk\s*=.*|    compileSdk = 37|' "$FILE"
sed -i 's|^\s*minSdk\s*=.*|        minSdk = 26|' "$FILE"
sed -i 's|^\s*targetSdk\s*=.*|        targetSdk = 36|' "$FILE"
sed -i 's|^\s*compileSdkVersion\s.*|    compileSdkVersion 37|' "$FILE"
sed -i 's|^\s*minSdkVersion\s.*|        minSdkVersion 26|' "$FILE"
sed -i 's|^\s*targetSdkVersion\s.*|        targetSdkVersion 36|' "$FILE"

# Add ndkVersion after compileSdk line
# Set ndkVersion - replace entire line or add after compileSdk
if grep -q 'ndkVersion' "$FILE"; then
  sed -i 's/ndkVersion = "[^"]*"/ndkVersion = "28.2.13676358"/' "$FILE"
else
  # Add ndkVersion
if grep -q ndkVersion "$FILE"; then
  sed -i 's|ndkVersion = ".*"|ndkVersion = "28.2.13676358"|' "$FILE"
else
  echo '        ndkVersion = "28.2.13676358"' >> "$FILE"
  sed -i '/compileSdk = 37/{n;s/.*/        ndkVersion = "28.2.13676358"/}' "$FILE"
fi
fi

# Add our dependencies at end of file
# T82: com.google.mediapipe:tasks-genai dropped — only used by the
# dead MediaPipePlugin.kt (mediapipe_service.dart, its Dart caller,
# was removed in T06). Gemini Nano uses com.google.mlkit:genai-prompt
# instead (GeminiNanoPlugin.kt), which stays.
if ! grep -q 'genai-prompt' "$FILE"; then
  cat >> "$FILE" << 'DEPS'

dependencies {
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta4")
    // #434: generates the schema for GeminiNanoPlugin's @Generable
    // classes (structured output), run through KSP (see below).
    ksp("com.google.mlkit:genai-schema-compiler:1.0.0-alpha1")
    implementation("com.google.guava:guava:32.1.3-android")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")
    implementation("com.google.android.gms:play-services-location:21.3.0")
}
DEPS
fi

# #434: ML Kit's structured output needs KSP >= 2.3.6 to generate the
# schema of the @Generable classes. Declared in settings.gradle.kts next
# to the Android/Kotlin plugins, then applied to the app module.
SETTINGS="android/settings.gradle.kts"
if [ -f "$SETTINGS" ] && ! grep -q 'com.google.devtools.ksp' "$SETTINGS"; then
  sed -i 's|^\(\s*\)id("com.android.application") version "\([^"]*\)" apply false|&\n\1id("com.google.devtools.ksp") version "2.3.6" apply false|' "$SETTINGS"
fi
if ! grep -q 'com.google.devtools.ksp' "$FILE"; then
  sed -i '0,/^\(\s*\)id("com.android.application")$/s||&\n\1id("com.google.devtools.ksp")|' "$FILE"
fi

# T118/T21: MediaSessionCompat/PlaybackStateCompat/MediaButtonReceiver
# for lock-screen/notification playback controls.
if ! grep -q 'androidx.media:media' "$FILE"; then
  cat >> "$FILE" << 'DEPS'

dependencies {
    implementation("androidx.media:media:1.7.0")
}
DEPS
fi

# T85: flutter_local_notifications requires core library desugaring.
if ! grep -q 'isCoreLibraryDesugaringEnabled' "$FILE"; then
  sed -i 's|compileOptions {|compileOptions {\n        isCoreLibraryDesugaringEnabled = true|' "$FILE"
fi
if ! grep -q 'coreLibraryDesugaring' "$FILE"; then
  cat >> "$FILE" << 'DEPS'

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
DEPS
fi

echo "=== Patched file ==="
cat "$FILE"
