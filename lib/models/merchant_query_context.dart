class MerchantQueryContext {
  final String merchantName;
  final String? channel;
  final String? country;
  final List<String> merchantTags;
  final String? paymentMethod;

  const MerchantQueryContext({
    required this.merchantName,
    this.channel,
    this.country,
    this.merchantTags = const [],
    this.paymentMethod,
  });
}