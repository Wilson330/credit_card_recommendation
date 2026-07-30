class RuleCondition {
  final bool requiresManualSelection;
  final String? selectedProgram;

  final bool japanOnly;
  final bool physicalStoreOnly;
  final bool requiresApplePay;
  final bool requiresGooglePay;
  final bool requiresRegistration;
  final bool designatedMerchantOnly;
  final bool installmentExcluded;
  final bool newCustomerOnly;

  final String? requiredLevel;
  final String? merchantGroup;
  final String? paymentMethodNote;

  RuleCondition({
    required this.requiresManualSelection,
    this.selectedProgram,
    required this.japanOnly,
    required this.physicalStoreOnly,
    required this.requiresApplePay,
    required this.requiresGooglePay,
    required this.requiresRegistration,
    required this.designatedMerchantOnly,
    required this.installmentExcluded,
    required this.newCustomerOnly,
    this.requiredLevel,
    this.merchantGroup,
    this.paymentMethodNote,
  });
}