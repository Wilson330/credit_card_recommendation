import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/merchant_query_context.dart';
import '../services/recommendation_orchestrator.dart';
import '../state/user_cards_store.dart';
import 'my_cards_page.dart';
import 'result_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _merchantController = TextEditingController();
  final _orchestrator = RecommendationOrchestrator();

  void _openMyCardsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MyCardsPage(),
      ),
    );
  }

  void _handleSearch() {
    final merchantName = _merchantController.text.trim();
    if (merchantName.isEmpty) return;

    final store = context.read<UserCardsStore>();
    final userCards = store.userCards;
    if (userCards.isEmpty) return;

    final merchantContext = MerchantQueryContext(
      merchantName: merchantName,
    );

    final results = _orchestrator.evaluate(
      merchantContext: merchantContext,
      userCards: userCards,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultPage(
          merchantName: merchantName,
          results: results,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserCardsStore>();
    final userCards = store.userCards;
    final hasCards = store.hasCards;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cards'),
        actions: [
          IconButton(
            onPressed: _openMyCardsPage,
            icon: const Icon(Icons.credit_card),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasCards ? '已設定 ${userCards.length} 張卡片' : '尚未設定卡片',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (hasCards)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Debug: 目前卡片狀態',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  ...userCards.map(
                    (c) => Text(
                      '- ${c.walletCard.cardName} (${c.walletCard.cardId})',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _openMyCardsPage,
              child: const Text('設定我的卡片'),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: '輸入商家名稱',
                hintText: '例如：全聯、Uber Eats、星巴克',
              ),
              onSubmitted: (_) => _handleSearch(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: hasCards ? _handleSearch : null,
              child: const Text('開始推薦'),
            ),
          ],
        ),
      ),
    );
  }
}