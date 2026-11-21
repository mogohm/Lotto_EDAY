import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/ui.dart';

// ============================================================ MARKETS
class LotteryMarketsAdminPage extends StatelessWidget {
  const LotteryMarketsAdminPage({super.key});
  @override
  Widget build(BuildContext context) {
    final canManage = context.session.can('markets.manage');
    return AsyncView<List<Market>>(
      load: () => context.api.adminMarkets(),
      builder: (context, markets, reload) => PageList(onRefresh: reload, maxWidth: 1200, padding: const EdgeInsets.all(20), children: [
        SectionTitle('จัดการประเภทหวย',
            trailing: canManage
                ? FilledButton.icon(
                    onPressed: () async {
                      if (await showMarketDialog(context, null) && context.mounted) await reload();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มประเภท'))
                : null),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('4 ประเภทหลัก: หวยรายวัน (กำหนดผลเอง/สุ่ม DEMO), หวยลาว, หวยเวียดนาม, หวยไทย • เลข 2/3/4 ตัว • ตำแหน่ง หน้า/หลัง/บน/ล่าง\n'
                'ผลหวยภายนอกต้องมีแหล่งอ้างอิงและผู้ตรวจสอบคนละคนก่อนเผยแพร่ • ระบบไม่รับโพยหรือเงินจริง'),
          ),
        ),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 1000 ? 2 : 1;
          return Wrap(spacing: 10, children: [
            for (final m in markets)
              SizedBox(
                width: (c.maxWidth - (cols - 1) * 10) / cols,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CircleAvatar(
                            backgroundColor: LottoColors.surface, child: Icon(m.isDaily ? Icons.casino_outlined : Icons.public, color: LottoColors.primary)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.nameTh, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            Text('${kindTh[m.kind]} • ${m.id}', style: const TextStyle(fontSize: 12, color: Color(0xFF4A6380))),
                          ]),
                        ),
                        StatusChip(m.enabled ? 'เปิดใช้งาน' : 'ปิดใช้งาน',
                            color: m.enabled ? LottoColors.positive : LottoColors.negative, icon: m.enabled ? Icons.toggle_on : Icons.toggle_off),
                      ]),
                      const SizedBox(height: 10),
                      Text('เลข ${m.digits.join('/')} ตัว • ${m.positions.map((p) => positionTh[p]).join(' / ')} (${m.keys.length} ช่อง)'),
                      Text('เปิด ${m.openTime} • ปิด ${m.closeTime} • ประกาศผล ${m.resultTime} น. (Asia/Bangkok)'),
                      Text(
                          'วันออก: ${m.weekdays.isEmpty ? 'กำหนดเอง (เช่น 1 และ 16)' : m.weekdays.map((d) => thaiWeekdaysShort[d]).join(' ')} • ราคา ${m.ticketPrice} บาท'),
                      Text(m.isDaily ? 'แหล่งผล: กำหนดเอง / สุ่ม DEMO' : 'แหล่งผล: ภายนอก — ต้องตรวจสอบแหล่งประกาศ',
                          style: TextStyle(color: m.isDaily ? LottoColors.primary : const Color(0xFFB7791F))),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton.tonalIcon(
                            onPressed: () => context.go('/admin/lottery/draws/${m.id}'),
                            icon: const Icon(Icons.calendar_month),
                            label: const Text('จัดการงวด')),
                        if (canManage)
                          OutlinedButton.icon(
                            onPressed: () async {
                              if (await showMarketDialog(context, m) && context.mounted) await reload();
                            },
                            icon: const Icon(Icons.tune),
                            label: const Text('ตั้งค่า'),
                          ),
                      ]),
                    ]),
                  ),
                ),
              ),
          ]);
        }),
      ]),
    );
  }
}

