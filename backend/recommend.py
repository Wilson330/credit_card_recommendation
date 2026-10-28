"""計算推薦(docs/DB_DESIGN.md 7.3)。

純函式,不碰資料庫:輸入「卡片規則 + 使用者卡片設定 + SQL 撈出的方案資料 + 店家」,
輸出每張卡的最佳回饋。資料庫查詢在 service.py。

行動支付另外計算(payment_suggestion):不知道店家收哪些行動支付,所以不放進主清單,
只在比主清單第 1 名高時,額外給一筆建議。
"""

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

from .rules import HOME_COUNTRY

TAIWAN_TZ = timezone(timedelta(hours=8))   # 台灣沒有日光節約時間,固定 +8


@dataclass(frozen=True)
class Merchant:
    merchant_id: int
    name: str
    category: str
    country: str


@dataclass(frozen=True)
class SchemeRow:
    """SQL 撈出的一列:某卡某方案在某個 variant 下的回饋率,以及這家店有沒有被點名。"""
    card_id: str
    scheme_name: str
    variant: str
    reward_rate: Decimal
    is_named: bool = False
    rate_override: Decimal = None
    merchant_notes: tuple = ()


@dataclass(frozen=True)
class CardResult:
    card_id: str
    card_name: str
    bank_name: str
    reward_rate: Decimal
    scheme_name: str
    is_general: bool          # True = 一般消費,不需要做任何動作
    required_action: str
    notes: tuple = field(default_factory=tuple)
    payment_methods: tuple = ()   # 空的 = 直接刷卡;有值 = 用其中任一種行動支付綁定本卡付款


@dataclass(frozen=True)
class PaymentSuggestion:
    """用行動支付付款的建議。"""
    result: CardResult
    direct_reward_rate: Decimal   # 同一張卡直接刷卡的回饋率,對照用


def today_in_taiwan():
    return datetime.now(TAIWAN_TZ).date()


def is_birthday_month(birthday, today):
    return birthday is not None and birthday.month == today.month


def where_matches(where, country):
    if where is None:
        return True
    if where == 'domestic':
        return country == HOME_COUNTRY
    if where == 'overseas':
        return country != HOME_COUNTRY
    return country == where


def active_conditions(card_rule, config, birthday, today):
    """config 中為 true 的開關,加上系統判斷的條件。"""
    flags = {key for key in card_rule.toggles if config.get(key) is True}
    if is_birthday_month(birthday, today):
        flags.add('birthday_month')
    return frozenset(flags)


def _candidates(card_rule, config, rows, merchant, birthday, today):
    """一張卡在這家店的候選:(直接刷卡的候選, 用行動支付的候選)。

    候選是 (回饋率, 同分時的優先序, CardResult)。
    rows:{(scheme_name, variant): SchemeRow},只含這張卡的資料。
    merchant:找不到店家時為 None,視為國內、沒有分類。
    """
    flags = active_conditions(card_rule, config, birthday, today)
    country = merchant.country if merchant else HOME_COUNTRY
    category = merchant.category if merchant else None

    def bonus_for(target):
        return sum((b.add for b in card_rule.bonuses if b.requires <= flags and target in b.applies_to),
                   Decimal('0'))

    def result(rate, **kwargs):
        return CardResult(card_id=card_rule.card_id, card_name=card_rule.name, bank_name=card_rule.bank,
                          reward_rate=rate, **kwargs)

    # 一般消費:條件與地點都符合的各層,加上適用的加碼後取最高;一層都不符合就是 0%
    general_choices = [
        (tier.rate + bonus_for(tier.name), tier)
        for tier in card_rule.general
        if tier.requires <= flags and where_matches(tier.where, country)
    ]
    if general_choices:
        general_rate, general_tier = max(general_choices, key=lambda x: x[0])
    else:
        general_rate, general_tier = Decimal('0'), None

    # 優先序:一般消費 2 > 點名的方案 1 > 分類涵蓋 0,
    # 也就是同分時優先推薦不用做任何動作的一般消費
    direct = [(general_rate, 2, result(
        general_rate,
        scheme_name=general_tier.name if general_tier else '一般消費',
        is_general=True,
        required_action=None,
        notes=card_rule.notes + (general_tier.notes if general_tier else ()),
    ))]
    payments = []

    variant = card_rule.variant_for(config)
    chosen = set(config.get('chosen_merchants') or [])
    bound = set(config.get('payment_methods') or [])
    chosen_payments = set(config.get('chosen_payment_methods') or [])
    for name, rule in card_rule.schemes.items():
        row = rows.get((name, variant))
        if row is None or not rule.requires <= flags:
            continue
        picking = variant in rule.pick_merchants_when_plan
        extra = (general_rate if rule.stacks_with_general else Decimal('0')) + bonus_for(name)

        # 行動支付:只限國內的店(找不到店家視為國內),不限哪家店;要有綁定,
        # 需要挑店的方案還要挑了這個行動支付
        methods = () if country != HOME_COUNTRY else tuple(
            m for m in rule.payment_method_names if m in bound and (not picking or m in chosen_payments))
        if methods:
            rate = row.reward_rate + extra
            payments.append((rate, 0, result(
                rate,
                scheme_name=name,
                is_general=False,
                required_action=_payment_action(card_rule, rule, methods),
                notes=card_rule.notes + rule.notes,
                payment_methods=methods,
            )))

        covered = merchant is not None and any(c.matches(category, country) for c in rule.covers)
        if not (row.is_named or covered):
            continue
        if picking and (merchant is None or merchant.merchant_id not in chosen):
            continue
        rate = (row.rate_override if row.rate_override is not None else row.reward_rate) + extra
        direct.append((rate, 1 if row.is_named else 0, result(
            rate,
            scheme_name=name,
            is_general=False,
            required_action=rule.action,
            notes=card_rule.notes + rule.notes + tuple(row.merchant_notes),
        )))

    return direct, payments


