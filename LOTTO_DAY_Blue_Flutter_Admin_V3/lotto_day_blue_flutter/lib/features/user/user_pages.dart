import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ui.dart';

export 'profile_pages.dart';

// ============================================================ HOME
class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => AsyncView<Json>(
        load: () async {
          final api = context.api;
          final s = await api.summary();
          final news = await api.announcements();
          return {...s, 'news': news};
        },
        builder: (context, s, reload) {
          final next = s['nextDraw'] == null ? null : jsonMap(s['nextDraw']);
          final latest = jsonList(s['latestResults']);
          final news = jsonList(s['news']);
          final kyc = '${s['kycStatus']}';
          final cols = MediaQuery.sizeOf(context).width >= 700 ? 6 : 3;
          return PageList(
            onRefresh: () async {
              await reload();
              if (context.mounted) await context.session.refreshCounters();
            },
            children: [
              GradientPanel(
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('สวัสดี', style: TextStyle(color: Colors.white70)),
                      Text('คุณ${s['displayName']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(kyc == 'VERIFIED' ? Icons.verified : Icons.pending_outlined,
                              size: 15, color: kyc == 'VERIFIED' ? LottoColors.primary : LottoColors.negative),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(kycTh[kyc] ?? kyc,
                                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: LottoColors.navy)),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                  InkWell(
                    onTap: () => context.go('/app/wallet'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('เครดิตจำลอง', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(money(s['balance'] as num?), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                      const Text('บาท (DEMO)', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              _NextDrawCard(next),
              const SectionTitle('เมนูหลัก'),
              GridView.count(
                crossAxisCount: cols,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.05,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  QuickTile(label: 'ตรวจผลรางวัล', icon: Icons.search, onTap: () => context.go('/app/results')),
                  QuickTile(label: 'สลากของฉัน', icon: Icons.confirmation_number, onTap: () => context.go('/app/my-tickets')),
                  QuickTile(label: 'ประวัติรายการ', icon: Icons.receipt_long, onTap: () => context.go('/app/orders')),
                  QuickTile(label: 'เติมเงิน', icon: Icons.account_balance_wallet, onTap: () => context.go('/app/wallet?action=topup')),
                  QuickTile(
                      label: 'ถอนเงิน', icon: Icons.savings_outlined, color: const Color(0xFFE0A800), onTap: () => context.go('/app/wallet?action=withdraw')),
                  QuickTile(label: 'ข่าวสาร / ประกาศ', icon: Icons.campaign_outlined, color: const Color(0xFF8E44AD), onTap: () => context.go('/app/news')),
                ],
              ),
              SectionTitle('ผลรางวัลล่าสุด', trailing: TextButton(onPressed: () => context.go('/app/markets'), child: const Text('ดูทั้งหมด'))),
              if (latest.isEmpty) const EmptyState('ยังไม่มีผลที่ประกาศ'),
              for (final r in latest)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: LottoColors.surface, child: Icon(Icons.emoji_events, color: LottoColors.accent)),
                    title: Text('${r['marketName']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('งวด ${thaiDate(r['drawDate'])}'),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(stringMap(r['results'])['3:top'] ?? stringMap(r['results']).values.firstOrNull ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: LottoColors.navy, letterSpacing: 2)),
                      Text('2 ตัวล่าง ${stringMap(r['results'])['2:bottom'] ?? '-'}', style: const TextStyle(fontSize: 12)),
                    ]),
                    onTap: () => context.go('/app/results'),
                  ),
                ),
              if (news.isNotEmpty) ...[
                SectionTitle('ข่าวสารและประกาศ', trailing: TextButton(onPressed: () => context.go('/app/news'), child: const Text('ทั้งหมด'))),
                for (final n in news.take(3))
                  Card(
                    child: ListTile(
                      leading: Icon(n['pinned'] == true ? Icons.push_pin : Icons.campaign_outlined, color: LottoColors.primary),
                      title: Text('${n['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${n['body']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => context.go('/app/news'),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              const DemoBanner(),
            ],
          );
        },
      );
}

class _NextDrawCard extends StatelessWidget {
  const _NextDrawCard(this.next);
  final Json? next;
  @override
  Widget build(BuildContext context) {
    final n = next;
    return Card(
      elevation: 3,
      shadowColor: LottoColors.primary.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: n == null
            ? const Text('ยังไม่มีงวดที่เปิดรับ')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${n['marketName']} • งวดวันที่', style: const TextStyle(color: Color(0xFF4A6380)))),
                  StatusChip.sales('${n['salesState']}'),
                ]),
                const SizedBox(height: 2),
                Text(thaiDate(n['drawDate']), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: LottoColors.navy)),
                Text('ปิดรับซื้อ: ${thaiDateTime(n['closesAt'])} • เหลือ ${n['available']} ใบ', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.go('/app/catalog?drawId=${n['id']}'),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('ซื้อสลากเลย'),
                  ),
                ),
              ]),
      ),
    );
  }
}

