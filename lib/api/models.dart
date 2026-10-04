// 後端 API 回傳的資料(格式見 backend/README.md 的 API 一覽)。

/// 一張卡在設定畫面要顯示的選項,來自 GET /api/cards(後端讀 cards.yaml)。
class CardOption {
  final String cardId;
  final String name;
  final String bank;

  /// 決定回饋率的設定:'level'(CUBE 等級)、'plan'(Unicard 方案)、null(沒有)。
  final String? rateBy;
  final List<String> options;
  final List<CardToggle> toggles;

  /// 選到這些方案時要挑店(Unicard 任意選)。
  final List<String> pickMerchantsWhen;
  final int? maxChosenMerchants;

  const CardOption({
    required this.cardId,
    required this.name,
    required this.bank,
    required this.rateBy,
    required this.options,
    required this.toggles,
    required this.pickMerchantsWhen,
    required this.maxChosenMerchants,
  });

  factory CardOption.fromJson(Map<String, dynamic> json) => CardOption(
        cardId: json['card_id'] as String,
        name: json['name'] as String,
        bank: json['bank'] as String,
        rateBy: json['rate_by'] as String?,
        options: List<String>.from(json['options'] as List),
        toggles: [
          for (final t in json['toggles'] as List)
            CardToggle(key: t['key'] as String, label: t['label'] as String),
        ],
        pickMerchantsWhen: List<String>.from(json['pick_merchants_when'] as List),
        maxChosenMerchants: json['max_chosen_merchants'] as int?,
      );

  /// 等級或方案選單的標題。
  String get rateByLabel => rateBy == 'level' ? '權益等級' : '方案';

  bool needsMerchantPicks(String? selected) =>
      selected != null && pickMerchantsWhen.contains(selected);

  /// 新增卡片時的預設設定。
  Map<String, dynamic> defaultConfig() => {
        ?rateBy: options.isEmpty ? null : options.first,
        for (final t in toggles) t.key: false,
      };
}

class CardToggle {
  final String key;
  final String label;

  const CardToggle({required this.key, required this.label});
}

/// 使用者持有的一張卡與它的設定(user_cards.config)。
class UserCard {
  final String cardId;
  final String cardName;
  final Map<String, dynamic> config;

  const UserCard({required this.cardId, required this.cardName, required this.config});

  factory UserCard.fromJson(Map<String, dynamic> json) => UserCard(
        cardId: json['card_id'] as String,
        cardName: (json['card_name'] as String?) ?? json['card_id'] as String,
        config: Map<String, dynamic>.from(json['config'] as Map),
      );

  Map<String, dynamic> toJson() => {'card_id': cardId, 'card_name': cardName, 'config': config};

  /// 列表上顯示的設定摘要,例如「Level 2 · 童樂匯」。
  String summary(CardOption? option) {
    final parts = <String>[];
    if (option?.rateBy != null && config[option!.rateBy] != null) {
      parts.add(config[option.rateBy] as String);
    }
    for (final t in option?.toggles ?? const <CardToggle>[]) {
      if (config[t.key] == true) parts.add(t.label);
    }
    final picks = config['chosen_merchants'];
    if (picks is List && picks.isNotEmpty) parts.add('挑選 ${picks.length} 家');
    return parts.join(' · ');
  }
}

class MerchantSuggestion {
  final int merchantId;
  final String name;

  const MerchantSuggestion({required this.merchantId, required this.name});

  factory MerchantSuggestion.fromJson(Map<String, dynamic> json) =>
      MerchantSuggestion(merchantId: json['merchant_id'] as int, name: json['name'] as String);
}

/// POST /api/recommend 的結果。
class Recommendation {
  final String? merchantName;
  final bool merchantFound;

  /// 找不到店家時的提示,例如「此店家不在回饋名單中,以一般消費計算」。
  final String? message;
  final List<CardRecommendation> results;

  const Recommendation({
    required this.merchantName,
    required this.merchantFound,
    required this.message,
    required this.results,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
        merchantName: (json['merchant'] as Map?)?['name'] as String?,
        merchantFound: json['merchant_found'] as bool,
        message: json['message'] as String?,
        results: [
          for (final r in json['results'] as List) CardRecommendation.fromJson(r as Map<String, dynamic>),
        ],
      );
}

class CardRecommendation {
  final String cardId;
  final String cardName;
  final String bankName;
  final double rewardRate;
  final String schemeName;

  /// true = 一般消費,不需要做任何動作。
  final bool isGeneral;
  final String? requiredAction;
  final List<String> notes;

  const CardRecommendation({
    required this.cardId,
    required this.cardName,
    required this.bankName,
    required this.rewardRate,
    required this.schemeName,
    required this.isGeneral,
    required this.requiredAction,
    required this.notes,
  });

  factory CardRecommendation.fromJson(Map<String, dynamic> json) => CardRecommendation(
        cardId: json['card_id'] as String,
        cardName: json['card_name'] as String,
        bankName: json['bank_name'] as String,
        rewardRate: (json['reward_rate'] as num).toDouble(),
        schemeName: json['scheme_name'] as String,
        isGeneral: json['is_general'] as bool,
        requiredAction: json['required_action'] as String?,
        notes: List<String>.from(json['notes'] as List),
      );

  /// 回饋率顯示,例如 3、3.5、0.3(不顯示多餘的 0)。
  String get rateText {
    final text = rewardRate.toStringAsFixed(2);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class LoggedInUser {
  final String email;
  final String fullName;
  final String birthday;

  const LoggedInUser({required this.email, required this.fullName, required this.birthday});

  factory LoggedInUser.fromJson(Map<String, dynamic> json) => LoggedInUser(
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        birthday: json['birthday'] as String,
      );

  Map<String, dynamic> toJson() => {'email': email, 'full_name': fullName, 'birthday': birthday};
}
