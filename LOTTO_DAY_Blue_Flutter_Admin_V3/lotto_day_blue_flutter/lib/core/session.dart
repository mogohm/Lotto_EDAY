import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'api/lotto_api.dart';
import 'api/models.dart';

/// Holds the signed-in user + small cross-screen counters (cart, unread).
/// Token is kept in memory and in local storage; the server revokes it via token versioning.
class Session extends ChangeNotifier {
  Session(this.api, {SharedPreferences? prefs}) : _prefs = prefs {
    api.client.onUnauthorized = () {
      if (user != null) _clear();
    };
  }

  static const _tokenKey = 'lotto_day_token';
  final LottoApi api;
  SharedPreferences? _prefs;
  AppUser? user;
  bool restoring = true;
  int cartCount = 0;
  int unread = 0;

  bool get isLoggedIn => user != null;
  bool get isStaff => user?.isStaff ?? false;
  bool can(String permission) => user?.can(permission) ?? false;

  Future<SharedPreferences?> _store() async {
    try {
      return _prefs ??= await SharedPreferences.getInstance();
    } catch (_) {
      return null; // private mode / blocked storage: session stays in memory only
    }
  }

  Future<void> restore() async {
    try {
      final token = (await _store())?.getString(_tokenKey);
      if (token != null) {
        api.client.token = token;
        user = await api.me();
        await refreshCounters();
      }
    } catch (_) {
      api.client.token = null;
      user = null;
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<void> _accept(Json auth) async {
    api.client.token = auth['accessToken'] as String;
    user = AppUser(jsonMap(auth['user']));
    await (await _store())?.setString(_tokenKey, api.client.token!);
    await refreshCounters();
    notifyListeners();
  }

  Future<void> login(String email, String password) async => _accept(await api.login(email.trim(), password));

  Future<void> register({required String email, required String password, required String displayName, String? phone}) async =>
      _accept(await api.register(email: email.trim(), password: password, displayName: displayName.trim(), phone: phone));

  Future<void> changePassword(String current, String next) async => _accept(await api.changePassword(current, next));

  Future<void> reloadUser() async {
    user = await api.me();
    notifyListeners();
  }

  Future<void> refreshCounters() async {
    if (user == null) return;
    try {
      final cart = await api.cart();
      cartCount = (cart['count'] ?? 0) as int;
      final s = await api.summary();
      unread = (s['unread'] ?? 0) as int;
      if (user != null) user!.j['demoBalance'] = s['balance'];
    } catch (_) {}
    notifyListeners();
  }

  void setCartCount(int n) {
    cartCount = n;
    notifyListeners();
  }

  Future<void> logout() async {
    await (await _store())?.remove(_tokenKey);
    _clear();
  }

  void _clear() {
    api.client.token = null;
    user = null;
    cartCount = 0;
    unread = 0;
    notifyListeners();
  }
}

/// Makes [Session] (and its [LottoApi]) available to the widget tree.
class AppScope extends InheritedNotifier<Session> {
  const AppScope({super.key, required Session session, required super.child}) : super(notifier: session);

  static Session of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static Session read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension SessionContext on BuildContext {
  Session get session => AppScope.read(this);
  LottoApi get api => AppScope.read(this).api;
}

ApiClient createClient() => ApiClient();