// ============================================================ CATALOG
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, this.drawId});
  final String? drawId;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  List<Json> _draws = [];
  String? _drawId;
  String _query = '';
  int _page = 1;
  PageResult<Ticket>? _result;
  Object? _error;
  bool _loading = true;
  final Set<String> _adding = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final draws = await context.api.catalogDraws();
      _draws = draws;
      _drawId = widget.drawId ??
          draws.where((d) => d['salesState'] == 'OPEN').map((d) => d['id'] as String).firstOrNull ??
          draws.map((d) => d['id'] as String).firstOrNull;
      await _load();
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await context.api.tickets(drawId: _drawId, number: _query, page: page);
      setState(() {
        _result = r;
        _page = page;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(Ticket t) async {
    setState(() => _adding.add(t.id));
    await runAction(context, () async {
      final cart = await context.api.addToCart(t.id);
      if (mounted) context.session.setCartCount((cart['count'] ?? 0) as int);
    }, success: 'เพิ่ม ${t.number} ลงตะกร้าแล้ว');
    if (mounted) setState(() => _adding.remove(t.id));
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final draw = _draws.where((d) => d['id'] == _drawId).firstOrNull;
    final r = _result;
    final pages = r == null ? 1 : ((r.total + 19) ~/ 20).clamp(1, 9999);
    return Column(children: [
      Expanded(
        child: PageList(children: [
          const SectionTitle('ซื้อสลาก'),
          if (_draws.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final d in _draws)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${d['marketName']} • ${thaiDate(d['drawDate'], short: true)}'),
                      selected: d['id'] == _drawId,
                      onSelected: (_) {
                        _drawId = d['id'] as String;
                        _load();
                      },
                    ),
                  ),
              ]),
            ),
          if (draw != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('งวดวันที่ ${thaiDate(draw['drawDate'])}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: LottoColors.navy)),
                      Text('ปิดรับซื้อ: ${thaiDateTime(draw['closesAt'])}', style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                  StatusChip.sales('${draw['salesState']}'),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('catalog-search'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onSubmitted: (v) {
              _query = v;
              _load();
            },
            onChanged: (v) {
              _query = v;
              if (v.isEmpty || v.length >= 2) _load();
            },
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ค้นหาเลขที่ต้องการ (บางส่วนหรือ 6 หลัก)'),
          ),
          const SizedBox(height: 8),
          if (_error != null) ErrorView(_error!, onRetry: _init),
          if (_loading && r == null) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
          if (r != null) ...[
            Text('พบ ${money(r.total)} ใบ', style: const TextStyle(color: Color(0xFF4A6380))),
            const SizedBox(height: 6),
            if (r.items.isEmpty) const EmptyState('ไม่พบหมายเลขที่ค้นหา', icon: Icons.search_off),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 900
                  ? 3
                  : c.maxWidth >= 560
                      ? 2
                      : 1;
              return Wrap(spacing: 8, runSpacing: 0, children: [
                for (final t in r.items)
                  SizedBox(
                    width: (c.maxWidth - (cols - 1) * 8) / cols,
                    child: Card(
                      child: ListTile(
                        onTap: () => context.go('/app/ticket/${t.id}'),
                        leading: const CircleAvatar(
                            backgroundColor: LottoColors.surface, child: Icon(Icons.confirmation_number_outlined, color: LottoColors.primary)),
                        title: Text(t.number, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 2, color: LottoColors.navy)),
                        subtitle: Text('งวด ${thaiDate(t.drawDate, short: true)} • ${t.price} บาท'),
                        trailing: _adding.contains(t.id)
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : IconButton(
                                tooltip: 'เพิ่มในตะกร้า',
                                icon: const Icon(Icons.add_circle_outline, color: LottoColors.primary, size: 28),
                                onPressed: t.salesState == 'OPEN' ? () => _add(t) : null,
                              ),
                      ),
                    ),
                  ),
              ]);
            }),
            if (pages > 1)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(onPressed: _page > 1 ? () => _load(page: _page - 1) : null, icon: const Icon(Icons.chevron_left)),
                Text('หน้า $_page / $pages'),
                IconButton(onPressed: _page < pages ? () => _load(page: _page + 1) : null, icon: const Icon(Icons.chevron_right)),
              ]),
          ],
          const SizedBox(height: 8),
          const DemoBanner(),
        ]),
      ),
      if (session.cartCount > 0)
        SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            decoration:
                BoxDecoration(gradient: const LinearGradient(colors: [LottoColors.primary, LottoColors.secondary]), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Icon(Icons.shopping_cart, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text('ตะกร้า (${session.cartCount} ใบ)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              FilledButton(onPressed: () => context.go('/app/cart'), child: const Text('ตรวจสอบรายการ')),
            ]),
          ),
        ),
    ]);
  }
}

