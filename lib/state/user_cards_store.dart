import 'package:flutter/foundation.dart';

import '../models/user_card_bundle.dart';

class UserCardsStore extends ChangeNotifier {
  List<UserCardBundle> _userCards = [];

  List<UserCardBundle> get userCards => List.unmodifiable(_userCards);

  bool get hasCards => _userCards.isNotEmpty;

  void setUserCards(List<UserCardBundle> userCards) {
    _userCards = List<UserCardBundle>.from(userCards);
    notifyListeners();
  }

  void replaceAll(List<UserCardBundle> userCards) {
    _userCards = List<UserCardBundle>.from(userCards);
    notifyListeners();
  }

  void addCard(UserCardBundle userCard) {
    _userCards = [..._userCards, userCard];
    notifyListeners();
  }

  void removeCardByWalletId(String walletId) {
    _userCards = _userCards
        .where((card) => card.walletCard.id != walletId)
        .toList();
    notifyListeners();
  }

  void updateCard(UserCardBundle updatedCard) {
    _userCards = _userCards.map((card) {
      if (card.walletCard.id == updatedCard.walletCard.id) {
        return updatedCard;
      }
      return card;
    }).toList();
    notifyListeners();
  }

  UserCardBundle? findByCardId(String cardId) {
    for (final card in _userCards) {
      if (card.walletCard.cardId == cardId) {
        return card;
      }
    }
    return null;
  }

  void clear() {
    _userCards = [];
    notifyListeners();
  }
}