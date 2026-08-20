import 'dart:async';
import 'package:in_app_update/in_app_update.dart';

/// T128: checks the Play Store for an available update on startup and, if
/// one is found and the flexible flow is allowed, silently starts the
/// background download. [onReadyToInstall] fires once that download has
/// finished — the caller is responsible for showing a (discreet) prompt
/// and calling [completeUpdate] when the user agrees to restart.
///
/// This is Android/Play-Store-only and entirely best-effort: any failure
/// (no Play Store account, sideloaded/debug build, emulator without Play
/// services, no connectivity...) is swallowed silently so it can never
/// disrupt startup or surface an error to the user.
class AppUpdateService {
  StreamSubscription<InstallStatus>? _installSub;

  void Function()? onReadyToInstall;

  Future<void> checkAndStartUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }
      if (!info.flexibleUpdateAllowed) return;

      _installSub = InAppUpdate.installUpdateListener.listen((status) {
        if (status == InstallStatus.downloaded) {
          onReadyToInstall?.call();
        }
      });

      await InAppUpdate.startFlexibleUpdate();
    } catch (_) {
      // Best-effort only — see class doc.
    }
  }

  Future<void> completeUpdate() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (_) {
      // Ignore — worst case the user isn't prompted again until the next
      // app restart triggers a fresh checkAndStartUpdate().
    }
  }

  void dispose() {
    _installSub?.cancel();
  }
}
