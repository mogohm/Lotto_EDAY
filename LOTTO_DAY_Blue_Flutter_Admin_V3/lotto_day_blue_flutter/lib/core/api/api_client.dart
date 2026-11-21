import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Error returned by the LOTTO DAY API (or a network failure, status 0).
class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  bool get isUnauthorized => status == 401;
  bool get isConflict => status == 409;
  @override
  String toString() => message;
}

/// Resolves the API base URL:
/// 1. `--dart-define=API_BASE_URL=...` when provided;
/// 2. same origin `/api/v1` on the web (production: NestJS serves the Flutter build);
/// 3. `http://localhost:3000/api/v1` elsewhere.
String defaultApiBaseUrl() {
  const fromEnv = String.fromEnvironment('API_BASE_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (kIsWeb) return '${Uri.base.origin}/api/v1';
  return 'http://localhost:3000/api/v1';
}

/// Thin JSON REST client with bearer auth, timeouts and Thai error messages.
class ApiClient {
  ApiClient({String? baseUrl, http.Client? client, this.timeout = const Duration(seconds: 20)})
      : baseUrl = (baseUrl ?? defaultApiBaseUrl()).replaceAll(RegExp(r'/$'), ''),
        _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  final Duration timeout;
  String? token;

  /// Called when any request returns 401 (expired/revoked session).
  void Function()? onUnauthorized;

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) q[k] = '$v';
    });
    return Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send(() => _http.get(uri(path, query), headers: _headers));
  Future<dynamic> post(String path, [Object? body]) => _send(() => _http.post(uri(path), headers: _headers, body: jsonEncode(body ?? {})));
  Future<dynamic> patch(String path, [Object? body]) => _send(() => _http.patch(uri(path), headers: _headers, body: jsonEncode(body ?? {})));
  Future<dynamic> delete(String path) => _send(() => _http.delete(uri(path), headers: _headers));

  /// Raw text (CSV reports).
  Future<String> getText(String path) async {
    final res = await _raw(() => _http.get(uri(path), headers: _headers));
    return utf8.decode(res.bodyBytes);
  }

  Future<http.Response> _raw(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call().timeout(timeout);
    } on TimeoutException {
      throw ApiException(0, 'เซิร์ฟเวอร์ตอบสนองช้า กรุณาลองใหม่');
    } catch (e) {
      throw ApiException(0, 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้ กรุณาตรวจสอบการเชื่อมต่อ');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    var message = 'เกิดข้อผิดพลาด (${res.statusCode})';
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final m = body is Map ? body['message'] : null;
      if (m is List) {
        message = m.join('\n');
      } else if (m != null) {
        message = '$m';
      }
    } catch (_) {}
    if (res.statusCode == 429) message = 'มีการเรียกใช้งานถี่เกินไป กรุณารอสักครู่';
    if (res.statusCode == 401) onUnauthorized?.call();
    throw ApiException(res.statusCode, message);
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    final res = await _raw(call);
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }
}
