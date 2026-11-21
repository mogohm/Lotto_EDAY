import 'package:flutter_test/flutter_test.dart';
import 'package:lotto_day_blue/core/data/demo_store.dart';

void main() {
  test('demo cart de-duplicates and clears on confirmation', () {
    final store = DemoStore.instance;
    store.cart.clear();
    store.demoReceipts.clear();
    expect(store.addTicket(store.tickets.first), isTrue);
    expect(store.addTicket(store.tickets.first), isFalse);
    expect(store.total, 80);
    store.confirmDemo();
    expect(store.cart, isEmpty);
    expect(store.demoReceipts, hasLength(1));
  });
}
