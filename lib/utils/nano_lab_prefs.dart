import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// #609: the Nano lab's last settings, restored when the screen reopens
/// so the same analysis can be repeated without filling everything in
/// again. Results are never part of it.
class NanoLabPrefs {
  static const storageKey = 'nano_lab_prefs';

  final bool pipelineMode;
  final String? variantKey;
  final String maxTokens;
  final String temperature;
  final String prompt;
  final String latitude;
  final String longitude;
  final String caseId;
  final bool locationFirst;
  final bool fullPrevious;
  final bool? titleLookup;
  final int? imageMaxSide;
  final int compareRounds;

  /// Copy of the chosen photo kept in the app's own storage.
  final String? imagePath;

  const NanoLabPrefs({
    this.pipelineMode = false,
    this.variantKey,
    this.maxTokens = '256',
    this.temperature = '',
    this.prompt = '',
    this.latitude = '',
    this.longitude = '',
    this.caseId = '',
    this.locationFirst = false,
    this.fullPrevious = false,
    this.titleLookup,
    this.imageMaxSide,
    this.compareRounds = 1,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'pipeline_mode': pipelineMode,
        'variant': variantKey,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'prompt': prompt,
        'latitude': latitude,
        'longitude': longitude,
        'case_id': caseId,
        'location_first': locationFirst,
        'full_previous': fullPrevious,
        'title_lookup': titleLookup,
        'image_max_side': imageMaxSide,
        'compare_rounds': compareRounds,
        'image_path': imagePath,
      };

  factory NanoLabPrefs.fromJson(Map<String, dynamic> json) {
    String str(String key, [String fallback = '']) {
      final v = json[key];
      return v is String ? v : fallback;
    }

    final rounds = json['compare_rounds'];
    return NanoLabPrefs(
      pipelineMode: json['pipeline_mode'] == true,
      variantKey: json['variant'] as String?,
      maxTokens: str('max_tokens', '256'),
      temperature: str('temperature'),
      prompt: str('prompt'),
      latitude: str('latitude'),
      longitude: str('longitude'),
      caseId: str('case_id'),
      locationFirst: json['location_first'] == true,
      fullPrevious: json['full_previous'] == true,
      titleLookup: json['title_lookup'] as bool?,
      imageMaxSide: json['image_max_side'] as int?,
      compareRounds: rounds is int && rounds >= 1 ? rounds : 1,
      imagePath: json['image_path'] as String?,
    );
  }

  static Future<NanoLabPrefs> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(storageKey);
      if (raw == null) return const NanoLabPrefs();
      return NanoLabPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const NanoLabPrefs();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(toJson()));
  }
}
