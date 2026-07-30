import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../models/card_profiles/jiho_card_profile.dart';
import '../../models/user_card_bundle.dart';
import '../../models/wallet_card.dart';
import '../../state/user_cards_store.dart';
import '../widgets/card_thumbnail.dart';

class JihoCardFormPage extends StatefulWidget {
  final UserCardBundle? existingCard;

  const JihoCardFormPage({
    super.key,
    this.existingCard,
  });

  @override
  State<JihoCardFormPage> createState() => _JihoCardFormPageState();
}

class _JihoCardFormPageState extends State<JihoCardFormPage> {
  late bool isNewCardHolder;
  late String selectedNetwork;

  bool get isEditMode => widget.existingCard != null;

  @override
  void initState() {
    super.initState();

    final existingProfile = widget.existingCard?.profile as JihoCardProfile?;
    final existingWalletCard = widget.existingCard?.walletCard;

    isNewCardHolder = existingProfile?.isNewCardHolder ?? false;
    selectedNetwork = existingWalletCard?.network ?? 'Mastercard';
  }

  void _handleSave() {
    final existingWalletCard = widget.existingCard?.walletCard;

    final userCard = UserCardBundle(
      walletCard: WalletCard(
        id: existingWalletCard?.id ??
            'wallet_jiho_${DateTime.now().millisecondsSinceEpoch}',
        cardId: 'ubot_jiho',
        bankName: '聯邦銀行',
        cardName: '吉鶴卡',
        network: selectedNetwork,
      ),
      profile: JihoCardProfile(
        isNewCardHolder: isNewCardHolder,
      ),
    );

    final store = context.read<UserCardsStore>();

    if (isEditMode) {
      store.updateCard(userCard);
      Navigator.of(context).pop();
    } else {
      store.addCard(userCard);
      Navigator.of(context).pop();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(isEditMode ? '編輯吉鶴卡' : '新增吉鶴卡'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Center(
              child: CardThumbnail(cardId: 'ubot_jiho', width: 240),
            ),
            const SizedBox(height: 24),
            CupertinoFormSection.insetGrouped(
              children: [
                CupertinoFormRow(
                  prefix: const Text('發卡組織'),
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: selectedNetwork,
                    children: const {
                      'Visa': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Visa'),
                      ),
                      'Mastercard': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Mastercard'),
                      ),
                      'JCB': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('JCB'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedNetwork = value);
                    },
                  ),
                ),
                CupertinoFormRow(
                  prefix: const Text('吉鶴新戶'),
                  child: CupertinoSwitch(
                    value: isNewCardHolder,
                    onChanged: (value) => setState(() => isNewCardHolder = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoButton.filled(
                onPressed: _handleSave,
                child: Text(isEditMode ? '儲存變更' : '加入我的卡片'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
