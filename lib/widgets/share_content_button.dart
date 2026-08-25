import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import 'scrim_action_chip.dart';

/// #125: shares a history entry's audio or script via the platform share
/// sheet — a sibling item in the same Save/Copy/Report row, same rationale
/// as [ReportContentButton] (single reusable widget so any future styling
/// change to the row happens in one place).
///
/// One button, not two ("share text" / "share audio"): when a generated
/// audio file exists, that's the more "finished" artifact and is shared in
/// its place — a script-only entry (no audio yet, or the native TTS
/// fallback was used and never produced a file) falls back to sharing the
/// text instead. This keeps the action row from growing a fourth chip for
/// what's really one user intent ("share what I have").
class ShareContentButton extends StatelessWidget {
  final String title;
  final String script;
  final String? audioPath;

  /// Injectable for tests — [SharePlus.instance] is a lazily-constructed
  /// singleton that only captures `SharePlatform.instance` at its *first*
  /// access process-wide, so a test-local fake platform set up per-test
  /// would silently stop taking effect after the first test in a file to
  /// actually trigger a share. Same idea as `GeminiApiService`'s injectable
  /// `dioClient`.
  final SharePlus? sharePlus;

  const ShareContentButton({
    super.key,
    required this.title,
    required this.script,
    this.audioPath,
    this.sharePlus,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ScrimActionChip(
      icon: Icons.share,
      label: l10n.shareContentButton,
      onTap: _share,
    );
  }

  Future<void> _share() async {
    final path = audioPath;
    final shareParams = path != null && File(path).existsSync()
        ? ShareParams(text: title, files: [XFile(path)])
        : ShareParams(text: script, subject: title);
    await (sharePlus ?? SharePlus.instance).share(shareParams);
  }
}
