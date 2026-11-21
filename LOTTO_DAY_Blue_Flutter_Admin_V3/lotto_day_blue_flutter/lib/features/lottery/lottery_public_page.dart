import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ui.dart';

/// Results history for the 4 market types (published results only).
class LotteryPublicPage extends StatefulWidget {
  const LotteryPublicPage({super.key});
  @override
  State<LotteryPublicPage> createState() => _LotteryPublicPageState();
}

class _LotteryPublicPageState extends State<LotteryPublicPage> {
  String? marketId;

  @override
  Widget build(BuildContext context) => AsyncView<(List<Market>, List<Draw>)>(
        key: ValueKey(marketId),
        load: () async {
          final api = context.api;
          final markets = await api.markets();
          marketId ??= markets.firstOrNull?.id;
          return (markets, await api.published(marketId: marketId));
        },
        builder: (context, data, reload) {
          final (markets, published) = data;
          final market = markets.where((m) => m.id == marketId).firstOrNull;
          return PageList(onRefresh: reload, children: [
            const SectionTitle('ผลหวยย้อนหลัง • 4 ประเภท'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in markets) ChoiceChip(label: Text(m.nameTh), selected: marketId == m.id, onSelected: (_) => setState(() => marketId = m.id)),
            ]),
            const SizedBox(height: 14),
            if (market != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(market.nameTh, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: LottoColors.navy)),
                    const SizedBox(height: 4),
                    Text(market.isDaily
                        ? 'ผลจำลองที่ผู้ดูแลกำหนดหรือสุ่ม (DEMO) • ประกาศ ${market.resultTime} น.'
                        : 'แสดงเฉพาะผลที่ผู้ตรวจสอบยืนยันกับแหล่งประกาศแล้ว • ห้ามใช้อ้างอิงการจ่ายรางวัล'),
                    const SizedBox(height: 4),
                    Text('รองรับ: ${market.digits.join('/')} ตัว • ${market.positions.map((p) => positionTh[p]).join(' / ')}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF4A6380))),
                  ]),
                ),
              ),
            if (published.isEmpty) const EmptyState('ยังไม่มีผลที่เผยแพร่', icon: Icons.hourglass_empty),
            for (final draw in published)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('งวด ${thaiDate(draw.drawDate)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                      if (market?.isDaily == true)
                        const StatusChip('DEMO', color: Color(0xFFB7791F), icon: Icons.science_outlined)
                      else
                        StatusChip.draw(draw.status),
                    ]),
                    if (draw.sourceName != null) Text('แหล่งอ้างอิง: ${draw.sourceName}', style: const TextStyle(fontSize: 12)),
                    ResultGrid(results: draw.results, compact: true),
                  ]),
                ),
              ),
          ]);
        },
      );
}
