import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/user_cards_store.dart';
import 'card_forms/cube_card_form_page.dart';
import 'card_forms/jiho_card_form_page.dart';

class AddCardPage extends StatelessWidget {
  const AddCardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserCardsStore>();

    final existingCubeCard = store.findByCardId('cathay_cube');
    final existingJihoCard = store.findByCardId('ubot_jiho');

    final hasCubeCard = existingCubeCard != null;
    final hasJihoCard = existingJihoCard != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('新增卡片'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('CUBE Card'),
              subtitle: Text(
                hasCubeCard ? '國泰世華 · 已加入，點擊編輯' : '國泰世華 · 點擊新增',
              ),
              trailing: Text(
                hasCubeCard ? '編輯' : '新增',
                style: TextStyle(
                  color: hasCubeCard ? Colors.orange : Colors.teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CubeCardFormPage(
                      existingCard: existingCubeCard,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('吉鶴卡'),
              subtitle: Text(
                hasJihoCard ? '聯邦銀行 · 已加入，點擊編輯' : '聯邦銀行 · 點擊新增',
              ),
              trailing: Text(
                hasJihoCard ? '編輯' : '新增',
                style: TextStyle(
                  color: hasJihoCard ? Colors.orange : Colors.teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => JihoCardFormPage(
                      existingCard: existingJihoCard,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}