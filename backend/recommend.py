"""計算推薦(docs/DB_DESIGN.md 7.3)。

純函式,不碰資料庫:輸入「卡片規則 + 使用者卡片設定 + SQL 撈出的方案資料 + 店家」,
輸出每張卡的最佳回饋。資料庫查詢在 service.py。
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


def best_for_card(card_rule, config, rows, merchant, birthday, today):
    """一張卡在這家店的最佳回饋。

    rows:{(scheme_name, variant): SchemeRow},只含這張卡的資料。
    merchant:找不到店家時為 None,視為國內、沒有分類。
    """
    flags = active_conditions(card_rule, config, birthday, today)
    country = merchant.country if merchant else HOME_COUNTRY
    category = merchant.category if merchant else None

    def bonus_for(target):
        return sum((b.add for b in card_rule.bonuses if b.requires <= flags and target in b.applies_to),
                   Decimal('0'))

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

    # 候選:(回饋率, 同分時的優先序, 結果)。優先序:一般消費 2 > 點名的方案 1 > 分類涵蓋 0,
    # 也就是同分時優先推薦不用做任何動作的一般消費
    candidates = [(general_rate, 2, CardResult(
        card_id=card_rule.card_id,
        card_name=card_rule.name,
        bank_name=card_rule.bank,
        reward_rate=general_rate,
        scheme_name=general_tier.name if general_tier else '一般消費',
        is_general=True,
        required_action=None,
        notes=card_rule.notes + (general_tier.notes if general_tier else ()),
    ))]

    variant = card_rule.variant_for(config)
    chosen = set(config.get('chosen_merchants') or [])
    for name, rule in card_rule.schemes.items():
        row = rows.get((name, variant))
        if row is None or not rule.requires <= flags:
            continue
        covered = merchant is not None and any(c.matches(category, country) for c in rule.covers)
        if not (row.is_named or covered):
            continue
        if variant in rule.pick_merchants_when_plan and (merchant is None or merchant.merchant_id not in chosen):
            continue
        rate = row.rate_override if row.rate_override is not None else row.reward_rate
        if rule.stacks_with_general:
            rate += general_rate
        rate += bonus_for(name)
        candidates.append((rate, 1 if row.is_named else 0, CardResult(
            card_id=card_rule.card_id,
            card_name=card_rule.name,
            bank_name=card_rule.bank,
            reward_rate=rate,
            scheme_name=name,
            is_general=False,
            required_action=rule.action,
            notes=card_rule.notes + rule.notes + tuple(row.merchant_notes),
        )))

    return max(candidates, key=lambda c: (c[0], c[1]))[2]


def recommend(rules, user_cards, rows, merchant, birthday, today=None, limit=3):
    """所有卡片的推薦,依回饋率高到低、同分依卡名排序,取前 limit 名。

    user_cards:[(card_id, config)];不在 cards.yaml 的卡會被略過。
    rows:SchemeRow 的清單(SQL 結果),可以含多張卡。
    """
    today = today or today_in_taiwan()
    by_card = {}
    for r in rows:
        by_card.setdefault(r.card_id, {})[(r.scheme_name, r.variant)] = r

    results = []
    for card_id, config in user_cards:
        card_rule = rules.cards.get(card_id)
        if card_rule is None:
            continue
        results.append(best_for_card(card_rule, config, by_card.get(card_id, {}), merchant, birthday, today))

    results.sort(key=lambda r: (-r.reward_rate, r.card_name))
    return results[:limit]
