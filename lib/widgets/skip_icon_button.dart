import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Shared ±10s skip button used by `PlayerScreen` and
/// `HistoryDetailScreen` (#147) — both represent the same action (jump
/// the current playback position by 10 seconds) but had drifted apart:
/// the player's version had no tooltip and a hardcoded on-scrim color,
/// history's had a tooltip but relied on the ambient icon theme, which
/// (unlike every other icon on these on-photo screens) isn't forced to a
/// light color — a real, if minor, contrast risk in light theme mode.
/// Both now get an explicit tooltip and the same on-scrim
/// `Colors.white70` default used throughout both screens.
class SkipIconButton extends StatelessWidget {
  final bool forward;
  final VoidCallback onPressed;
  final Color color;
  final double iconSize;

  const SkipIconButton({
    super.key,
    required this.forward,
    required this.onPressed,
    this.color = Colors.white70,
    this.iconSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      icon: Icon(forward ? Icons.forward_10 : Icons.replay_10,
          color: color, size: iconSize),
      tooltip: forward ? l10n.commonSkipForward10 : l10n.commonSkipBack10,
      onPressed: onPressed,
    );
  }
}
