---
name: verify-on-device
description: Boot the Android emulator, build and install a debug APK, optionally seed test data via SQLite, and screenshot/interact with the running app to verify a UI change end-to-end. Use before shipping a real, user-visible UI change when widget tests alone aren't enough proof — e.g. a new interactive element (menu, dialog, gesture) or a visual change (layout, color, spacing) that needs to be seen rendered for real, not just asserted on in a test tree.
---

# Verify a change on a real device (emulator)

This is the on-device verification pass referenced throughout
`AGENTS.md`'s ship discipline — use it when `flutter analyze` +
`flutter test` passing isn't itself proof the UI actually looks/works
right. Skip it for purely structural refactors with no visual change
(existing test coverage is enough there) or non-UI changes.

## 1. Boot the emulator

```
emulator -list-avds
nohup emulator -avd <avd-name> -no-snapshot-save > /tmp/emulator.log 2>&1 &
disown
```

Wait for a device to attach, then for boot to actually finish (a device
appearing in `adb devices` does not mean the OS finished booting):

```
adb wait-for-device shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 2; done; echo BOOTED'
```

If `emulator`/`adb` aren't on `PATH`, they're typically under
`$ANDROID_HOME/emulator` and `$ANDROID_HOME/platform-tools` — check
`/opt/homebrew/share/android-commandlinetools` first on this machine.

## 2. Build and install

```
bash scripts/build_android_local.sh
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

**If install fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`** (a prior
build on this emulator was signed with a different key — common after
switching branches or a long-lived AVD): uninstall the stale package
first, then retry:

```
adb uninstall io.nohzoh.audiolens
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## 3. Launch

```
adb shell am start -n io.nohzoh.audiolens/.MainActivity
```

`monkey -c android.intent.category.LAUNCHER` is less reliable here (can
report success without actually starting the activity) — prefer `am
start` with the explicit component.

## 4. Seed test data, if the screen you're verifying needs it

No configured AI provider exists on a fresh emulator, so seed a
`HistoryEntry` directly via SQLite rather than running a real analysis.
Push a placeholder image first (a real decodable file — `Image.file()`
in the app actually decodes it):

```
python3 -c "from PIL import Image; Image.new('RGB', (800, 600), color=(120, 90, 200)).save('/tmp/seed_photo.jpg', quality=85)"
cat /tmp/seed_photo.jpg | adb shell "run-as io.nohzoh.audiolens sh -c 'cat > files/seed_photo.jpg'"
adb shell run-as io.nohzoh.audiolens sh -c 'pwd'   # e.g. /data/user/0/io.nohzoh.audiolens
```

Then insert the row — **pipe the SQL via stdin**, not as a shell
argument to `sqlite3` through `adb shell`; passing it inline breaks on
quoting every time:

```
cat <<'SQL' | adb shell "run-as io.nohzoh.audiolens sh -c 'sqlite3 databases/audio_guide_history.db'"
INSERT INTO history (imagePath, title, script, locationName, status, aiModel, ttsModel, gpsLatitude, gpsLongitude, gpsAddress, createdAt, analyzedAt)
VALUES ('/data/user/0/io.nohzoh.audiolens/files/seed_photo.jpg', 'Title', 'Script text.', 'City', 'complete', 'gemini-3.5-flash', 'gemini-tts', 48.85, 2.35, 'City, France', '2026-01-01T12:00:00.000', '2026-01-01T12:00:05.000');
SQL
```

Check the schema first if inserting into a table whose columns you
haven't confirmed recently: `echo ".schema history" | adb shell
"run-as io.nohzoh.audiolens sh -c 'sqlite3 databases/audio_guide_history.db'"`.

**Then force-restart the app** — it caches `HistoryService`'s list in
memory at startup, so a row inserted while the app is already running
stays invisible until the process restarts and re-reads the DB fresh:

```
adb shell am force-stop io.nohzoh.audiolens
adb shell am start -n io.nohzoh.audiolens/.MainActivity
```

## 5. Interact and screenshot

```
adb shell input tap <x> <y>
adb exec-out screencap -p > /tmp/screen.png
```

Read the PNG with the Read tool to actually look at it — don't infer
correctness from the command succeeding.

## 6. Clean up

- If you seeded data, delete it: pipe a `DELETE FROM history WHERE
  id=<n>;` the same way as the insert above.
- `scripts/build_android_local.sh` regenerates the gitignored `android/`
  scaffold and touches a few tracked files as a side effect — restore
  those before finishing, per `AGENTS.md`:
  ```
  git checkout -- .metadata pubspec.lock android/app/src/main/res/xml/file_paths.xml
  rm -f test/widget_test.dart
  git clean -fdx android/
  rm -rf build/
  ```
  `git status --short` should show only the changes you actually
  intended after this.
- Kill the emulator if you're done with it: `adb emu kill`.