class TicketDetailPage extends StatelessWidget {
  const TicketDetailPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => AsyncView<Ticket>(
        load: () => context.api.ticket(id),
        builder: (context, t, reload) => PageList(maxWidth: 640, children: [
          SectionTitle('รายละเอียดสลาก',
              trailing: TextButton.icon(
                  onPressed: () => context.go('/app/catalog?drawId=${t.drawId}'), icon: const Icon(Icons.arrow_back), label: const Text('กลับ'))),
          GradientPanel(
            child: Column(children: [
              Text(t.marketName, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 6),
              Text(t.number, style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: 6)),
              Text('งวดวันที่ ${thaiDate(t.drawDate)}', style: const TextStyle(color: Colors.white)),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                KeyValueRow('ราคา', '${t.price} บาท (เครดิตจำลอง)'),
                KeyValueRow('สถานะ', t.status == 'AVAILABLE' ? 'ว่าง' : 'ไม่ว่าง'),
                KeyValueRow('ปิดรับซื้อ', thaiDateTime(t.closesAt)),
                const KeyValueRow('ผู้ออกสลาก', 'ข้อมูลสาธิต — ไม่ใช่สลากจริงหรือหลักฐานกรรมสิทธิ์'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: t.status == 'AVAILABLE' && t.salesState == 'OPEN'
                ? () => runAction(context, () async {
                      final c = await context.api.addToCart(t.id);
                      if (context.mounted) context.session.setCartCount((c['count'] ?? 0) as int);
                    }, success: 'เพิ่มลงตะกร้าแล้ว')
                : null,
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(t.salesState == 'OPEN' ? 'เพิ่มลงตะกร้า' : (salesStateTh[t.salesState] ?? 'ไม่เปิดขาย')),
          ),
        ]),
      );
}

// ============================================================ CART / CHECKOUT
class CartPage extends StatelessWidget {
  const CartPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncView<Json>(
        load: () => context.api.cart(),
        builder: (context, cart, reload) {
          final items = jsonList(cart['items']).map(Ticket.new).toList();
          final total = (cart['total'] ?? 0) as int;
          final balance = (cart['balance'] ?? 0) as int;
          final hasProblem = items.any((t) => t.problem != null);
          return PageList(maxWidth: 760, children: [
            const SectionTitle('ตรวจสอบรายการ'),
            if (items.isEmpty)
              EmptyState('ยังไม่มีรายการในตะกร้า',
                  icon: Icons.shopping_cart_outlined, action: FilledButton(onPressed: () => context.go('/app/catalog'), child: const Text('เลือกซื้อสลาก'))),
            for (final t in items)
              Card(
                child: ListTile(
                  leading: Icon(t.problem == null ? Icons.confirmation_number_outlined : Icons.error_outline,
                      color: t.problem == null ? LottoColors.primary : LottoColors.negative),
                  title: Text(t.number, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2)),
                  subtitle: Text('${t.marketName} • งวด ${thaiDate(t.drawDate, short: true)}${t.problem != null ? '\n⚠ ${t.problem}' : ''}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${t.price} บาท'),
                    IconButton(
                      tooltip: 'ลบ',
                      onPressed: () => runAction(context, () async {
                        final c = await context.api.removeFromCart(t.id);
                        if (context.mounted) context.session.setCartCount((c['count'] ?? 0) as int);
                        await reload();
                      }),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ]),
                ),
              ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    KeyValueRow('จำนวน', '${items.length} ใบ'),
                    KeyValueRow('ยอดรวม', baht(total)),
                    KeyValueRow('เครดิตจำลองคงเหลือ', baht(balance)),
                    if (balance < total)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
                          const Expanded(child: Text('เครดิตจำลองไม่พอ', style: TextStyle(color: LottoColors.negative))),
                          TextButton(onPressed: () => context.go('/app/wallet?action=topup'), child: const Text('เติมเครดิตจำลอง')),
                        ]),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('checkout'),
                onPressed: hasProblem || balance < total
                    ? null
                    : () async {
                        if (!await confirmDialog(
                            context, 'ยืนยันรายการ (DEMO)', 'ยืนยันซื้อ ${items.length} ใบ รวม ${baht(total)} ด้วยเครดิตจำลอง\nไม่มีการชำระเงินจริง')) {
                          return;
                        }
                        if (!context.mounted) return;
                        Json? order;
                        final ok = await runAction(context, () async => order = await context.api.checkout(), success: 'ยืนยันรายการสำเร็จ (DEMO)');
                        if (ok && context.mounted) {
                          await context.session.refreshCounters();
                          if (context.mounted) context.go('/app/orders/${order!['id']}');
                        }
                      },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('ยืนยันรายการ (ไม่มีการชำระเงินจริง)'),
              ),
            ],
            const SizedBox(height: 12),
            const DemoBanner(),
          ]);
        },
      );
}

