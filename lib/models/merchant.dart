class Merchant {
  final String merchantId;
  final String canonicalName;
  final String displayName;
  final String primaryCategory;
  final String? subcategory;
  final List<String> tags;
  final String channel;
  final String country;
  final bool active;

  const Merchant({
    required this.merchantId,
    required this.canonicalName,
    required this.displayName,
    required this.primaryCategory,
    required this.subcategory,
    required this.tags,
    required this.channel,
    required this.country,
    required this.active,
  });

  factory Merchant.fromJson(Map<String, dynamic> json) {
    return Merchant(
      merchantId: json['merchant_id'] as String,
      canonicalName: json['canonical_name'] as String,
      displayName: json['display_name'] as String,
      primaryCategory: json['primary_category'] as String,
      subcategory: json['subcategory'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      channel: json['channel'] as String,
      country: json['country'] as String,
      active: json['active'] as bool? ?? true,
    );
  }
}
