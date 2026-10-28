"""使用者卡片設定(user_cards.config)的檢查(docs/DB_DESIGN.md 6.3)。

資料庫只檢查「是不是合法 JSON」,內容是否合法在這裡依 cards.yaml 檢查。
"""

from .errors import ApiError


def validate_config(card_rule, config, pickable_ids):
    """檢查並整理 config;不合法時丟出 400。

    回傳整理過的 config:沒給的開關補成 false;有支援行動支付的卡一定有 payment_methods
    (依 cards.yaml 的順序);不需要挑店時不存 chosen_merchants 與 chosen_payment_methods。
    """
    if not isinstance(config, dict):
        raise ApiError(400, 'config 要是物件')

    allowed = set(card_rule.toggles)
    if card_rule.rate_by:
        allowed.add(card_rule.rate_by)
    if card_rule.payment_methods:
        allowed.add('payment_methods')
    if card_rule.pick_plans:
        allowed.add('chosen_merchants')
    if card_rule.pickable_payment_methods:
        allowed.add('chosen_payment_methods')
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

    if card_rule.payment_methods:
        result['payment_methods'] = _payment_list(
            config.get('payment_methods'), card_rule.payment_methods, 'payment_methods',
            f'{card_rule.name} 不支援這些行動支付')

    chosen = config.get('chosen_merchants') or []
    chosen_payments = config.get('chosen_payment_methods') or []
    variant = card_rule.variant_for(result)
    if variant in card_rule.pick_plans:
        if not isinstance(chosen, list) or not all(isinstance(m, int) and not isinstance(m, bool) for m in chosen):
            raise ApiError(400, 'chosen_merchants 要是店家編號的清單')
        if len(set(chosen)) != len(chosen):
            raise ApiError(400, 'chosen_merchants 有重複的店家')
        invalid = [m for m in chosen if m not in pickable_ids]
        if invalid:
            raise ApiError(400, f'這些店家不在可挑選的名單中:{"、".join(map(str, invalid))}')
        if card_rule.pickable_payment_methods:
            chosen_payments = _payment_list(
                chosen_payments, card_rule.pickable_payment_methods, 'chosen_payment_methods',
                '這些行動支付不在可挑選的名單中')
        limit = card_rule.max_chosen_merchants
        if len(chosen) + len(chosen_payments) > limit:
            raise ApiError(400, f'{variant} 最多只能挑 {limit} 家店(行動支付也算在內)')
        result['chosen_merchants'] = chosen
        if card_rule.pickable_payment_methods:
            result['chosen_payment_methods'] = chosen_payments
    elif chosen or chosen_payments:
        raise ApiError(400, f'{variant or card_rule.name} 不需要挑店,'
                            f'請不要帶 chosen_merchants 或 chosen_payment_methods')

    return result


def _payment_list(value, allowed, key, invalid_message):
    """行動支付名稱清單:檢查後依 cards.yaml 的順序排列。"""
    value = value or []
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        raise ApiError(400, f'{key} 要是行動支付名稱的清單')
    if len(set(value)) != len(value):
        raise ApiError(400, f'{key} 有重複的行動支付')
    invalid = [v for v in value if v not in allowed]
    if invalid:
        raise ApiError(400, f'{invalid_message}:{"、".join(invalid)}')
    return [v for v in allowed if v in value]
