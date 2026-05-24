/// Pure, local heuristic for the F4 Live Confidence Meter.
///
/// Inputs a rolling window of transcribed user speech (last ~8 s by
/// default) and returns a confidence score in [0.0, 1.0].
///
/// Formula:
///
///   filler_density = (filler + 0.5 * hedge) / max(words, 1)
///   confidence     = clamp(1.0 - 4.0 * filler_density, 0.0, 1.0)
///
/// Tuned so that 25 % filler density ⇒ confidence 0.0.
class ConfidenceHeuristic {
  static const Duration windowDuration = Duration(seconds: 8);

  static const List<String> fillerTokens = [
    'um',
    'uh',
    'er',
    'ah',
    'hmm',
    'like',
    'basically',
    'literally',
    'actually',
  ];

  /// Phrases must be matched as whole-word bigrams / trigrams.
  static const List<String> hedgePhrases = [
    'you know',
    'sort of',
    'kind of',
    'i mean',
    'i think',
    'i guess',
    'maybe',
    'possibly',
  ];

  /// Word-tokenise lowercased text. Punctuation is stripped; contractions
  /// like "i'm", "you're" survive as single tokens.
  static List<String> tokenize(String text) {
    if (text.isEmpty) return const [];
    final lower = text.toLowerCase();
    // Keep apostrophes inside words ("don't") but drop everything else
    // that isn't a letter or digit.
    final cleaned = lower.replaceAll(RegExp(r"[^a-z0-9'\s]"), ' ');
    return cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
  }

  /// Count occurrences of each filler token (whole-word, case-insensitive).
  static int countFillers(List<String> tokens) {
    int n = 0;
    for (final t in tokens) {
      if (fillerTokens.contains(t)) n += 1;
    }
    return n;
  }

  /// Count occurrences of each hedge phrase via sliding window over
  /// tokens (bigram / trigram match).
  static int countHedges(List<String> tokens) {
    if (tokens.length < 2) return 0;
    int n = 0;
    for (final phrase in hedgePhrases) {
      final parts = phrase.split(' ');
      if (parts.length == 1) {
        for (final t in tokens) {
          if (t == parts[0]) n += 1;
        }
        continue;
      }
      for (var i = 0; i + parts.length <= tokens.length; i++) {
        var match = true;
        for (var k = 0; k < parts.length; k++) {
          if (tokens[i + k] != parts[k]) {
            match = false;
            break;
          }
        }
        if (match) n += 1;
      }
    }
    return n;
  }

  /// Compute confidence score from raw transcript text.
  static double scoreForText(String text) {
    final tokens = tokenize(text);
    return scoreForTokens(tokens);
  }

  static double scoreForTokens(List<String> tokens) {
    if (tokens.isEmpty) return 1.0; // no speech yet → assume confident
    final filler = countFillers(tokens);
    final hedge = countHedges(tokens);
    final words = tokens.length;
    final density = (filler + 0.5 * hedge) / (words == 0 ? 1 : words);
    final score = 1.0 - 4.0 * density;
    if (score.isNaN) return 1.0;
    if (score < 0.0) return 0.0;
    if (score > 1.0) return 1.0;
    return score;
  }
}

/// Marks each transcript chunk with the wall-clock time it was produced
/// so the meter can drop chunks older than the rolling window.
class _Chunk {
  final DateTime t;
  final String text;
  const _Chunk(this.t, this.text);
}

/// Rolling buffer of transcribed text; computes the heuristic over the
/// most recent [ConfidenceHeuristic.windowDuration].
class ConfidenceWindow {
  ConfidenceWindow();

  final List<_Chunk> _chunks = [];

  void clear() => _chunks.clear();

  void addChunk(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _chunks.add(_Chunk(DateTime.now(), trimmed));
    _gc();
  }

  void _gc() {
    final cutoff =
        DateTime.now().subtract(ConfidenceHeuristic.windowDuration);
    _chunks.removeWhere((c) => c.t.isBefore(cutoff));
  }

  /// Current confidence score for the rolling window.
  double currentScore() {
    _gc();
    if (_chunks.isEmpty) return 1.0;
    final joined = _chunks.map((c) => c.text).join(' ');
    return ConfidenceHeuristic.scoreForText(joined);
  }
}
