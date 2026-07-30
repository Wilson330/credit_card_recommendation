import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_card_bundle.dart';
import '../state/user_cards_store.dart';
import 'add_card_page.dart';
import 'card_forms/cube_card_form_page.dart';
import 'card_forms/jiho_card_form_page.dart';

class MyCardsPage extends StatelessWidget {
  const MyCardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserCardsStore>();
    final userCards = store.userCards;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cards'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AddCardPage(),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('新增卡片'),
            ),
            const SizedBox(height: 24),
            if (userCards.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('目前還沒有加入任何卡片'),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: userCards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final UserCardBundle userCard = userCards[index];
                    final walletCard = userCard.walletCard;

                    return Card(
                      child: ListTile(
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(walletCard.cardName),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.teal.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                walletCard.network,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(walletCard.bankName),
                        ),
                        onTap: () {
                          if (walletCard.cardId == 'cathay_cube') {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CubeCardFormPage(
                                  existingCard: userCard,
                                ),
                              ),
                            );
                            return;
                          }

                          if (walletCard.cardId == 'ubot_jiho') {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => JihoCardFormPage(
                                  existingCard: userCard,
                                ),
                              ),
                            );
                            return;
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${walletCard.cardName} 編輯頁下一步接上'),
                            ),
                          );
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            store.removeCardByWalletId(walletCard.id);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}