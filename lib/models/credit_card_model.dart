import 'card_benefit_rule.dart';

class CreditCardModel {
  final String id;
  final String bankName;
  final String cardName;
  final String network;
  final String cardType;
  final List<CardBenefitRule> benefitRules;

  CreditCardModel({
    required this.id,
    required this.bankName,
    required this.cardName,
    required this.network,
    required this.cardType,
    required this.benefitRules,
  });
}