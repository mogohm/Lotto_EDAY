import 'api_client.dart';
import 'models.dart';

/// Repository: every screen talks to the backend through this class (no mock data).
class LottoApi {
  LottoApi(this.client);
  final ApiClient client;

  // ---- auth
  Future<Json> login(String email, String password) async => jsonMap(await client.post('/auth/login', {'email': email, 'password': password}));
  Future<Json> register({required String email, required String password, required String displayName, String? phone}) async => jsonMap(await client
      .post('/auth/register', {'email': email, 'password': password, 'displayName': displayName, if (phone != null && phone.isNotEmpty) 'phone': phone}));
  Future<AppUser> me() async => AppUser(jsonMap(await client.get('/auth/me')));
  Future<AppUser> updateProfile({String? displayName, String? phone}) async => AppUser(
      jsonMap(await client.patch('/auth/me', {if (displayName != null) 'displayName': displayName, if (phone != null && phone.isNotEmpty) 'phone': phone})));
  Future<Json> changePassword(String current, String next) async =>
      jsonMap(await client.post('/auth/change-password', {'currentPassword': current, 'newPassword': next}));
  Future<Json> config() async => jsonMap(await client.get('/config'));

  // ---- public lottery
  Future<List<Market>> markets() async => jsonList(await client.get('/lottery/markets')).map(Market.new).toList();
  Future<List<Draw>> publicDraws({String? marketId}) async =>
      jsonList(await client.get('/lottery/draws', query: {'marketId': marketId})).map(Draw.new).toList();
  Future<List<Draw>> published({String? marketId}) async =>
      jsonList(await client.get('/lottery/published', query: {'marketId': marketId})).map(Draw.new).toList();
  Future<Json> check(String number, {String? drawId, String? marketId}) async =>
      jsonMap(await client.get('/lottery/check', query: {'number': number, 'drawId': drawId, 'marketId': marketId}));

  // ---- catalog / cart / orders
  Future<List<Json>> catalogDraws() async => jsonList(await client.get('/catalog/draws'));
  Future<PageResult<Ticket>> tickets({String? drawId, String? number, int page = 1, int pageSize = 20}) async {
    final r = jsonMap(await client.get('/catalog/tickets', query: {'drawId': drawId, 'number': number, 'page': page, 'pageSize': pageSize}));
    return PageResult(r['total'] as int, r['page'] as int, jsonList(r['items']).map(Ticket.new).toList());
  }

  Future<Ticket> ticket(String id) async => Ticket(jsonMap(await client.get('/catalog/tickets/$id')));
  Future<Json> cart() async => jsonMap(await client.get('/cart'));
  Future<Json> addToCart(String ticketId) async => jsonMap(await client.post('/cart', {'ticketId': ticketId}));
  Future<Json> removeFromCart(String ticketId) async => jsonMap(await client.delete('/cart/$ticketId'));
  Future<Json> checkout() async => jsonMap(await client.post('/orders/checkout'));
  Future<List<Json>> orders({String? status}) async => jsonList(await client.get('/orders', query: {'status': status}));
  Future<Json> order(String id) async => jsonMap(await client.get('/orders/$id'));
  Future<List<Json>> myTickets() async => jsonList(await client.get('/my-tickets'));
  Future<Json> summary() async => jsonMap(await client.get('/me/summary'));

  // ---- wallet (simulated)
  Future<Json> wallet() async => jsonMap(await client.get('/wallet'));
  Future<List<Json>> walletTransactions({String? type}) async => jsonList(await client.get('/wallet/transactions', query: {'type': type}));
  Future<Json> topup(int amount) async => jsonMap(await client.post('/wallet/topup', {'amount': amount}));
  Future<Json> withdraw(int amount) async => jsonMap(await client.post('/wallet/withdraw', {'amount': amount}));

  // ---- notifications / news
  Future<List<Json>> notifications() async => jsonList(await client.get('/notifications'));
  Future<void> markAllRead() async => client.post('/notifications/read-all');
  Future<void> markRead(String id) async => client.post('/notifications/$id/read');
  Future<List<Json>> announcements() async => jsonList(await client.get('/announcements'));

