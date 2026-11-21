import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ui.dart';
import 'user_pages.dart';

/// Simulated wallet. Credits are non-redeemable; no payment provider is connected.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key, this.action});
  final String? action;
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  bool _autoOpened = false;

  Future<void> _amountDialog(BuildContext context, {required bool topup, required Future<void> Function() reload}) async {
    final c = TextEditingController(text: topup ? '500' : '');
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(topup ? 'เติมเครดิตจำลอง' : 'ขอถอนเครดิตจำลอง'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(topup ? 'ไม่มีการตัดเงินจริง — ใช้ทดสอบการซื้อเท่านั้น' : 'คำขอจะรอผู้ดูแลอนุมัติ — ไม่มีการโอนเงินจริง', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          if (topup)
            Wrap(spacing: 8, children: [
              for (final v in [100, 500, 1000, 2000]) ActionChip(label: Text('$v'), onPressed: () => c.text = '$v'),
            ]),
          const SizedBox(height: 8),
          TextField(
            key: const Key('amount'),
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: const InputDecoration(labelText: 'จำนวน (บาท)', helperText: 'ขั้นต่ำ 20 บาท'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)), child: const Text('ยืนยัน')),
        ],
      ),
    );
    if (amount == null || !context.mounted) return;
    final ok = await runAction(context, () async {
      if (topup) {
        await context.api.topup(amount);
      } else {
        await context.api.withdraw(amount);
      }
    }, success: topup ? 'เติมเครดิตจำลอง ${baht(amount)} แล้ว' : 'ส่งคำขอถอนจำลองแล้ว');
    if (ok && context.mounted) {
      await context.session.refreshCounters();
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) => AsyncView<(Json, List<Json>)>(
        load: () async {
          final api = context.api;
          return (await api.wallet(), await api.walletTransactions());
        },
        builder: (context, data, reload) {
          final (w, txs) = data;
          if (!_autoOpened && widget.action != null) {
            _autoOpened = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _amountDialog(context, topup: widget.action == 'topup', reload: reload);
            });
          }
          return PageList(onRefresh: reload, maxWidth: 760, children: [
            const SectionTitle('กระเป๋าเครดิตจำลอง'),
            GradientPanel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ยอดคงเหลือ (DEMO)', style: TextStyle(color: Colors.white70)),
                Text(baht(w['balance'] as num?), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text('เครดิตจำลองไม่สามารถแลกเป็นเงินจริงได้', style: TextStyle(color: Colors.white, fontSize: 12)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('topup'),
                      onPressed: () => _amountDialog(context, topup: true, reload: reload),
                      icon: const Icon(Icons.add),
                      label: const Text('เติมเงิน'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          minimumSize: const Size(48, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      onPressed: () => _amountDialog(context, topup: false, reload: reload),
                      icon: const Icon(Icons.savings_outlined),
                      label: const Text('ถอนเงิน'),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock, color: LottoColors.negative),
                title: const Text('การชำระเงินจริงปิดอยู่'),
                subtitle: Text('PAYMENT_ENABLED = ${w['paymentEnabled']} • ต้องได้รับอนุญาตก่อนเชื่อมต่อผู้ให้บริการชำระเงิน'),
              ),
            ),
            const SectionTitle('ธุรกรรมล่าสุด'),
            if (txs.isEmpty) const EmptyState('ยังไม่มีธุรกรรม'),
            for (final t in txs) TxTile(t),
          ]);
        },
      );
}
