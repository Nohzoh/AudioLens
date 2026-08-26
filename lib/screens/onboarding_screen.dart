import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../l10n/app_localizations.dart';
import '../services/secure_key_storage.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppLogger.nav('OnboardingScreen opened');
  }

  @override
  void dispose() {
    AppLogger.nav('OnboardingScreen closed');
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(() =>
          _error = AppLocalizations.of(context)!.onboardingApiKeyRequired);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<SettingsService>().completeOnboarding(apiKey: key);
    } on SecureStorageUnavailableException {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppLocalizations.of(context)!.secureStorageUnavailable;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    // #236: see the matching comment in home_screen.dart's build().
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                const Text('🎧', style: TextStyle(fontSize: 48))
                    .animate()
                    .fadeIn()
                    .slideY(begin: -0.2),
                const SizedBox(height: 16),
                Text(
                  'AudioLens',
                  style: theme.textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ).animate(delay: 100.ms).fadeIn(),
                const SizedBox(height: 8),
                Text(
                  l10n.onboardingTagline,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ).animate(delay: 200.ms).fadeIn(),
                const SizedBox(height: 48),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Text('🔑', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(
                          l10n.onboardingApiKeySectionTitle,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        l10n.onboardingApiKeyInstructions,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ).animate(delay: 300.ms).fadeIn(),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'AIza...',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    errorText: _error,
                    suffixIcon: const Icon(Icons.visibility_off, size: 18),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ).animate(delay: 400.ms).fadeIn(),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _loading ? null : _finish,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _loading
                      // #145: onPrimary, not onSurface — this spinner sits on
                      // the button's own primary-colored fill, not the page.
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary))
                      : Text(l10n.onboardingLetsGo,
                          style: const TextStyle(fontSize: 18)),
                ).animate(delay: 500.ms).fadeIn(),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    l10n.onboardingKeyStoredLocally,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