// ============================================================ MY TICKETS
class MyTicketsPage extends StatelessWidget {
  const MyTicketsPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncView<List<Json>>(
        load: () => context.api.myTickets(),
        builder: (context, tickets, reload) => PageList(onRefresh: reload, children: [
          const SectionTitle('สลากของฉัน'),
          if (tickets.isEmpty)
            EmptyState('ยังไม่มีสลาก',
                icon: Icons.confirmation_number_outlined, action: FilledButton(onPressed: () => context.go('/app/catalog'), child: const Text('ซื้อสลาก'))),
          for (final t in tickets) _MyTicketCard(t),
          const SizedBox(height: 8),
          const DemoBanner(),
        ]),
      );
}

class _MyTicketCard extends StatelessWidget {
  const _MyTicketCard(this.t);
  final Json t;
  @override
  Widget build(BuildContext context) {
    final matches = jsonList(t['matches']);
    final state = '${t['resultState']}';
    final (label, color, icon) = switch (state) {
      'ANNOUNCED' when matches.isNotEmpty => ('ตรงกับผล ${matches.map((m) => m['label']).join(', ')}', LottoColors.positive, Icons.emoji_events),
      'ANNOUNCED' => ('ไม่ตรงกับผลที่ประกาศ', LottoColors.ink, Icons.remove_circle_outline),
      'CANCELLED' => ('งวดถูกยกเลิก', LottoColors.negative, Icons.block),
      _ => ('รอประกาศผล', LottoColors.primary, Icons.hourglass_top),
    };
    return Card(
      child: ListTile(
        onTap: () => context.go('/app/orders/${t['orderId']}'),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
        title: Text('${t['number']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 2, color: LottoColors.navy)),
        subtitle: Text('${t['marketName']} • งวด ${thaiDate(t['drawDate'])}\n$label',
            style: TextStyle(color: state == 'ANNOUNCED' && matches.isNotEmpty ? LottoColors.positive : null)),
        isThreeLine: true,
        trailing: Text('${t['price']} บาท'),
      ),
    );
  }
}

// ============================================================ HISTORY (orders + wallet transactions)
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _filter = 'ALL';
  @override
  Widget build(BuildContext context) => AsyncView<List<Json>>(
        load: () => context.api.walletTransactions(),
        builder: (context, txs, reload) {
          final shown = txs.where((t) => _filter == 'ALL' || t['status'] == _filter).toList();
          return PageList(onRefresh: reload, maxWidth: 820, children: [
            SectionTitle('ประวัติรายการ',
                trailing: TextButton.icon(
                    onPressed: () => context.go('/app/my-tickets'), icon: const Icon(Icons.confirmation_number_outlined), label: const Text('สลากของฉัน'))),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ALL', label: Text('ทั้งหมด')),
                ButtonSegment(value: 'SUCCESS', label: Text('สำเร็จ')),
                ButtonSegment(value: 'PENDING', label: Text('รอดำเนินการ')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
            const SizedBox(height: 10),
            if (shown.isEmpty) const EmptyState('ยังไม่มีรายการ', icon: Icons.receipt_long_outlined),
            for (final t in shown) TxTile(t),
            const SizedBox(height: 8),
            const DemoBanner(),
          ]);
        },
      );
}

class TxTile extends StatelessWidget {
  const TxTile(this.t, {super.key});
  final Json t;
  @override
  Widget build(BuildContext context) {
    final type = '${t['type']}';
    final amount = (t['amount'] ?? 0) as int;
    final status = '${t['status']}';
    final icon = switch (type) {
      'PURCHASE_DEMO' => Icons.shopping_cart_outlined,
      'TOPUP_DEMO' => Icons.account_balance_wallet_outlined,
      'WITHDRAW_DEMO' => Icons.savings_outlined,
      'REFUND_DEMO' => Icons.undo,
      _ => Icons.swap_horiz,
    };
    final statusColor = status == 'SUCCESS'
        ? LottoColors.positive
        : status == 'PENDING'
            ? const Color(0xFFB7791F)
            : LottoColors.negative;
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: LottoColors.surface, child: Icon(icon, color: LottoColors.primary)),
        title: Text(txTypeTh[type] ?? type, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${thaiDateTime(t['createdAt'])}\n${t['reference'] ?? ''}'),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${amount > 0 ? '+' : ''}${money(amount)} บาท',
              style: TextStyle(fontWeight: FontWeight.w900, color: amount >= 0 ? LottoColors.positive : LottoColors.navy)),
          const SizedBox(height: 4),
          StatusChip(txStatusTh[status] ?? status, color: statusColor),
        ]),
        onTap: type == 'PURCHASE_DEMO' ? () => context.go('/app/my-tickets') : null,
      ),
    );
  }
}

