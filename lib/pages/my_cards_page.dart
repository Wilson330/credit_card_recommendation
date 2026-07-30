import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../models/user_card_bundle.dart';
import '../state/user_cards_store.dart';
import 'add_card_page.dart';
import 'card_forms/cube_card_form_page.dart';
import 'card_forms/jiho_card_form_page.dart';
import 'widgets/card_thumbnail.dart';

class MyCardsPage extends StatelessWidget {
  const MyCardsPage({super.key});

  void _openAddCardPage(BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => const AddCardPage()),
    );
  }

  void _openEditPage(BuildContext context, UserCardBundle userCard) {
    final cardId = userCard.walletCard.cardId;

    if (cardId == 'cathay_cube') {
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => CubeCardFormPage(existingCard: userCard),
        ),
      );
      return;
    }

    if (cardId == 'ubot_jiho') {
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => JihoCardFormPage(existingCard: userCard),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserCardsStore>();
    final userCards = store.userCards;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('My Cards'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _openAddCardPage(context),
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        child: userCards.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.creditcard,
                        size: 48,
                        color: CupertinoColors.systemGrey.resolveFrom(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '目前還沒有加入任何卡片',
                        style: TextStyle(
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      CupertinoButton.filled(
                        onPressed: () => _openAddCardPage(context),
                        child: const Text('新增卡片'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  CupertinoListSection.insetGrouped(
                    header: const Text('已加入的卡片，左滑可移除'),
                    children: [
                      for (final userCard in userCards)
                        Dismissible(
                          key: ValueKey(userCard.walletCard.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            color: CupertinoColors.destructiveRed.resolveFrom(context),
                            child: const Icon(
                              CupertinoIcons.delete,
                              color: CupertinoColors.white,
                            ),
                          ),
                          onDismissed: (_) =>
                              store.removeCardByWalletId(userCard.walletCard.id),
                          child: CupertinoListTile(
                            leading: CardThumbnail(cardId: userCard.walletCard.cardId),
                            title: Text(userCard.walletCard.cardName),
                            subtitle: Text(
                              '${userCard.walletCard.bankName} · ${userCard.walletCard.network}',
                            ),
                            trailing: const CupertinoListTileChevron(),
                            onTap: () => _openEditPage(context, userCard),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
