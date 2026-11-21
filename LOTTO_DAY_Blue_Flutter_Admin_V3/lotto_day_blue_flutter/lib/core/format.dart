/// Thai-first formatting helpers (Buddhist Era years, Asia/Bangkok wall clock).
library;

const thaiMonths = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];
const thaiMonthsShort = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
const thaiWeekdays = ['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์'];
const thaiWeekdaysShort = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

/// Converts any instant to Bangkok wall-clock (UTC+7, no DST).
DateTime toBangkok(DateTime t) => t.toUtc().add(const Duration(hours: 7));

DateTime? parseDate(dynamic v) => v == null ? null : DateTime.tryParse('$v');

/// '2026-11-21' → '21 พฤศจิกายน 2569'
String thaiDate(dynamic isoOrDate, {bool short = false}) {
  if (isoOrDate == null) return '-';
  DateTime d;
  if (isoOrDate is DateTime) {
    d = toBangkok(isoOrDate);
  } else {
    final s = '$isoOrDate';
    if (s.length == 10) {
      d = DateTime.parse('${s}T00:00:00Z');
    } else {
      final p = DateTime.tryParse(s);
      if (p == null) return s;
      d = toBangkok(p);
    }
  }
  final m = short ? thaiMonthsShort[d.month - 1] : thaiMonths[d.month - 1];
  final y = d.year + 543;
  return '${d.day} $m ${short ? (y % 100).toString().padLeft(2, '0') : y}';
}

/// ISO datetime → '21 พ.ย. 69 14:00 น.'
String thaiDateTime(dynamic iso) {
  final p = iso is DateTime ? iso : parseDate(iso);
  if (p == null) return '-';
  final b = toBangkok(p);
  return '${thaiDate(p, short: true)} ${b.hour.toString().padLeft(2, '0')}:${b.minute.toString().padLeft(2, '0')} น.';
}

String hhmm(dynamic iso) {
  final p = parseDate(iso);
  if (p == null) return '-';
  final b = toBangkok(p);
  return '${b.hour.toString().padLeft(2, '0')}:${b.minute.toString().padLeft(2, '0')}';
}

/// 1245600 → '1,245,600'
String money(num? v) {
  if (v == null) return '0';
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

String baht(num? v) => '${money(v)} บาท';

/// '0812341234' → '081-xxx-1234'
String maskPhone(String? p) {
  if (p == null || p.length < 9) return p ?? '-';
  return '${p.substring(0, 3)}-xxx-${p.substring(p.length - 4)}';
}

/// Bangkok calendar date 'YYYY-MM-DD' for a local DateTime picked in a date picker.
String isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