class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => AsyncView<Json>(
        load: () => context.api.order(id),
        builder: (context, o, reload) {
          final items = jsonList(o['items']);
          final cancelled = o['status'] == 'CANCELLED';
          return PageList(maxWidth: 720, children: [
            SectionTitle('ใบรับรายการ (DEMO)',
                trailing: TextButton.icon(onPressed: () => context.go('/app/orders'), icon: const Icon(Icons.arrow_back), label: const Text('ประวัติ'))),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(cancelled ? Icons.cancel : Icons.check_circle, color: cancelled ? LottoColors.negative : LottoColors.positive, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(cancelled ? 'รายการถูกยกเลิก' : 'ยืนยันรายการสำเร็จ', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                  ]),
                  const Divider(height: 24),
                  KeyValueRow('เลขที่ใบรับ', '${o['receiptNo']}'),
                  KeyValueRow('วันที่', thaiDateTime(o['createdAt'])),
                  KeyValueRow('ยอดรวม', baht(o['total'] as num?)),
                  if (cancelled) KeyValueRow('หมายเหตุ', '${o['cancelNote'] ?? '-'}'),
                  const KeyValueRow('การชำระเงิน', 'เครดิตจำลอง — ไม่มีการตัดเงินจริง'),
                ]),
              ),
            ),
            const SectionTitle('รายการสลาก'),
            for (final i in items) _MyTicketCard({...i, 'orderId': o['id']}),
            const SizedBox(height: 8),
            const DemoBanner(),
          ]);
        },
      );
}

