import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'api/api_config.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'state/search_history_store.dart';
import 'state/session_store.dart';
import 'state/user_cards_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(api: ApiClient(baseUrl: resolveApiBaseUrl())));
}

class MyApp extends StatelessWidget {
  final ApiClient api;

  const MyApp({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => SessionStore(api)..restore()),
        ChangeNotifierProvider(create: (_) => UserCardsStore(api)),
        ChangeNotifierProvider(create: (_) => SearchHistoryStore()),
      ],
      child: const CupertinoApp(
        title: '刷哪張卡',
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(primaryColor: CupertinoColors.systemBlue),
        home: AppRoot(),
      ),
    );
  }
}

/// 依登入狀態切換登入頁或首頁;登入後載入使用者的卡片,登出時清掉。
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final cards = context.read<UserCardsStore>();

    switch (session.status) {
      case SessionStatus.restoring:
        return const CupertinoPageScaffold(child: Center(child: CupertinoActivityIndicator()));
      case SessionStatus.loggedOut:
        if (cards.loadedFor != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            cards.clear();
            context.read<SearchHistoryStore>().clear();
            // token 過期時使用者可能停在較深的頁面(例如卡片表單),一併關掉回到登入畫面
            Navigator.of(context).popUntil((route) => route.isFirst);
          });
        }
        return const LoginPage();
      case SessionStatus.loggedIn:
        final email = session.user!.email;
        if (cards.loadedFor != email) {
          WidgetsBinding.instance.addPostFrameCallback((_) => cards.loadForUser(email));
        }
        return const HomePage();
    }
  }
}
