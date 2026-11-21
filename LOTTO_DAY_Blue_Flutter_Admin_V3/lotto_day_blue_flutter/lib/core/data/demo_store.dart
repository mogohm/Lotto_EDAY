import 'package:flutter/foundation.dart';

/// In-memory, fictional demo only. No actual purchases, money movement, or official results.
class DemoTicket {
  const DemoTicket(this.id, this.number, this.demoPrice);
  final String id;
  final String number;
  final int demoPrice;
}

class DemoStore extends ChangeNotifier {
  static final DemoStore instance = DemoStore._();
  DemoStore._();
  final tickets = const [
    DemoTicket('t1', '123456', 80),
    DemoTicket('t2', '789012', 80),
    DemoTicket('t3', '456789', 80),
    DemoTicket('t4', '111222', 80),
    DemoTicket('t5', '333444', 80),
    DemoTicket('t6', '888999', 80),
  ];
  final List<DemoTicket> cart = [];
  final List<String> demoReceipts = [];
  bool addTicket(DemoTicket item) {
    if (cart.any((ticket) => ticket.id == item.id)) return false;
    cart.add(item);
    notifyListeners();
    return true;
  }

  void removeTicket(String id) {
    cart.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  int get total => cart.fold(0, (sum, ticket) => sum + ticket.demoPrice);
  void confirmDemo() {
    if (cart.isEmpty) return;
    demoReceipts.insert(0, 'DEMO-${DateTime.now().millisecondsSinceEpoch}');
    cart.clear();
    notifyListeners();
  }
}
