import 'package:flutter_test/flutter_test.dart';
import 'package:lotto_day_blue/features/lottery/lottery_store.dart';

void main() {
  test('four supported markets', () {
    expect(LotteryDemoStore.instance.markets.map((m) => m.id), containsAll(['daily', 'lao', 'vietnam', 'thai']));
  });
  test('leading zeros preserved and validation checks exact digit count', () {
    expect(LotteryDemoStore.validNumber('0012', 4), isTrue);
    expect(LotteryDemoStore.validNumber('12', 4), isFalse);
    expect(LotteryDemoStore.validNumber('12x', 3), isFalse);
  });
  test('daily demo can generate, publish and then lock result', () {
    final store = LotteryDemoStore.instance;
    final draw = store.forMarket('daily').first;
    store.generateDailyDemo(draw);
    expect(draw.results[LotteryDemoStore.key(4, NumberPosition.front)]?.length, 4);
    store.publishDemo(draw);
    expect(draw.status, DrawState.published);
    expect(() => store.generateDailyDemo(draw), throwsStateError);
  });
  test('external result cannot be published by demo operator', () {
    final store = LotteryDemoStore.instance;
    final draw = store.forMarket('thai').first;
    store.saveDraft(draw, {'2:bottom': '07'}, sourceNote: 'Source requires official verification');
    expect(() => store.publishDemo(draw), throwsStateError);
  });
}
