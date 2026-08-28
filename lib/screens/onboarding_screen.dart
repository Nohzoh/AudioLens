import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_guide_service.dart';
import '../services/secure_key_storage.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';

/// #298: rewritten from a single "enter your API key" gate into a
/// carousel — the old version never explained the photo→audio-guide
/// flow, never mentioned local AI existed at all, and unconditionally
/// required a cloud API key even on a device where Nano already works.
/// [guide.nanoAvailable] (page 3's device-specific status line, and page
/// 4's optional-vs-required gating) is safe to read synchronously here:
/// `main()` fully awaits `AudioGuideService.init()` before `runApp()`,
/// so it's already resolved by the time this screen can render.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 4;

  final _pageController = PageController();
  final _apiKeyController = TextEditingController();
  int _page = 0;
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
    _pageController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _next() {
    if (_page == _pageCount - 1) {
      _finish();
    } else {
      _goToPage(_page + 1);
    }
  }

  Future<void> _finish() async {
    final guide = context.read<AudioGuideService>();
    final key = _apiKeyController.text.trim();
    // A key is only mandatory when nothing else would make the app
    // usable — on a device where Nano already works, finishing without
    // one is fine (see SettingsService.completeOnboarding's own doc for
    // why this check lives here, not there).
    if (!guide.nanoAvailable && key.isEmpty) {
      setState(() =>
          _error = AppLocalizations.of(context)!.onboardingApiKeyRequired);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context
          .read<SettingsService>()
          .completeOnboarding(apiKey: key.isEmpty ? null : key);
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
    final guide = context.watch<AudioGuideService>();
    final isLastPage = _page == _pageCount - 1;

    // #236: see the matching comment in home_screen.dart's build().
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (page) => setState(() => _page = page),
                  children: [
                    const _IntroPage(),
                    const _HowItWorksPage(),
                    _AiModesPage(nanoAvailable: guide.nanoAvailable),
                    _ApiKeyPage(
                      controller: _apiKeyController,
                      nanoAvailable: guide.nanoAvailable,
                      error: _error,
                      onChanged: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pageCount,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Row(
                  children: [
                    if (!isLastPage)
                      TextButton(
                        onPressed: _loading ? null : () => _goToPage(_pageCount - 1),
                        child: Text(l10n.mapPickerSkip),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _loading ? null : _next,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(140, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _loading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary),
                            )
                          : Text(isLastPage ? l10n.onboardingLetsGo : l10n.onboardingNext),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎧', style: TextStyle(fontSize: 64))
                .animate()
                .fadeIn()
                .slideY(begin: -0.2),
            const SizedBox(height: 20),
            Text(
              'AudioLens',
              style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
            ).animate(delay: 100.ms).fadeIn(),
            const SizedBox(height: 12),
            Text(
              l10n.onboardingTagline,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ).animate(delay: 200.ms).fadeIn(),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final steps = [
      (Icons.camera_alt_outlined, l10n.onboardingStep1),
      (Icons.auto_awesome_outlined, l10n.onboardingStep2),
      (Icons.headphones_outlined, l10n.onboardingStep3),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.onboardingHowItWorksTitle,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ).animate().fadeIn(),
          const SizedBox(height: 32),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(steps[i].$1, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(steps[i].$2, style: theme.textTheme.bodyLarge),
                  ),
                ],
              ),
            ).animate(delay: (150 * (i + 1)).ms).fadeIn().slideX(begin: 0.1),
        ],
      ),
    );
  }
}

class _AiModesPage extends StatelessWidget {
  const _AiModesPage({required this.nanoAvailable});

  final bool nanoAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            l10n.onboardingAiModesTitle,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ).animate().fadeIn(),
          const SizedBox(height: 24),
          _AiModeCard(
            icon: Icons.phone_android,
            name: l10n.settingsLocalAiName,
            description: l10n.settingsNanoDescription,
            statusLine: nanoAvailable
                ? l10n.onboardingNanoAvailableOnDevice
                : l10n.settingsNanoUnavailableDevice,
            statusIsPositive: nanoAvailable,
          ).animate(delay: 150.ms).fadeIn(),
          const SizedBox(height: 16),
          _AiModeCard(
            icon: Icons.cloud_outlined,
            name: 'Gemini API',
            description: l10n.settingsApiDescription,
            statusLine: l10n.settingsGetFreeKey,
            statusIsPositive: null,
          ).animate(delay: 300.ms).fadeIn(),
        ],
      ),
    );
  }
}

class _AiModeCard extends StatelessWidget {
  const _AiModeCard({
    required this.icon,
    required this.name,
    required this.description,
    required this.statusLine,
    required this.statusIsPositive,
  });

  final IconData icon;
  final String name;
  final String description;
  final String statusLine;
  // true = positive (green), false = negative (dimmed/neutral), null =
  // purely informational (no color coding — the "get a free key" line).
  final bool? statusIsPositive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          Text(
            statusLine,
            style: theme.textTheme.bodySmall?.copyWith(
              color: statusIsPositive == true
                  ? Colors.green.shade700
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: statusIsPositive != null ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiKeyPage extends StatelessWidget {
  const _ApiKeyPage({
    required this.controller,
    required this.nanoAvailable,
    required this.error,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool nanoAvailable;
  final String? error;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
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
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  // #298: only mandatory-sounding when it actually is —
                  // a device where Nano already works gets the optional
                  // hint instead of instructions framed as a requirement.
                  nanoAvailable ? l10n.onboardingApiKeyOptionalHint : l10n.onboardingApiKeyInstructions,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'AIza...',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              errorText: error,
              suffixIcon: const Icon(Icons.visibility_off, size: 18),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              l10n.onboardingKeyStoredLocally,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }
}
