import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'services/reward_rules_repository.dart';
import 'state/search_history_store.dart';
import 'state/user_cards_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RewardRulesRepository.instance.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserCardsStore()),
        ChangeNotifierProvider(create: (_) => SearchHistoryStore()),
      ],
      child: MaterialApp(
        title: 'Credit Card Recommender',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.teal,
        ),
        home: const HomePage(),
      ),
    );
  }
}
