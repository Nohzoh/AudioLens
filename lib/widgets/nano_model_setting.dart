import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/gemini_nano_service.dart';
import '../services/settings_service.dart';

/// #462: picks the Gemini Nano model variant analyses run on — the
/// default model or one of the 4 Stable/Preview x Fast/Full variants the
/// Nano Prompt Lab already offers (#431), each with its availability on
/// this device and a download action when it's downloadable. A variant
/// that isn't ready can still be picked: analyses use the default model
/// until it is (see GeminiNanoService._usableVariant).
class NanoModelSetting extends StatefulWidget {
  final GeminiNanoService nano;

  const NanoModelSetting({super.key, required this.nano});

  @override
  State<NanoModelSetting> createState() => _NanoModelSettingState();
}

class _NanoModelSettingState extends State<NanoModelSetting> {
  final Map<NanoModelVariant?, NanoDeviceStatus> _statuses = {};
  bool _downloading = false;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    for (final v in <NanoModelVariant?>[null, ...NanoModelVariant.all]) {
      final status = await widget.nano.checkDeviceStatus(variant: v);
      if (!mounted) return;
      setState(() => _statuses[v] = status);
    }
  }

  Future<void> _download(NanoModelVariant variant) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _downloadError = null;
      _statuses[variant] = NanoDeviceStatus.downloading;
    });
    String? error;
    try {
      await widget.nano.downloadVariant(variant);
    } catch (e) {
      error = e.toString();
    }
    final status = await widget.nano.checkDeviceStatus(variant: variant);
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _downloadError = error;
      _statuses[variant] = status;
    });
  }

  String _statusLabel(AppLocalizations l10n, NanoDeviceStatus? status) {
    switch (status) {
      case null:
        return l10n.nanoLabModelChecking;
      case NanoDeviceStatus.available:
        return l10n.nanoLabModelAvailable;
      case NanoDeviceStatus.downloadable:
        return l10n.nanoLabModelDownloadable;
      case NanoDeviceStatus.downloading:
        return l10n.nanoLabModelDownloading;
      case NanoDeviceStatus.unavailable:
        return l10n.nanoLabModelUnavailable;
      case NanoDeviceStatus.unknown:
        return l10n.nanoLabModelUnknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = context.watch<SettingsService>();
    final selected = settings.nanoModelVariant;
    final selectedStatus = _statuses[selected];
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.54));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsNanoModelTitle, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(l10n.settingsNanoModelSubtitle, style: muted),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in <NanoModelVariant?>[null, ...NanoModelVariant.all])
              ChoiceChip(
                label: Text('${v?.label ?? l10n.nanoLabModelDefault} · '
                    '${_statusLabel(l10n, _statuses[v])}'),
                selected: selected == v,
                onSelected: (_) {
                  setState(() => _downloadError = null);
                  settings.setNanoModelVariant(v);
                },
              ),
          ],
        ),
        if (selected != null &&
            selectedStatus != null &&
            selectedStatus != NanoDeviceStatus.available) ...[
          const SizedBox(height: 8),
          Text(
            selectedStatus == NanoDeviceStatus.unavailable
                ? l10n.nanoLabModelUnavailableHint
                : l10n.settingsNanoModelNotReadyHint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
          if (selectedStatus == NanoDeviceStatus.downloadable || _downloading) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: _downloading
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download, size: 18),
              label: Text(l10n.nanoLabModelDownload),
              onPressed: _downloading ? null : () => _download(selected),
            ),
          ],
        ],
        if (_downloadError != null) ...[
          const SizedBox(height: 8),
          Text(_downloadError!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