// ============================================================ RESULTS (ตรวจผลรางวัล)
class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key});
  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  String? _marketId;
  String? _drawId;
  final _number = TextEditingController();
  Json? _check;
  String? _checkError;

  Future<(List<Market>, List<Draw>)> _load() async {
    final api = context.api;
    final markets = await api.markets();
    _marketId ??= markets.firstOrNull?.id;
    final draws = _marketId == null ? <Draw>[] : await api.published(marketId: _marketId);
    if (_drawId == null || !draws.any((d) => d.id == _drawId)) _drawId = draws.firstOrNull?.id;
    return (markets, draws);
  }

  Future<void> _doCheck() async {
    setState(() {
      _check = null;
      _checkError = null;
    });
    if (!RegExp(r'^\d{6}$').hasMatch(_number.text)) {
      setState(() => _checkError = 'กรุณากรอกเลข 6 หลัก');
      return;
    }
    try {
      final r = await context.api.check(_number.text, drawId: _drawId);
      setState(() => _check = r);
    } catch (e) {
      setState(() => _checkError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AsyncView<(List<Market>, List<Draw>)>(
        key: ValueKey(_marketId),
        load: _load,
        builder: (context, data, reload) {
          final (markets, draws) = data;
          final market = markets.where((m) => m.id == _marketId).firstOrNull;
          final draw = draws.where((d) => d.id == _drawId).firstOrNull;
          final r = draw?.results ?? {};
          return PageList(maxWidth: 820, children: [
            SectionTitle('ตรวจผลรางวัล', trailing: TextButton(onPressed: () => context.go('/app/markets'), child: const Text('ผลย้อนหลัง'))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in markets)
                ChoiceChip(
                  label: Text(m.nameTh),
                  selected: m.id == _marketId,
                  onSelected: (_) => setState(() {
                    _marketId = m.id;
                    _drawId = null;
                    _check = null;
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            if (draws.isEmpty)
              EmptyState(market?.isExternal == true ? 'ยังไม่มีผลที่ผ่านการตรวจสอบแหล่งประกาศสำหรับ ${market!.nameTh}' : 'ยังไม่มีผลที่ประกาศ',
                  icon: Icons.hourglass_empty)
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _drawId,
                      items: [
                        for (final d in draws)
                          DropdownMenuItem(value: d.id, child: Text('งวดวันที่ ${thaiDate(d.drawDate)}', style: const TextStyle(fontWeight: FontWeight.w800)))
                      ],
                      onChanged: (v) => setState(() {
                        _drawId = v;
                        _check = null;
                      }),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: LottoColors.primary,
                    child: Text('🏆 ผลรางวัล • ${market?.nameTh ?? ''}',
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(children: [
                      const Text('เลข 4 ตัวบน', style: TextStyle(color: LottoColors.primary, fontWeight: FontWeight.w700)),
                      Text(r['4:top'] ?? r.values.firstOrNull ?? '-',
                          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: LottoColors.navy, letterSpacing: 6)),
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        _ResultCell('เลขหน้า 3 ตัว', r['3:front']),
                        _ResultCell('เลขท้าย 3 ตัว', r['3:back']),
                        _ResultCell('เลขท้าย 2 ตัว', r['2:bottom']),
                      ]),
                      const Divider(height: 28),
                      ExpansionTile(
                          title: const Text('ดูผลทุกตำแหน่ง (2/3/4 ตัว)'),
                          children: [Padding(padding: const EdgeInsets.all(8), child: ResultGrid(results: r, compact: true))]),
                      if (draw != null)
                        Text(
                          market?.isDaily == true
                              ? 'ผลหวยรายวัน (DEMO) ประกาศ ${thaiDateTime(draw.publishedAt)}'
                              : 'แหล่งอ้างอิง: ${draw.sourceName ?? '-'} • ตรวจสอบแล้ว ${draw.sourceVerified ? '✔' : '✘'}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF4A6380)),
                        ),
                    ]),
                  ),
                ]),
              ),
              const SectionTitle('ตรวจสลากของฉัน'),
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('check-number'),
                    controller: _number,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    onSubmitted: (_) => _doCheck(),
                    decoration: InputDecoration(hintText: 'กรอกเลขสลาก 6 หลัก', errorText: _checkError),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(key: const Key('check-submit'), onPressed: _doCheck, child: const Text('ตรวจผล')),
              ]),
              if (_check != null) _CheckResult(_check!),
              const SizedBox(height: 10),
              FilledButton.icon(
                  onPressed: () => context.go('/app/my-tickets'), icon: const Icon(Icons.confirmation_number), label: const Text('ตรวจสลากของฉัน')),
            ],
          ]);
        },
      );
}

class _ResultCell extends StatelessWidget {
  const _ResultCell(this.label, this.value);
  final String label;
  final String? value;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, style: const TextStyle(color: LottoColors.primary, fontSize: 12)),
        Text(value ?? '-', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: LottoColors.navy, letterSpacing: 2)),
      ]);
}

class _CheckResult extends StatelessWidget {
  const _CheckResult(this.r);
  final Json r;
  @override
  Widget build(BuildContext context) {
    final matches = jsonList(r['matches']);
    final hit = matches.isNotEmpty;
    return Card(
      color: hit ? const Color(0xFFE8F8F0) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(hit ? Icons.emoji_events : Icons.info_outline, color: hit ? LottoColors.positive : LottoColors.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(hit ? 'เลข ${r['number']} ตรงกับ ${matches.length} ตำแหน่ง' : 'เลข ${r['number']} ไม่ตรงกับผลงวดนี้',
                    style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          for (final m in matches) Padding(padding: const EdgeInsets.only(left: 32, top: 4), child: Text('• ${m['label']}: ${m['value']}')),
          const SizedBox(height: 6),
          Text('${r['disclaimer']}', style: const TextStyle(fontSize: 12, color: Color(0xFF4A6380))),
        ]),
      ),
    );
  }
}
