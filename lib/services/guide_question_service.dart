import 'gemini_api_service.dart';
import 'gemini_nano_service.dart';
import '../utils/app_logger.dart';
import '../utils/cancel_token.dart';
import '../utils/error_sanitizer.dart';
import '../utils/script_cleanup.dart';

/// #424: one question asked after a guide, and its answer.
class GuideExchange {
  final String question;
  final String answer;
  const GuideExchange(this.question, this.answer);
}

/// #424: how many questions can be asked about one guide in a row —
/// earlier exchanges are sent back with each question, and the prompt
/// must stay short enough for the on-device model.
const maxGuideQuestions = 5;

/// Context kept for the on-device model, whose input is limited (#420):
/// the script plus this much of the place context.
const _nanoContextChars = 2500;

/// #424: the prompt answering [question] about a guide, from its
/// [script] and the [context] the analysis had (place, Wikipedia...).
/// The model is asked to say so when the answer is not there.
String buildGuideQuestionPrompt({
  required String title,
  required String script,
  String? context,
  String? language,
  List<GuideExchange> previous = const [],
  required String question,
  int? maxContextChars,
}) {
  final buffer = StringBuffer()
    ..writeln('Tu es le guide audio qui vient de présenter « $title » à un visiteur.')
    ..writeln()
    ..writeln('Texte du guide :')
    ..writeln(script.trim());
  var ctx = context?.trim();
  if (ctx != null && ctx.isNotEmpty) {
    if (maxContextChars != null && ctx.length > maxContextChars) {
      ctx = '${ctx.substring(0, maxContextChars)}…';
    }
    buffer
      ..writeln()
      ..writeln('Informations disponibles sur le lieu :')
      ..writeln(ctx);
  }
  if (previous.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Questions déjà posées :');
    for (final e in previous) {
      buffer
        ..writeln('- Question : ${e.question}')
        ..writeln('  Réponse : ${e.answer}');
    }
  }
  final lang = (language == null || language.isEmpty) ? 'Français' : language;
  buffer
    ..writeln()
    ..writeln('Question du visiteur : $question')
    ..writeln()
    ..writeln('Réponds exclusivement en $lang, en deux à quatre phrases, uniquement à partir '
        'du texte du guide et des informations ci-dessus. Si la réponse n\'y figure pas, '
        'dis-le simplement, sans inventer. Pas de titre, pas de liste, pas de mise en forme.');
  return buffer.toString();
}

/// #424: no model can answer (no Gemini API key and no on-device model).
class GuideQuestionUnavailableException implements Exception {
  const GuideQuestionUnavailableException();
}

/// #424: answers a question about a guide with the cloud model when a
/// key is configured, else (or if the cloud call fails) the on-device one.
class GuideQuestionService {
  GuideQuestionService({this.api, this.nano, this.nanoAvailable = false});

  final GeminiApiService? api;
  final GeminiNanoService? nano;
  final bool nanoAvailable;

  bool get isAvailable => api != null || (nano != null && nanoAvailable);

  Future<String> ask({
    required String title,
    required String script,
    String? context,
    String? language,
    List<GuideExchange> previous = const [],
    required String question,
    CancelToken? cancelToken,
  }) async {
    if (!isAvailable) throw const GuideQuestionUnavailableException();
    final cloud = api;
    if (cloud != null) {
      try {
        final answer = await cloud.answerQuestion(
          buildGuideQuestionPrompt(
            title: title,
            script: script,
            context: context,
            language: language,
            previous: previous,
            question: question,
          ),
          cancelToken: cancelToken,
        );
        AppLogger.ai('Guide question answered by Gemini API');
        return cleanMarkdown(answer);
      } catch (e) {
        if (cancelToken?.isCancelled ?? false) rethrow;
        if (!(nano != null && nanoAvailable)) rethrow;
        AppLogger.error('Guide question: Gemini API failed, trying on-device: '
            '${sanitizeError(e.toString())}');
      }
    }
    final answer = await nano!.rawPrompt(
      prompt: buildGuideQuestionPrompt(
        title: title,
        script: script,
        context: context,
        language: language,
        // The on-device model's input is short: the last exchange only.
        previous: previous.isEmpty ? const [] : [previous.last],
        question: question,
        maxContextChars: _nanoContextChars,
      ),
      maxOutputTokens: 256,
    );
    final cleaned = cleanMarkdown(answer).trim();
    if (cleaned.isEmpty) throw Exception('Gemini Nano: empty answer');
    AppLogger.ai('Guide question answered on-device');
    return cleaned;
  }
}
