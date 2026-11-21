import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'app/router.dart';
import 'core/api/api_client.dart';
import 'core/api/lotto_api.dart';
import 'core/session.dart';
import 'core/theme/app_theme.dart';

void main() {
  usePathUrlStrategy();
  final session = Session(LottoApi(ApiClient()));
  session.restore();
  runApp(LottoDayApp(session: session));
}

class LottoDayApp extends StatefulWidget {
  const LottoDayApp({super.key, required this.session});
  final Session session;
  @override
  State<LottoDayApp> createState() => _LottoDayAppState();
}

class _LottoDayAppState extends State<LottoDayApp> {
  late final GoRouter _router = buildRouter(widget.session);

  @override
  Widget build(BuildContext context) => AppScope(
        session: widget.session,
        child: MaterialApp.router(
          title: 'LOTTO DAY • DEMO',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: _router,
          locale: const Locale('th', 'TH'),
          supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
        ),
      );
}