/// Create (market == null) or edit market configuration. Returns true when saved.
Future<bool> showMarketDialog(BuildContext context, Market? market) async {
  final isNew = market == null;
  final id = TextEditingController(text: market?.id ?? '');
  final name = TextEditingController(text: market?.nameTh ?? '');
  final desc = TextEditingController(text: market?.description ?? '');
  final open = TextEditingController(text: market?.openTime ?? '06:00');
  final close = TextEditingController(text: market?.closeTime ?? '15:30');
  final result = TextEditingController(text: market?.resultTime ?? '16:00');
  final price = TextEditingController(text: '${market?.ticketPrice ?? 80}');
  var kind = market?.kind ?? 'DAILY';
  var enabled = market?.enabled ?? true;
  final digits = {
    ...(market?.digits ?? [2, 3, 4])
  };
  final positions = {...(market?.positions ?? positionOrder)};
  final weekdays = {
    ...(market?.weekdays ?? [0, 1, 2, 3, 4, 5, 6])
  };
  String? error;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(isNew ? 'เพิ่มประเภทหวย' : 'ตั้งค่า ${market.nameTh}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (isNew) ...[
                TextField(controller: id, decoration: const InputDecoration(labelText: 'รหัส (a-z, 0-9, -)', hintText: 'lao-star')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'ชนิด'),
                  items: [for (final k in kindTh.entries) DropdownMenuItem(value: k.key, child: Text(k.value))],
                  onChanged: (v) => setS(() => kind = v!),
                ),
                const SizedBox(height: 10),
              ],
              TextField(controller: name, decoration: const InputDecoration(labelText: 'ชื่อที่แสดง')),
              const SizedBox(height: 10),
              TextField(controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'คำอธิบาย')),
              const SizedBox(height: 12),
              const Text('ประเภทเลข', style: TextStyle(fontWeight: FontWeight.w800)),
              Wrap(spacing: 8, children: [
                for (final d in [2, 3, 4])
                  FilterChip(label: Text('$d ตัว'), selected: digits.contains(d), onSelected: (s) => setS(() => s ? digits.add(d) : digits.remove(d))),
              ]),
              const SizedBox(height: 8),
              const Text('ตำแหน่ง', style: TextStyle(fontWeight: FontWeight.w800)),
              Wrap(spacing: 8, children: [
                for (final p in positionOrder)
                  FilterChip(
                      label: Text(positionTh[p]!), selected: positions.contains(p), onSelected: (s) => setS(() => s ? positions.add(p) : positions.remove(p))),
              ]),
              const SizedBox(height: 8),
              const Text('วันออกผล', style: TextStyle(fontWeight: FontWeight.w800)),
              Wrap(spacing: 6, children: [
                for (var d = 0; d < 7; d++)
                  FilterChip(
                      label: Text(thaiWeekdaysShort[d]),
                      selected: weekdays.contains(d),
                      onSelected: (s) => setS(() => s ? weekdays.add(d) : weekdays.remove(d))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: open, decoration: const InputDecoration(labelText: 'เปิดรับ (HH:mm)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: close, decoration: const InputDecoration(labelText: 'ปิดรับ (HH:mm)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: result, decoration: const InputDecoration(labelText: 'ประกาศผล'))),
              ]),
              const SizedBox(height: 10),
              TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'ราคาสลาก (บาท, DEMO)')),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: enabled, onChanged: (v) => setS(() => enabled = v), title: const Text('เปิดใช้งาน')),
              if (error != null) Text(error!, style: const TextStyle(color: LottoColors.negative)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () async {
              if (digits.isEmpty || positions.isEmpty) {
                setS(() => error = 'ต้องเลือกประเภทเลขและตำแหน่งอย่างน้อย 1 รายการ');
                return;
              }
              final body = <String, dynamic>{
                'nameTh': name.text.trim(),
                'description': desc.text.trim(),
                'allowedDigits': digits.toList()..sort(),
                'allowedPositions': positions.toList(),
                'drawWeekdays': weekdays.toList()..sort(),
                'openTime': open.text.trim(),
                'closeTime': close.text.trim(),
                'resultTime': result.text.trim(),
                'ticketPrice': int.tryParse(price.text) ?? 80,
                'enabled': enabled,
              };
              try {
                if (isNew) {
                  await context.api.createMarket({...body, 'id': id.text.trim(), 'kind': kind});
                } else {
                  await context.api.updateMarket(market.id, {...body, 'expectedVersion': market.version});
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                setS(() => error = '$e');
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    ),
  );
  return saved ?? false;
}

// ============================================================ DRAWS
class LotteryDrawsAdminPage extends StatefulWidget {
  const LotteryDrawsAdminPage({super.key, required this.marketId});
  final String marketId;
  @override
  State<LotteryDrawsAdminPage> createState() => _LotteryDrawsAdminPageState();
}

class _LotteryDrawsAdminPageState extends State<LotteryDrawsAdminPage> {
  String? _status;

  Future<void> _create(BuildContext context, Market m, Future<void> Function() reload) async {
    final date =
        await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100), helpText: 'เลือกวันออกผล');
    if (date == null || !context.mounted) return;
    final open = TextEditingController(text: m.openTime);
    final close = TextEditingController(text: m.closeTime);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('สร้างงวด ${thaiDate(isoDay(date))}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('เวลาเปิด-ปิดรับ (Asia/Bangkok) ของวันออกผล'),
          const SizedBox(height: 10),
          TextField(controller: open, decoration: const InputDecoration(labelText: 'เปิดรับ HH:mm')),
          const SizedBox(height: 10),
          TextField(controller: close, decoration: const InputDecoration(labelText: 'ปิดรับ HH:mm')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('สร้างงวด'))
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (await runAction(context, () => context.api.createDraw(m.id, isoDay(date), openTime: open.text.trim(), closeTime: close.text.trim()),
        success: 'สร้างงวดแล้ว')) {
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = context.session.can('draws.manage');
    return AsyncView<(Market, List<Draw>)>(
      key: ValueKey(_status),
      load: () async {
        final api = context.api;
        final markets = await api.adminMarkets();
        final m = markets.firstWhere((x) => x.id == widget.marketId);
        return (m, await api.adminDraws(marketId: m.id, status: _status));
      },
      builder: (context, data, reload) {
        final (market, draws) = data;
        return PageList(onRefresh: reload, maxWidth: 1200, padding: const EdgeInsets.all(20), children: [
          SectionTitle('จัดการงวด • ${market.nameTh}'),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(onPressed: () => context.go('/admin/lottery'), icon: const Icon(Icons.arrow_back), label: const Text('ทุกประเภท')),
            if (canManage) FilledButton.icon(onPressed: () => _create(context, market, reload), icon: const Icon(Icons.add), label: const Text('เพิ่มงวด')),
            if (canManage && market.weekdays.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () async {
                  final created = <String>[];
                  final ok = await runAction(context, () async => created.addAll(await context.api.createUpcoming(market.id, 7)));
                  if (ok && context.mounted) {
                    toast(context, created.isEmpty ? 'มีงวด 7 วันข้างหน้าครบแล้ว' : 'สร้าง ${created.length} งวด');
                    await reload();
                  }
                },
                icon: const Icon(Icons.event_repeat),
                label: const Text('สร้างงวด 7 วันข้างหน้า'),
              ),
            DropdownButton<String?>(
              value: _status,
              hint: const Text('ทุกสถานะ'),
              items: [
                const DropdownMenuItem(value: null, child: Text('ทุกสถานะ')),
                for (final s in drawStatusTh.entries) DropdownMenuItem(value: s.key, child: Text(s.value))
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ]),
          const SizedBox(height: 12),
          if (draws.isEmpty) const EmptyState('ยังไม่มีงวด'),
          for (final d in draws)
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month, color: LottoColors.primary),
                title: Text('งวด ${thaiDate(d.drawDate)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                    'เปิด ${thaiDateTime(d.opensAt)} • ปิด ${thaiDateTime(d.closesAt)}\nผลที่บันทึก ${d.results.length}/${market.keys.length} ช่อง • v${d.version}'),
                isThreeLine: true,
                trailing:
                    Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [StatusChip.sales(d.salesState), StatusChip.draw(d.status)]),
                onTap: () => context.go('/admin/lottery/result/${d.id}'),
              ),
            ),
        ]);
      },
    );
  }
}

