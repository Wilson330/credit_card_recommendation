import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../models/card_profiles/cube_card_profile.dart';
import '../../models/user_card_bundle.dart';
import '../../models/wallet_card.dart';
import '../../state/user_cards_store.dart';
import '../widgets/card_thumbnail.dart';

class CubeCardFormPage extends StatefulWidget {
  final UserCardBundle? existingCard;

  const CubeCardFormPage({
    super.key,
    this.existingCard,
  });

  @override
  State<CubeCardFormPage> createState() => _CubeCardFormPageState();
}

class _CubeCardFormPageState extends State<CubeCardFormPage> {
  late bool isNewCardHolder;
  late String selectedLevel;
  late String selectedNetwork;

  bool get isEditMode => widget.existingCard != null;

  @override
  void initState() {
    super.initState();

    final existingProfile = widget.existingCard?.profile as CubeCardProfile?;
    final existingWalletCard = widget.existingCard?.walletCard;

    isNewCardHolder = existingProfile?.isNewCardHolder ?? false;
    selectedLevel = existingProfile?.selectedLevel ?? 'level_3';
    selectedNetwork = existingWalletCard?.network ?? 'Visa';
  }

  void _handleSave() {
    final existingWalletCard = widget.existingCard?.walletCard;

    final userCard = UserCardBundle(
      walletCard: WalletCard(
        id: existingWalletCard?.id ??
            'wallet_cube_${DateTime.now().millisecondsSinceEpoch}',
        cardId: 'cathay_cube',
        bankName: '國泰世華',
        cardName: 'CUBE Card',
        network: selectedNetwork,
      ),
      profile: CubeCardProfile(
        selectedLevel: selectedLevel,
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
        middle: Text(isEditMode ? '編輯 CUBE Card' : '新增 CUBE Card'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Center(
              child: CardThumbnail(cardId: 'cathay_cube', width: 240),
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
                  prefix: const Text('CUBE 新戶'),
                  child: CupertinoSwitch(
                    value: isNewCardHolder,
                    onChanged: (value) => setState(() => isNewCardHolder = value),
                  ),
                ),
                CupertinoFormRow(
                  prefix: const Text('CUBE 權益等級'),
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: selectedLevel,
                    children: const {
                      'level_1': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Level 1'),
                      ),
                      'level_2': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Level 2'),
                      ),
                      'level_3': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Level 3'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedLevel = value);
                    },
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
