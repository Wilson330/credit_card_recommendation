import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../models/user_card_bundle.dart';
import '../state/user_cards_store.dart';
import 'card_forms/cube_card_form_page.dart';
import 'card_forms/jiho_card_form_page.dart';
import 'widgets/card_thumbnail.dart';

class AddCardPage extends StatelessWidget {
  const AddCardPage({super.key});

  Widget _buildCardOption(
    BuildContext context, {
    required String cardId,
    required String cardName,
    required String bankName,
    required UserCardBundle? existing,
    required WidgetBuilder formPageBuilder,
  }) {
    final isAdded = existing != null;

    return CupertinoListTile(
      leading: CardThumbnail(cardId: cardId),
      title: Text(cardName),
      subtitle: Text(isAdded ? '$bankName · 已加入，點擊編輯' : '$bankName · 點擊新增'),
      trailing: Text(
        isAdded ? '編輯' : '新增',
        style: TextStyle(
          color: (isAdded ? CupertinoColors.systemOrange : CupertinoColors.systemBlue)
              .resolveFrom(context),
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () {
        Navigator.of(context).push(CupertinoPageRoute(builder: formPageBuilder));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserCardsStore>();

    final existingCubeCard = store.findByCardId('cathay_cube');
    final existingJihoCard = store.findByCardId('ubot_jiho');

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('新增卡片'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            CupertinoListSection.insetGrouped(
              children: [
                _buildCardOption(
                  context,
                  cardId: 'cathay_cube',
                  cardName: 'CUBE Card',
                  bankName: '國泰世華',
                  existing: existingCubeCard,
                  formPageBuilder: (_) => CubeCardFormPage(existingCard: existingCubeCard),
                ),
                _buildCardOption(
                  context,
                  cardId: 'ubot_jiho',
                  cardName: '吉鶴卡',
                  bankName: '聯邦銀行',
                  existing: existingJihoCard,
                  formPageBuilder: (_) => JihoCardFormPage(existingCard: existingJihoCard),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
