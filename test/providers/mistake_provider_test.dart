import 'package:bubbles/providers/mistake_provider.dart';
import 'package:bubbles/services/mistake_service.dart';
import 'package:bubbles/services/suggestion_service.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';

class _FakeService extends MistakeService {
  int calls = 0;
  MistakeCheckResult? next;
  Duration delay = Duration.zero;

  _FakeService() : super('http://x', 'jwt');

  @override
  Future<MistakeCheckResult?> checkTurn({
    required String userId,
    required String sessionId,
    required String transcript,
    required CancelToken cancelToken,
  }) async {
    calls++;
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return next;
  }

  @override
  Future<List<MistakeItem>> listForSession({required String sessionId}) async =>
      [];
}

MistakeCheckResult _resultWith(List<MistakeItem> items) =>
    MistakeCheckResult(
      count: items.length,
      byCategory: {for (final i in items) i.category: 1},
      items: items,
      latencyMs: 100,
    );

void main() {
  test('increments counters from service result', () async {
    final svc = _FakeService();
    final p = MistakeProvider(service: svc);
    svc.next = _resultWith([
      MistakeItem(
          id: '1',
          category: 'grammar',
          snippet: "don't goes",
          ruleId: 'r1',
          source: 'lt'),
      MistakeItem(
          id: '2',
          category: 'filler',
          snippet: 'um',
          ruleId: 'llm-filler',
          source: 'llm'),
    ]);
    await p.onUserTurnFinal('u', 's', "she don't goes um");
    expect(p.sessionTotal, 2);
    expect(p.byCategory['grammar'], 1);
    expect(p.byCategory['filler'], 1);
    expect(p.items.length, 2);
  });

  test('null result leaves state unchanged', () async {
    final svc = _FakeService();
    final p = MistakeProvider(service: svc);
    svc.next = null;
    await p.onUserTurnFinal('u', 's', 'hi');
    expect(p.sessionTotal, 0);
  });

  test('clear resets state', () async {
    final svc = _FakeService();
    final p = MistakeProvider(service: svc);
    svc.next = _resultWith([
      MistakeItem(
          id: '1',
          category: 'grammar',
          snippet: 'x',
          ruleId: 'r',
          source: 'lt'),
    ]);
    await p.onUserTurnFinal('u', 's', 'x');
    p.clear();
    expect(p.sessionTotal, 0);
    expect(p.byCategory, isEmpty);
    expect(p.items, isEmpty);
  });

  test('coalesces concurrent calls', () async {
    final svc = _FakeService()
      ..delay = const Duration(milliseconds: 30)
      ..next = _resultWith([]);
    final p = MistakeProvider(service: svc);
    final f1 = p.onUserTurnFinal('u', 's', 'one');
    final f2 = p.onUserTurnFinal('u', 's', 'two'); // dropped while in-flight
    await Future.wait([f1, f2]);
    expect(svc.calls, 1);
  });
}
