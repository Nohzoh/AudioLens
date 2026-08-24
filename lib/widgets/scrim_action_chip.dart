import 'package:flutter/material.dart';

/// A small icon+label action on a translucent dark pill, for the
/// Save / Copy / Report row that sits over a full-bleed background photo.
///
/// Same rationale as [ScrimIconButton] (#146), applied to the text
/// actions: without a backdrop these are thin light-grey glyphs and 12px
/// text directly on a user-supplied photo, which can become unreadable
/// over a bright sky or pale stone (#149).
///
/// The pill deliberately keeps the caller's [color] rather than forcing
/// one: the row has an intentional hierarchy — Save and Copy are primary
/// actions, Report is deliberately quieter — and flattening that to a
/// single colour to "fix contrast" would lose information the scrim
/// already solves on its own.
class ScrimActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ScrimActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    // Radius matches the pill's own height rather than a fixed value, so
    // it stays a true pill if text scaling grows the row.
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(100),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
