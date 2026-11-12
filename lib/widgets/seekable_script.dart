import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Closing quotes stay with their sentence, French spacing (« … . ») included.
final _sentence = RegExp(r'[^.!?…]+(?:[.!?…]+(?:\s*["»”’)\]])*\s*|$)');

/// #228: start offsets of the sentences of [text] (always starts with 0
/// for a non-empty text), so a long-pressed sentence can be mapped to a
/// point of the narration.
List<int> scriptSentenceStarts(String text) {
  final starts = <int>[];
  for (final m in _sentence.allMatches(text)) {
    if (m.group(0)!.trim().isEmpty) continue;
    starts.add(m.start);
  }
  if (starts.isEmpty && text.isNotEmpty) starts.add(0);
  return starts;
}

/// Script text with the part already read highlighted ([progress], 0-1).
///
/// #228: when [onSeek] is set, long-pressing a sentence calls it with
/// the fraction of the text where that sentence starts — the same linear
/// text-to-time approximation the highlight already uses.
class SeekableScript extends StatefulWidget {
  const SeekableScript({super.key, required this.text, required this.progress, this.onSeek});

  final String text;
  final double progress;
  final ValueChanged<double>? onSeek;

  @override
  State<SeekableScript> createState() => _SeekableScriptState();
}

class _SeekableScriptState extends State<SeekableScript> {
  List<int> _starts = const [];
  List<LongPressGestureRecognizer> _recognizers = const [];

  @override
  void initState() {
    super.initState();
    _rebuildRecognizers();
  }

  @override
  void didUpdateWidget(SeekableScript old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || (old.onSeek == null) != (widget.onSeek == null)) {
      _rebuildRecognizers();
    }
  }

  void _rebuildRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _starts = scriptSentenceStarts(widget.text);
    _recognizers = widget.onSeek == null
        ? const []
        : [
            for (final start in _starts)
              LongPressGestureRecognizer()
                ..onLongPress = () {
                  HapticFeedback.selectionClick();
                  final length = widget.text.length;
                  widget.onSeek?.call(length == 0 ? 0 : start / length);
                },
          ];
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  static const _base = TextStyle(fontSize: 15, height: 1.7);

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final progress = widget.progress;
    final split = progress <= 0 ? 0 : (text.length * progress).round().clamp(0, text.length);
    final readStyle = progress <= 0
        ? _base.copyWith(color: Colors.white70)
        : _base.copyWith(color: Colors.white, fontWeight: FontWeight.w500);
    final unreadStyle = _base.copyWith(color: progress <= 0 ? Colors.white70 : Colors.white38);

    final spans = <TextSpan>[];
    for (var i = 0; i < _starts.length; i++) {
      final start = _starts[i];
      final end = i + 1 < _starts.length ? _starts[i + 1] : text.length;
      final recognizer = i < _recognizers.length ? _recognizers[i] : null;
      void add(int from, int to, TextStyle style) {
        if (to > from) {
          spans.add(TextSpan(text: text.substring(from, to), style: style, recognizer: recognizer));
        }
      }

      if (split <= start) {
        add(start, end, unreadStyle);
      } else if (split >= end) {
        add(start, end, readStyle);
      } else {
        add(start, split, readStyle);
        add(split, end, unreadStyle);
      }
    }
    // Text before the first sentence (leading spaces) isn't lost.
    if (_starts.isNotEmpty && _starts.first > 0) {
      spans.insert(0, TextSpan(text: text.substring(0, _starts.first), style: readStyle));
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Text.rich(TextSpan(children: spans)),
    );
  }
}
