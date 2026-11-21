import 'dart:math';
import 'package:flutter/foundation.dart';

enum LotteryKind { daily, lao, vietnam, thai }

enum DrawState { scheduled, draft, published, cancelled }

enum ResultSource { internalDemo, externalUnverified, officialVerified }

enum NumberPosition { front, back, top, bottom }

extension PositionLabel on NumberPosition {
  String get thaiLabel => switch (this) {
        NumberPosition.front => 'หน้า',
        NumberPosition.back => 'หลัง',
        NumberPosition.top => 'บน',
        NumberPosition.bottom => 'ล่าง',
      };
}

class LotteryMarket {
  const LotteryMarket(
      {required this.id,
      required this.name,
      required this.kind,
      required this.digits,
      required this.positions,
      required this.resultSource,
      this.enabled = true});
  final String id;
  final String name;
  final LotteryKind kind;
  final Set<int> digits;
  final Set<NumberPosition> positions;
  final ResultSource resultSource;
  final bool enabled;
}

class LotteryDraw {
  LotteryDraw(
      {required this.id,
      required this.marketId,
      required this.drawDate,
      this.status = DrawState.scheduled,
      Map<String, String>? results,
      this.sourceNote = '',
      this.publishedAt});
  final String id;
  final String marketId;
  final DateTime drawDate;
  DrawState status;
  final Map<String, String> results = {};
  String sourceNote;
  DateTime? publishedAt;
}

class LotteryAudit {
  const LotteryAudit(this.timestamp, this.action, this.detail);
  final DateTime timestamp;
  final String action;
  final String detail;
}

/// UI DEMO ONLY. Never use this in-memory store as a production result authority.
/// Production: authenticated server, locked draws, immutable audit, two-person approval.
class LotteryDemoStore extends ChangeNotifier {
  LotteryDemoStore._() {
    final now = DateTime.now();
    for (final market in markets) {
      draws.add(LotteryDraw(
          id: '${market.id}-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}',
          marketId: market.id,
          drawDate: DateTime(now.year, now.month, now.day)));
    }
  }
  static final LotteryDemoStore instance = LotteryDemoStore._();
  final markets = const [
    LotteryMarket(
        id: 'daily',
        name: 'หวยรายวัน • จำลอง',
        kind: LotteryKind.daily,
        digits: {2, 3, 4},
        positions: {NumberPosition.front, NumberPosition.back, NumberPosition.top, NumberPosition.bottom},
        resultSource: ResultSource.internalDemo),
    LotteryMarket(
        id: 'lao',
        name: 'หวยลาว',
        kind: LotteryKind.lao,
        digits: {2, 3, 4},
        positions: {NumberPosition.front, NumberPosition.back, NumberPosition.top, NumberPosition.bottom},
        resultSource: ResultSource.externalUnverified),
    LotteryMarket(
        id: 'vietnam',
        name: 'หวยเวียดนาม',
        kind: LotteryKind.vietnam,
        digits: {2, 3, 4},
        positions: {NumberPosition.front, NumberPosition.back, NumberPosition.top, NumberPosition.bottom},
        resultSource: ResultSource.externalUnverified),
    LotteryMarket(
        id: 'thai',
        name: 'หวยไทย',
        kind: LotteryKind.thai,
        digits: {2, 3, 4},
        positions: {NumberPosition.front, NumberPosition.back, NumberPosition.top, NumberPosition.bottom},
        resultSource: ResultSource.externalUnverified),
  ];
  final List<LotteryDraw> draws = [];
  final List<LotteryAudit> audit = [];
  LotteryMarket market(String id) => markets.firstWhere((m) => m.id == id);
  List<LotteryDraw> forMarket(String id) => draws.where((d) => d.marketId == id).toList()..sort((a, b) => b.drawDate.compareTo(a.drawDate));

  static String key(int digits, NumberPosition position) => '$digits:${position.name}';
  static bool validNumber(String value, int digits) => RegExp('^[0-9]{$digits}\$').hasMatch(value);

  void createDraw(String marketId, DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    if (draws.any((d) => d.marketId == marketId && d.drawDate == date)) {
      throw StateError('มีงวดของวันที่เลือกอยู่แล้ว');
    }
    final id = '$marketId-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    draws.add(LotteryDraw(id: id, marketId: marketId, drawDate: date));
    _log('CREATE_DRAW', id);
  }

  void saveDraft(LotteryDraw draw, Map<String, String> values, {String sourceNote = ''}) {
    if (draw.status == DrawState.published || draw.status == DrawState.cancelled) {
      throw StateError('งวดนี้ไม่อนุญาตให้แก้ไข');
    }
    final m = market(draw.marketId);
    for (final entry in values.entries) {
      final split = entry.key.split(':');
      if (split.length != 2) throw FormatException('Invalid key');
      final digits = int.tryParse(split[0]);
      final position = NumberPosition.values.where((v) => v.name == split[1]).firstOrNull;
      if (digits == null || !m.digits.contains(digits) || position == null || !m.positions.contains(position)) {
        throw FormatException('ประเภทเลขไม่รองรับ: ${entry.key}');
      }
      if (entry.value.isNotEmpty && !validNumber(entry.value, digits)) {
        throw FormatException('เลข ${entry.key} ต้องมี $digits หลัก');
      }
    }
    draw.results
      ..clear()
      ..addAll(values..removeWhere((_, v) => v.isEmpty));
    draw.sourceNote = sourceNote.trim();
    draw.status = DrawState.draft;
    _log('SAVE_DRAFT', draw.id);
  }

  void generateDailyDemo(LotteryDraw draw) {
    if (market(draw.marketId).kind != LotteryKind.daily) throw StateError('สุ่มได้เฉพาะหวยรายวันสาธิต');
    if (draw.status == DrawState.published || draw.status == DrawState.cancelled) throw StateError('งวดนี้ถูกล็อก');
    final random = Random.secure();
    final values = <String, String>{};
    final marketConfig = market(draw.marketId);
    for (final length in marketConfig.digits) {
      for (final position in marketConfig.positions) {
        values[key(length, position)] = List.generate(length, (_) => random.nextInt(10)).join();
      }
    }
    saveDraft(draw, values, sourceNote: 'ผลสุ่มทดลองอัตโนมัติ ไม่ใช่ผลรางวัลเงินจริง');
    _log('GENERATE_DEMO', draw.id);
  }

  void publishDemo(LotteryDraw draw) {
    if (draw.status != DrawState.draft || draw.results.isEmpty) throw StateError('ต้องบันทึกผลร่างก่อน');
    if (market(draw.marketId).kind != LotteryKind.daily) {
      throw StateError('หวยภายนอกต้องยืนยันแหล่งผลอย่างเป็นทางการผ่าน Backend ก่อนเผยแพร่');
    }
    draw.status = DrawState.published;
    draw.publishedAt = DateTime.now();
    _log('PUBLISH_DEMO', draw.id);
  }

  void _log(String action, String detail) {
    audit.insert(0, LotteryAudit(DateTime.now(), action, detail));
    notifyListeners();
  }
}
