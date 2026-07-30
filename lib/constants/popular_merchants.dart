/// Curated for v1 since there's no real usage data yet to derive "popular"
/// from. Every entry is verified to exist verbatim as a match_value in
/// cube_reward_rules.json / jiho_reward_rules.json (see
/// scripts/convert_allen_rewards.js output), so tapping one always
/// produces a real result rather than falling through to default.
class PopularMerchants {
  static const List<String> suggestions = [
    '全家便利商店 實體門市',
    'Netflix',
    'Uber Eats',
    '誠品生活',
    '台灣高鐵',
    'Agoda',
    '蝦皮購物',
    'UNIQLO',
  ];
}
