import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A discrete Ko-fi support button widget.
///
/// This widget displays a small heart icon (or custom icon) that opens
/// the Ko-fi support page when pressed. It can be shown/hidden based
/// on user preferences.
class KofiButton extends StatelessWidget {
  final bool show;
  final Color? iconColor;
  final double? iconSize;

  const KofiButton({
    super.key,
    required this.show,
    this.iconColor,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return IconButton(
      icon: Icon(
        Icons.favorite_border,
        color: iconColor ?? Colors.grey[600],
        size: iconSize ?? 20,
      ),
      tooltip: 'Soutenir AudioLens',
      onPressed: () => launchUrl(
        Uri.parse('https://ko-fi.com/tarnaud'),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}