def _payment_action(card_rule, rule, methods):
    if len(methods) == 1:
        pay = f'用 {methods[0]} 綁定 {card_rule.name} 付款'
    else:
        pay = f'用 {"、".join(methods)} 其中一種綁定 {card_rule.name} 付款'
    return f'{rule.action},並{pay}' if rule.action else pay


def _best(candidates):
    return max(candidates, key=lambda c: (c[0], c[1]))[2]


def best_for_card(card_rule, config, rows, merchant, birthday, today):
    """一張卡在這家店直接刷卡的最佳回饋(不含行動支付)。"""
    direct, _ = _candidates(card_rule, config, rows, merchant, birthday, today)
    return _best(direct)


def _rows_by_card(rows):
    by_card = {}
    for r in rows:
        by_card.setdefault(r.card_id, {})[(r.scheme_name, r.variant)] = r
    return by_card


def recommend(rules, user_cards, rows, merchant, birthday, today=None, limit=3):
    """所有卡片的推薦,依回饋率高到低、同分依卡名排序,取前 limit 名。

    user_cards:[(card_id, config)];不在 cards.yaml 的卡會被略過。
    rows:SchemeRow 的清單(SQL 結果),可以含多張卡。
    """
    today = today or today_in_taiwan()
    by_card = _rows_by_card(rows)

    results = []
    for card_id, config in user_cards:
        card_rule = rules.cards.get(card_id)
        if card_rule is None:
            continue
        results.append(best_for_card(card_rule, config, by_card.get(card_id, {}), merchant, birthday, today))

    results.sort(key=lambda r: (-r.reward_rate, r.card_name))
    return results[:limit]


def payment_suggestion(rules, user_cards, rows, merchant, birthday, today=None):
    """用行動支付付款的建議;沒有比直接刷卡更好的選擇時回傳 None。

    只在回饋率高於所有卡直接刷卡的最高回饋(主清單第 1 名)時才建議;
    多張卡都符合時取回饋率最高的一張,同分依卡名。同一張卡回饋率相同的行動支付全部列出,
    使用者挑店家有收的那一種即可。
    """
    today = today or today_in_taiwan()
    by_card = _rows_by_card(rows)

    top_direct = None
    options = []
    for card_id, config in user_cards:
        card_rule = rules.cards.get(card_id)
        if card_rule is None:
            continue
        direct, payments = _candidates(card_rule, config, by_card.get(card_id, {}), merchant, birthday, today)
        direct_rate = _best(direct).reward_rate
        top_direct = direct_rate if top_direct is None else max(top_direct, direct_rate)
        if payments:
            # 回饋率相同時取 cards.yaml 中先列的方案
            options.append(PaymentSuggestion(result=_best(payments), direct_reward_rate=direct_rate))

    options = [o for o in options if o.result.reward_rate > top_direct]
    if not options:
        return None
    return min(options, key=lambda o: (-o.result.reward_rate, o.result.card_name))
