import 'package:flutter/material.dart';

/// An [IconButton] on a translucent dark circle, for use over a
/// full-bleed background photo.
///
/// Without the scrim, a plain white icon can become unreadable depending
/// on what's behind it — a bright sky, a pale stone facade. The circle
/// guarantees contrast regardless of the photo underneath, which matters
/// here because the background is always user-supplied and can be
/// anything.
///
/// Extracted from HistoryDetailScreen, where it originated as a private
/// widget, so PlayerScreen can use the same treatment instead of
/// re-deriving it (#146).
class ScrimIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? tooltip;
  final VoidCallback onPressed;

  const ScrimIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.35),
      ),
      child: IconButton(
        icon: Icon(icon, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