// ============================================================ RESULT EDITOR + WORKFLOW
class LotteryResultEditorPage extends StatefulWidget {
  const LotteryResultEditorPage({super.key, required this.drawId});
  final String drawId;
  @override
  State<LotteryResultEditorPage> createState() => _LotteryResultEditorPageState();
}

class _LotteryResultEditorPageState extends State<LotteryResultEditorPage> {
  final Map<String, TextEditingController> controllers = {};
  final note = TextEditingController();
  final sourceName = TextEditingController();
  final sourceUrl = TextEditingController();
  DateTime? capturedAt;
  Draw? draw;
  Market? market;
  List<Json> history = [];
  Object? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    note.dispose();
    sourceName.dispose();
    sourceUrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = context.api;
      final canAudit = context.session.can('audit.view');
      final d = await api.adminDraw(widget.drawId);
      final h = canAudit ? await api.audit(entityType: 'draw', entityId: widget.drawId) : <Json>[];
      _apply(d);
      setState(() {
        history = h;
        error = null;
      });
    } catch (e) {
      setState(() => error = e);
    }
  }

  void _apply(Draw d) {
    final m = d.market!;
    for (final k in m.keys) {
      (controllers[k] ??= TextEditingController()).text = d.results[k] ?? '';
    }
    note.text = d.sourceNote;
    sourceName.text = d.sourceName ?? '';
    sourceUrl.text = d.sourceUrl ?? '';
    capturedAt = parseDate(d.sourceCapturedAt);
    setState(() {
      draw = d;
      market = m;
    });
  }

  Future<void> _do(Future<Draw> Function() action, String success) async {
    setState(() => busy = true);
    final ok = await runAction(context, () async => _apply(await action()), success: success);
    if (mounted) setState(() => busy = false);
    if (ok) await _load();
    if (!ok && mounted) await _load(); // refresh to show the latest version after conflicts
  }

  String? _validate() {
    final m = market!;
    for (final k in m.keys) {
      final v = controllers[k]!.text.trim();
      final digits = int.parse(k.split(':')[0]);
      if (v.isNotEmpty && !validNumber(v, digits)) return 'ช่อง $digits ตัว${positionTh[k.split(':')[1]]} ต้องเป็นตัวเลข $digits หลัก';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (error != null && draw == null) return ErrorView(error!, onRetry: _load);
    if (draw == null) return const Center(child: CircularProgressIndicator());
    final d = draw!;
    final m = market!;
    final s = context.session;
    final editable = d.isEditable && s.can('results.edit');
    final me = s.user?.id;
    return PageList(maxWidth: 1100, padding: const EdgeInsets.all(20), children: [
      SectionTitle('บันทึกผล • ${m.nameTh}',
          trailing: OutlinedButton.icon(
              onPressed: () => context.go('/admin/lottery/draws/${m.id}'), icon: const Icon(Icons.arrow_back), label: const Text('กลับไปยังงวด'))),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('งวด ${thaiDate(d.drawDate)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        StatusChip.draw(d.status),
        StatusChip.sales(d.salesState),
        StatusChip('v${d.version}', icon: Icons.history, color: LottoColors.navy),
        if (m.isDaily) const StatusChip('DEMO', color: Color(0xFFB7791F), icon: Icons.science_outlined),
        if (m.isExternal)
          StatusChip(d.sourceVerified ? 'ตรวจสอบแหล่งแล้ว' : 'รอตรวจสอบแหล่งประกาศ',
              color: d.sourceVerified ? LottoColors.positive : const Color(0xFFB7791F), icon: Icons.fact_check_outlined),
      ]),
      const SizedBox(height: 4),
      Text('เปิดรับ ${thaiDateTime(d.opensAt)} • ปิดรับ ${thaiDateTime(d.closesAt)}', style: const TextStyle(color: Color(0xFF4A6380))),
      _WorkflowStepper(status: d.status),
      if (d.reviewNote != null && d.reviewNote!.isNotEmpty)
        Card(
            color: const Color(0xFFFFF4D4),
            child: ListTile(leading: const Icon(Icons.comment_outlined), title: const Text('หมายเหตุผู้ตรวจสอบ'), subtitle: Text(d.reviewNote!))),
      if (d.cancelReason != null)
        Card(
            child:
                ListTile(leading: const Icon(Icons.block, color: LottoColors.negative), title: const Text('เหตุผลการยกเลิก'), subtitle: Text(d.cancelReason!))),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.isDaily ? 'ผลหวยรายวัน: กำหนดด้วยตนเองหรือสุ่ม DEMO' : 'ผลหวยภายนอก: บันทึกร่างพร้อมแหล่งอ้างอิง เพื่อรอผู้ตรวจสอบยืนยัน',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final length in m.digits.reversed) ...[
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('เลข $length ตัว', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final position in m.positions)
                    SizedBox(
                      width: constraints.maxWidth < 420 ? (constraints.maxWidth - 10) / 2 : 160,
                      child: TextField(
                        key: Key('result-$length-$position'),
                        controller: controllers[resultKey(length, position)],
                        enabled: editable && !busy,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(length)],
                        decoration: InputDecoration(labelText: '$length ตัว${positionTh[position]}', hintText: '0' * length),
                      ),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            if (m.isExternal) ...[
              const Text('แหล่งประกาศผล (บังคับก่อนส่งตรวจ)', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              TextField(controller: sourceName, enabled: editable, decoration: const InputDecoration(labelText: 'ชื่อแหล่งประกาศ / หน่วยงาน')),
              const SizedBox(height: 8),
              TextField(
                  controller: sourceUrl,
                  enabled: editable,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'URL แหล่งประกาศอย่างเป็นทางการ (https://)')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('เวลาที่บันทึกจากแหล่ง: ${capturedAt == null ? '-' : thaiDateTime(capturedAt)}')),
                TextButton.icon(
                    onPressed: editable ? () => setState(() => capturedAt = DateTime.now()) : null,
                    icon: const Icon(Icons.schedule),
                    label: const Text('ตั้งเป็นเวลาปัจจุบัน')),
              ]),
              const SizedBox(height: 8),
            ],
            TextField(
                controller: note, enabled: editable, maxLines: 2, decoration: InputDecoration(labelText: m.isDaily ? 'หมายเหตุการสุ่ม/กำหนดผล' : 'หมายเหตุ')),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        if (s.can('results.edit') && d.isEditable)
          FilledButton.icon(
            key: const Key('save-draft'),
            onPressed: busy
                ? null
                : () {
                    final err = _validate();
                    if (err != null) return toast(context, err, error: true);
                    _do(
                      () => context.api.saveDraft(
                          d.id,
                          {
                            for (final e in controllers.entries)
                              if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()
                          },
                          version: d.version,
                          sourceNote: note.text.trim(),
                          sourceName: m.isExternal ? sourceName.text.trim() : null,
                          sourceUrl: m.isExternal ? sourceUrl.text.trim() : null,
                          sourceCapturedAt: m.isExternal ? capturedAt?.toUtc().toIso8601String() : null),
                      'บันทึกร่างแล้ว',
                    );
                  },
            icon: const Icon(Icons.save),
            label: const Text('บันทึกร่าง'),
          ),
        if (m.isDaily && s.can('results.edit') && d.isEditable)
          OutlinedButton.icon(
            key: const Key('generate-demo'),
            onPressed: busy ? null : () => _do(() => context.api.generateDemo(d.id), 'สุ่มผล DEMO และบันทึกร่างแล้ว'),
            icon: const Icon(Icons.casino_outlined),
            label: const Text('สุ่มผล DEMO'),
          ),
        if (s.can('results.edit') && d.status == 'DRAFT')
          FilledButton.tonalIcon(
            key: const Key('submit'),
            onPressed: busy ? null : () => _do(() => context.api.drawAction(d.id, 'submit', version: d.version), 'ส่งตรวจสอบแล้ว'),
            icon: const Icon(Icons.send),
            label: const Text('ส่งตรวจสอบ'),
          ),
        if (s.can('results.review') && d.status == 'AWAITING_REVIEW') ...[
          FilledButton.icon(
            key: const Key('approve'),
            onPressed: busy || (m.isExternal && d.submittedById == me)
                ? null
                : () async {
                    final n = await promptText(context, m.isExternal ? 'ยืนยันว่าตรวจสอบกับแหล่งประกาศแล้ว' : 'อนุมัติผล',
                        label: 'หมายเหตุการตรวจสอบ', required: false);
                    if (n != null) await _do(() => context.api.drawAction(d.id, 'approve', version: d.version, note: n), 'อนุมัติแล้ว');
                  },
            icon: const Icon(Icons.verified),
            label: Text(m.isExternal && d.submittedById == me ? 'อนุมัติ (ต้องเป็นผู้ตรวจคนอื่น)' : 'อนุมัติ'),
          ),
        ],
        if (s.can('results.review') && (d.status == 'AWAITING_REVIEW' || d.status == 'APPROVED'))
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final n = await promptText(context, 'ส่งกลับแก้ไข', label: 'เหตุผล');
                    if (n != null) await _do(() => context.api.drawAction(d.id, 'reject', version: d.version, note: n), 'ส่งกลับแก้ไขแล้ว');
                  },
            icon: const Icon(Icons.undo),
            label: const Text('ส่งกลับแก้ไข'),
          ),
        if (s.can('results.publish') && d.status == 'APPROVED')
          FilledButton.icon(
            key: const Key('publish'),
            style: FilledButton.styleFrom(backgroundColor: LottoColors.positive, foregroundColor: Colors.white),
            onPressed: busy
                ? null
                : () async {
                    if (await confirmDialog(context, 'เผยแพร่ผล', 'เมื่อเผยแพร่แล้วจะแก้ไขไม่ได้ (ล็อกถาวร) ยืนยันหรือไม่?', ok: 'เผยแพร่')) {
                      await _do(() => context.api.drawAction(d.id, 'publish', version: d.version), 'เผยแพร่ผลแล้ว (ล็อกการแก้ไข)');
                    }
                  },
            icon: const Icon(Icons.publish),
            label: const Text('เผยแพร่ผล'),
          ),
        if (s.can('draws.manage') && !d.isLocked)
          TextButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final n = await promptText(context, 'ยกเลิกงวด', label: 'เหตุผลการยกเลิก');
                    if (n != null) await _do(() => context.api.drawAction(d.id, 'cancel', version: d.version, note: n), 'ยกเลิกงวดแล้ว');
                  },
            icon: const Icon(Icons.block, color: LottoColors.negative),
            label: const Text('ยกเลิกงวด', style: TextStyle(color: LottoColors.negative)),
          ),
      ]),
      if (d.isLocked)
        const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('งวดนี้ถูกล็อกแล้ว ไม่สามารถแก้ไขผลได้ (การแก้ไขภายหลังต้องทำผ่านกระบวนการ correction แยกต่างหาก)',
                style: TextStyle(color: LottoColors.negative))),
      if (m.isExternal)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('หวยลาว / เวียดนาม / ไทย: ต้องระบุแหล่งประกาศ และผู้อนุมัติต้องเป็นคนละคนกับผู้ส่งตรวจ ห้ามสุ่มผล',
              style: TextStyle(color: Color(0xFFB7791F))),
        ),
      if (history.isNotEmpty) ...[
        const SectionTitle('ประวัติการเปลี่ยนแปลง (Audit)'),
        Card(
          child: Column(children: [
            for (final h in history)
              ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, color: LottoColors.primary),
                  title: Text('${h['action']} • ${h['actor']}'),
                  subtitle: Text(thaiDateTime(h['timestamp']))),
          ]),
        ),
      ],
    ]);
  }
}