  // ---- admin: lottery
  Future<List<Market>> adminMarkets() async => jsonList(await client.get('/admin/lottery/markets')).map(Market.new).toList();
  Future<Market> createMarket(Json body) async => Market(jsonMap(await client.post('/admin/lottery/markets', body)));
  Future<Market> updateMarket(String id, Json body) async => Market(jsonMap(await client.patch('/admin/lottery/markets/$id', body)));
  Future<List<Draw>> adminDraws({String? marketId, String? status, String? from, String? to}) async =>
      jsonList(await client.get('/admin/lottery/draws', query: {'marketId': marketId, 'status': status, 'from': from, 'to': to})).map(Draw.new).toList();
  Future<Draw> adminDraw(String id) async => Draw(jsonMap(await client.get('/admin/lottery/draws/$id')));
  Future<Draw> createDraw(String marketId, String date, {String? openTime, String? closeTime}) async => Draw(jsonMap(await client.post('/admin/lottery/draws', {
        'marketId': marketId,
        'date': date,
        if (openTime != null) 'openTime': openTime,
        if (closeTime != null) 'closeTime': closeTime,
      })));
  Future<List<String>> createUpcoming(String marketId, int days) async =>
      ((jsonMap(await client.post('/admin/lottery/draws/bulk', {'marketId': marketId, 'days': days}))['created'] as List?) ?? []).map((e) => '$e').toList();
  Future<Draw> updateSchedule(String id, {String? opensAt, String? closesAt, required int version}) async => Draw(jsonMap(await client.patch(
      '/admin/lottery/draws/$id/schedule', {if (opensAt != null) 'opensAt': opensAt, if (closesAt != null) 'closesAt': closesAt, 'expectedVersion': version})));
  Future<Draw> saveDraft(String id, Map<String, String> results,
          {required int version, String? sourceNote, String? sourceName, String? sourceUrl, String? sourceCapturedAt}) async =>
      Draw(jsonMap(await client.patch('/admin/lottery/draws/$id/draft', {
        'results': results,
        'expectedVersion': '$version',
        'sourceNote': sourceNote ?? '',
        if (sourceName != null) 'sourceName': sourceName,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        if (sourceCapturedAt != null) 'sourceCapturedAt': sourceCapturedAt,
      })));
  Future<Draw> generateDemo(String id) async => Draw(jsonMap(await client.post('/admin/lottery/draws/$id/generate-demo')));
  Future<Draw> drawAction(String id, String action, {int? version, String? note}) async =>
      Draw(jsonMap(await client.post('/admin/lottery/draws/$id/$action', {if (version != null) 'expectedVersion': version, if (note != null) 'note': note})));

  // ---- admin: other modules
  Future<Json> dashboard() async => jsonMap(await client.get('/admin/dashboard'));
  Future<Json> users({String? q, String? role, String? status, int page = 1}) async =>
      jsonMap(await client.get('/admin/users', query: {'q': q, 'role': role, 'status': status, 'page': page}));
  Future<Json> createUser(Json body) async => jsonMap(await client.post('/admin/users', body));
  Future<Json> updateUser(String id, Json body) async => jsonMap(await client.patch('/admin/users/$id', body));
  Future<Json> roles() async => jsonMap(await client.get('/admin/roles'));
  Future<Json> adminTickets({String? drawId, String? status, String? number, int page = 1}) async =>
      jsonMap(await client.get('/admin/tickets', query: {'drawId': drawId, 'status': status, 'number': number, 'page': page}));
  Future<int> generateTickets(String drawId, int count, {int? price}) async =>
      (jsonMap(await client.post('/admin/tickets/generate', {'drawId': drawId, 'count': count, if (price != null) 'price': price}))['created'] ?? 0) as int;
  Future<void> setTicketStatus(String id, String status) async => client.patch('/admin/tickets/$id', {'status': status});
  Future<Json> adminOrders({String? q, String? status, String? from, String? to, int page = 1}) async =>
      jsonMap(await client.get('/admin/orders', query: {'q': q, 'status': status, 'from': from, 'to': to, 'page': page}));
  Future<void> cancelOrder(String id, String note) async => client.post('/admin/orders/$id/cancel', {'note': note});
  Future<List<Json>> withdrawals({String? status}) async => jsonList(await client.get('/admin/withdrawals', query: {'status': status}));
  Future<void> decideWithdrawal(String id, bool approve) async => client.post('/admin/withdrawals/$id/${approve ? 'approve' : 'reject'}');
  Future<List<Json>> adminAnnouncements() async => jsonList(await client.get('/admin/announcements'));
  Future<Json> saveAnnouncement(String? id, Json body) async =>
      jsonMap(id == null ? await client.post('/admin/announcements', body) : await client.patch('/admin/announcements/$id', body));
  Future<void> deleteAnnouncement(String id) async => client.delete('/admin/announcements/$id');
  Future<Json> reportSummary() async => jsonMap(await client.get('/admin/reports/summary'));
  Future<String> reportCsv(String type) => client.getText('/admin/reports/$type.csv');
  Future<Json> settings() async => jsonMap(await client.get('/admin/settings'));
  Future<Json> updateSettings(Json values) async => jsonMap(await client.patch('/admin/settings', {'values': values}));
  Future<List<Json>> audit({String? action, String? entityType, String? entityId, String? actor, String? from, String? to, int take = 200}) async =>
      jsonList(await client.get('/admin/audit',
          query: {'action': action, 'entityType': entityType, 'entityId': entityId, 'actor': actor, 'from': from, 'to': to, 'take': take}));
  Future<Json> verifyAudit() async => jsonMap(await client.get('/admin/audit/verify'));
}
