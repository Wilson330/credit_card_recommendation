import 'card_profiles/card_profile.dart';
import 'wallet_card.dart';

class UserCardBundle {
  final WalletCard walletCard;
  final CardProfile profile;

  const UserCardBundle({
    required this.walletCard,
    required this.profile,
  });
}
