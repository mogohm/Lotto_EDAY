/// Typed views over API JSON. Numbers are kept as text where leading zeros matter.
library;

typedef Json = Map<String, dynamic>;

List<Json> jsonList(dynamic v) => v is List ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Json>[];
Json jsonMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
Map<String, String> stringMap(dynamic v) => v is Map ? v.map((k, val) => MapEntry('$k', '$val')) : <String, String>{};

const positionOrder = ['front', 'back', 'top', 'bottom'];
const positionTh = {'front': 'หน้า', 'back': 'หลัง', 'top': 'บน', 'bottom': 'ล่าง'};
const kindTh = {'DAILY': 'หวยรายวัน', 'LAO': 'หวยลาว', 'VIETNAM': 'หวยเวียดนาม', 'THAI': 'หวยไทย'};

const drawStatusTh = {
  'SCHEDULED': 'ตั้งเวลาแล้ว',
  'DRAFT': 'ร่างผล',
  'AWAITING_REVIEW': 'รอตรวจสอบ',
  'APPROVED': 'อนุมัติแล้ว',
  'PUBLISHED': 'เผยแพร่แล้ว',
  'CANCELLED': 'ยกเลิก',
};
const salesStateTh = {'UPCOMING': 'ยังไม่เปิดขาย', 'OPEN': 'เปิดรับ', 'CLOSED': 'ปิดรับแล้ว'};
const roleTh = {
  'SUPER_ADMIN': 'ผู้ดูแลสูงสุด',
  'ADMIN': 'ผู้ดูแลระบบ',
  'RESULT_EDITOR': 'ผู้บันทึกผล',
  'REVIEWER': 'ผู้ตรวจสอบ/อนุมัติ',
  'AUDITOR': 'ผู้ตรวจสอบบัญชี',
  'USER': 'สมาชิก',
};
const kycTh = {'NONE': 'ยังไม่ยืนยันตัวตน', 'PENDING': 'รอตรวจสอบ KYC', 'VERIFIED': 'ยืนยันตัวตนแล้ว', 'REJECTED': 'KYC ไม่ผ่าน'};
const txTypeTh = {
  'TOPUP_DEMO': 'เติมเงิน (จำลอง)',
  'WITHDRAW_DEMO': 'ถอนเงิน (จำลอง)',
  'PURCHASE_DEMO': 'ซื้อสลาก',
  'REFUND_DEMO': 'คืนเครดิต',
  'ADJUSTMENT_DEMO': 'ปรับยอด',
};
const txStatusTh = {'SUCCESS': 'สำเร็จ', 'PENDING': 'รอดำเนินการ', 'REJECTED': 'ไม่อนุมัติ'};

String resultKey(int digits, String position) => '$digits:$position';
bool validNumber(String value, int digits) => RegExp('^[0-9]{$digits}\$').hasMatch(value);

class AppUser {
  AppUser(this.j);
  final Json j;
  String get id => j['id'] as String;
  String get email => j['email'] as String;
  String get displayName => (j['displayName'] ?? '') as String;
  String? get phone => j['phone'] as String?;
  String get role => (j['role'] ?? 'USER') as String;
  String get status => (j['status'] ?? 'ACTIVE') as String;
  String get kycStatus => (j['kycStatus'] ?? 'NONE') as String;
  int get demoBalance => (j['demoBalance'] ?? 0) as int;
  List<String> get permissions => (j['permissions'] as List? ?? const []).map((e) => '$e').toList();
  bool get isStaff => role != 'USER';
  bool can(String p) => permissions.contains(p);
}

class Market {
  Market(this.j);
  final Json j;
  String get id => j['id'] as String;
  String get nameTh => (j['nameTh'] ?? '') as String;
  String get kind => (j['kind'] ?? 'DAILY') as String;
  String get description => (j['description'] ?? '') as String;
  String get source => (j['source'] ?? '') as String;
  bool get enabled => (j['enabled'] ?? true) as bool;
  bool get isDaily => kind == 'DAILY';
  bool get isExternal => !isDaily;
  List<int> get digits => ((j['allowedDigits'] as List?) ?? const []).map((e) => (e as num).toInt()).toList()..sort();
  List<String> get positions {
    final p = ((j['allowedPositions'] as List?) ?? const []).map((e) => '$e').toList();
    p.sort((a, b) => positionOrder.indexOf(a).compareTo(positionOrder.indexOf(b)));
    return p;
  }

  String get openTime => (j['openTime'] ?? '06:00') as String;
  String get closeTime => (j['closeTime'] ?? '15:30') as String;
  String get resultTime => (j['resultTime'] ?? '16:00') as String;
  List<int> get weekdays => ((j['drawWeekdays'] as List?) ?? const []).map((e) => (e as num).toInt()).toList();
  int get ticketPrice => (j['ticketPrice'] ?? 80) as int;
  int get version => (j['version'] ?? 1) as int;
  List<String> get keys => [
        for (final d in digits)
          for (final p in positions) resultKey(d, p)
      ];
}

class Draw {
  Draw(this.j);
  final Json j;
  String get id => j['id'] as String;
  String get marketId => j['marketId'] as String;
  String get drawDate => (j['drawDate'] ?? '') as String;
  String get status => (j['status'] ?? 'SCHEDULED') as String;
  String get salesState => (j['salesState'] ?? 'CLOSED') as String;
  Map<String, String> get results => stringMap(j['results']);
  int get version => (j['version'] ?? 1) as int;
  String? get opensAt => j['opensAt'] as String?;
  String? get closesAt => j['closesAt'] as String?;
  String get sourceNote => (j['sourceNote'] ?? '') as String;
  String? get sourceName => j['sourceName'] as String?;
  String? get sourceUrl => j['sourceUrl'] as String?;
  String? get sourceCapturedAt => j['sourceCapturedAt'] as String?;
  bool get sourceVerified => (j['sourceVerified'] ?? false) as bool;
  String? get reviewNote => j['reviewNote'] as String?;
  String? get approvedBy => j['approvedBy'] as String?;
  String? get publishedAt => j['publishedAt'] as String?;
  String? get submittedById => j['submittedById'] as String?;
  String? get cancelReason => j['cancelReason'] as String?;
  Market? get market => j['market'] is Map ? Market(jsonMap(j['market'])) : null;
  bool get isPublished => status == 'PUBLISHED';
  bool get isLocked => status == 'PUBLISHED' || status == 'CANCELLED';
  bool get isEditable => status == 'SCHEDULED' || status == 'DRAFT';
}

class Ticket {
  Ticket(this.j);
  final Json j;
  String get id => j['id'] as String;
  String get number => j['number'] as String;
  int get price => (j['price'] ?? 0) as int;
  String get status => (j['status'] ?? '') as String;
  String get drawId => (j['drawId'] ?? '') as String;
  String get drawDate => (j['drawDate'] ?? '') as String;
  String get marketName => (j['marketName'] ?? '') as String;
  String get salesState => (j['salesState'] ?? '') as String;
  String? get closesAt => j['closesAt'] as String?;
  String? get problem => j['problem'] as String?;
}

class PageResult<T> {
  PageResult(this.total, this.page, this.items);
  final int total;
  final int page;
  final List<T> items;
}
