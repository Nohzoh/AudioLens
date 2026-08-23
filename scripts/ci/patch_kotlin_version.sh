#!/usr/bin/env bash
# Pins the Kotlin Android plugin version across whichever Gradle settings
# file `flutter create` generated (Groovy or Kotlin DSL).
#
# T100: pinning 2.2.0 here still built with Kotlin 2.2.10 effectively
# (Gradle's default "highest version wins" conflict resolution —
# kotlinx-coroutines-android/play-services pulled in elsewhere likely
# pull in a newer Kotlin stdlib transitively than the plugin version we
# declare) — Flutter's own deprecation warning wants >= 2.2.20, so pin
# there directly instead of a version Gradle silently overrides anyway.
#
# Extracted from build-android.yml (was the "Patch Kotlin version" step)
# — behavior unchanged, only its location.
set -euo pipefail

for f in android/settings.gradle android/settings.gradle.kts android/build.gradle android/build.gradle.kts; do
  [ -f "$f" ] && sed -i 's/org.jetbrains.kotlin.android" version "[^"]*"/org.jetbrains.kotlin.android" version "2.2.20"/' "$f" && echo "Patched $f"
  [ -f "$f" ] && sed -i 's/id("org.jetbrains.kotlin.android") version "[^"]*"/id("org.jetbrains.kotlin.android") version "2.2.20"/' "$f"
done
