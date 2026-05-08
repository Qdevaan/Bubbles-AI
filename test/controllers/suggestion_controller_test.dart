import 'package:bubbles/controllers/suggestion_controller.dart';
import 'package:bubbles/services/suggestion_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeService extends SuggestionService {
  int calls = 0;
  List<bool> draftFlags = [];

  _FakeService() : super('http://x', 'jwt');

  @override
  Future<SuggestionResult?> fetch({
    required String userId,
    required String sessionId,
    required String partnerUtterance,
    required String tone,
    required bool isDraft,
    required CancelToken cancelToken,
  }) async {
    calls++;
    draftFlags.add(isDraft);
    return SuggestionResult(
      suggestions: const ['a', 'b', 'c'],
      kind: isDraft ? 'draft' : 'final',
      latencyMs: 100,
      requestId: 'r',
    );
  }
}

void main() {
  test('debounces interim transcripts to a single fetch', () async {
    final svc = _FakeService();
    final c = SuggestionController(
      service: svc,
      userId: 'u',
      sessionId: 's',
      tone: 'casual',
      debounce: const Duration(milliseconds: 80),
    );
    c.onInterimTranscript('hello'); // >= 5 chars
    c.onInterimTranscript('hello1');
    c.onInterimTranscript('hello12');
    c.onInterimTranscript('hello123');
    await Future.delayed(const Duration(milliseconds: 200));
    expect(svc.calls, 1);
    expect(svc.draftFlags, [true]);
    expect(c.suggestions, ['a', 'b', 'c']);
    expect(c.isDraft, true);
  });

  test('final overrides draft', () async {
    final svc = _FakeService();
    final c = SuggestionController(
      service: svc,
      userId: 'u',
      sessionId: 's',
      tone: 'casual',
      debounce: const Duration(milliseconds: 80),
    );
    c.onInterimTranscript('hello');
    await Future.delayed(const Duration(milliseconds: 150));
    c.onFinalTranscript('hello there');
    await Future.delayed(const Duration(milliseconds: 50));
    expect(c.isDraft, false);
    expect(svc.draftFlags.contains(false), true);
  });

  test('clear empties suggestions', () async {
    final svc = _FakeService();
    final c = SuggestionController(
      service: svc,
      userId: 'u',
      sessionId: 's',
      tone: 'casual',
    );
    c.onFinalTranscript('hi');
    await Future.delayed(const Duration(milliseconds: 50));
    c.clear();
    expect(c.suggestions, isEmpty);
  });

  test('skips interim shorter than 5 chars', () async {
    final svc = _FakeService();
    final c = SuggestionController(
      service: svc,
      userId: 'u',
      sessionId: 's',
      tone: 'casual',
      debounce: const Duration(milliseconds: 50),
    );
    c.onInterimTranscript('hi');
    await Future.delayed(const Duration(milliseconds: 100));
    expect(svc.calls, 0);
  });
}
