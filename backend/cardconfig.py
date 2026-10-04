"""使用者卡片設定(user_cards.config)的檢查(docs/DB_DESIGN.md 6.3)。

資料庫只檢查「是不是合法 JSON」,內容是否合法在這裡依 cards.yaml 檢查。
"""

from .errors import ApiError


def validate_config(card_rule, config, pickable_ids):
    """檢查並整理 config;不合法時丟出 400。

    回傳整理過的 config:沒給的開關補成 false;不需要挑店時不存 chosen_merchants。
    """
    if not isinstance(config, dict):
        raise ApiError(400, 'config 要是物件')

    allowed = set(card_rule.toggles)
    if card_rule.rate_by:
        allowed.add(card_rule.rate_by)
    if card_rule.pick_plans:
        allowed.add('chosen_merchants')
    unknown = set(config) - allowed
    if unknown:
        raise ApiError(400, f'{card_rule.name} 沒有這些設定:{"、".join(sorted(unknown))}')

    result = {}
    if card_rule.rate_by:
        value = config.get(card_rule.rate_by)
        if value not in card_rule.options:
            raise ApiError(400, f'{card_rule.name} 的 {card_rule.rate_by} 要是以下其中之一:'
                                f'{"、".join(card_rule.options)}')
        result[card_rule.rate_by] = value

    for key in card_rule.toggles:
        value = config.get(key, False)
        if not isinstance(value, bool):
            raise ApiError(400, f'{key} 要是 true 或 false')
        result[key] = value

    chosen = config.get('chosen_merchants') or []
    variant = card_rule.variant_for(result)
    if variant in card_rule.pick_plans:
        if not isinstance(chosen, list) or not all(isinstance(m, int) and not isinstance(m, bool) for m in chosen):
            raise ApiError(400, 'chosen_merchants 要是店家編號的清單')
        if len(set(chosen)) != len(chosen):
            raise ApiError(400, 'chosen_merchants 有重複的店家')
        limit = card_rule.max_chosen_merchants
        if len(chosen) > limit:
            raise ApiError(400, f'{variant} 最多只能挑 {limit} 家店')
        invalid = [m for m in chosen if m not in pickable_ids]
        if invalid:
            raise ApiError(400, f'這些店家不在可挑選的名單中:{"、".join(map(str, invalid))}')
        result['chosen_merchants'] = chosen
    elif chosen:
        raise ApiError(400, f'{variant or card_rule.name} 不需要挑店,請不要帶 chosen_merchants')

    return result