class _WorkflowStepper extends StatelessWidget {
  const _WorkflowStepper({required this.status});
  final String status;
  static const steps = ['SCHEDULED', 'DRAFT', 'AWAITING_REVIEW', 'APPROVED', 'PUBLISHED'];
  @override
  Widget build(BuildContext context) {
    final idx = steps.indexOf(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (var i = 0; i < steps.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: status == 'CANCELLED'
                  ? LottoColors.border
                  : i <= idx
                      ? LottoColors.primary
                      : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: LottoColors.primary.withValues(alpha: 0.4)),
            ),
            child: Text('${i + 1}. ${drawStatusTh[steps[i]]}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i <= idx && status != 'CANCELLED' ? Colors.white : LottoColors.navy)),
          ),
          if (i < steps.length - 1) const Icon(Icons.chevron_right, size: 16, color: LottoColors.primary),
        ],
      ]),
    );
  }
}

// ============================================================ LOTTERY AUDIT
class LotteryAuditPage extends StatelessWidget {
  const LotteryAuditPage({super.key});
  @override
  Widget build(BuildContext context) => AsyncView<(List<Json>, List<Json>)>(
        load: () async {
          final api = context.api;
          return (await api.audit(entityType: 'draw', take: 300), await api.audit(entityType: 'market', take: 100));
        },
        builder: (context, data, reload) {
          final all = [...data.$1, ...data.$2]..sort((a, b) => '${b['timestamp']}'.compareTo('${a['timestamp']}'));
          return PageList(onRefresh: reload, maxWidth: 1100, padding: const EdgeInsets.all(20), children: [
            const SectionTitle('ประวัติการจัดการงวดและผล'),
            if (all.isEmpty) const EmptyState('ยังไม่มีการเปลี่ยนแปลง'),
            for (final e in all)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history, color: LottoColors.primary),
                  title: Text('${e['action']} • ${e['entityType']}'),
                  subtitle: Text('${e['actor']} • ${thaiDateTime(e['timestamp'])}\n${e['entityId']}'),
                  isThreeLine: true,
                  onTap: e['entityType'] == 'draw' ? () => context.go('/admin/lottery/result/${e['entityId']}') : null,
                ),
              ),
          ]);
        },
      );
}
