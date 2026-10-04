"""載入並檢查 cards.yaml(docs/DB_DESIGN.md 第 6 節)。

載入時就做完整檢查:拼錯的條件名稱、不存在的方案、加碼指到不存在的對象,
都會在後端啟動時直接報錯,而不是在計算時默默算錯。
"""

from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path

import yaml

# 系統自動判斷、不存在 config 中的條件
SYSTEM_CONDITIONS = frozenset({'birthday_month'})
RATE_BY_VALUES = ('level', 'plan')
WHERE_KEYWORDS = ('domestic', 'overseas')
HOME_COUNTRY = 'TW'

_CARD_KEYS = {'name', 'bank', 'crawl_name', 'rate_by', 'settings', 'notes', 'schemes',
              'general', 'bonuses', 'skip_crawl_schemes'}
_SETTINGS_KEYS = {'level', 'plan', 'toggles', 'max_chosen_merchants'}
_SCHEME_KEYS = {'action', 'requires', 'covers', 'stacks_with_general', 'pick_merchants_when_plan', 'notes'}
_COVER_KEYS = {'category', 'country', 'overseas'}
_GENERAL_KEYS = {'name', 'rate', 'requires', 'where', 'notes', 'crawl_name'}
_BONUS_KEYS = {'requires', 'add', 'applies_to'}


class RulesError(ValueError):
    """cards.yaml 內容不合法。"""


@dataclass(frozen=True)
class Cover:
    category: str = None
    country: str = None
    overseas: bool = None

    def matches(self, category, country):
        if self.category is not None and category != self.category:
            return False
        if self.country is not None and country != self.country:
            return False
        if self.overseas is not None and (country != HOME_COUNTRY) != self.overseas:
            return False
        return True


@dataclass(frozen=True)
class SchemeRule:
    name: str
    action: str
    requires: frozenset
    covers: tuple
    stacks_with_general: bool
    pick_merchants_when_plan: frozenset
    notes: tuple


@dataclass(frozen=True)
class GeneralTier:
    name: str
    rate: Decimal
    requires: frozenset
    where: str
    notes: tuple
    crawl_name: str


@dataclass(frozen=True)
class Bonus:
    requires: frozenset
    add: Decimal
    applies_to: frozenset


@dataclass(frozen=True)
class CardRule:
    card_id: str
    name: str
    bank: str
    crawl_name: str
    rate_by: str               # 'level' / 'plan' / None
    options: tuple             # rate_by 的選項(等級或方案)
    toggles: dict              # 開關 key → 顯示名稱
    max_chosen_merchants: int
    notes: tuple
    schemes: dict              # 方案名稱 → SchemeRule
    general: tuple
    bonuses: tuple
    skip_crawl_schemes: dict

    @property
    def conditions(self):
        """這張卡的方案可能用到的所有條件名稱。"""
        return frozenset(self.toggles) | SYSTEM_CONDITIONS

    @property
    def pick_plans(self):
        """哪些方案(plan)需要挑店。"""
        plans = set()
        for scheme in self.schemes.values():
            plans |= scheme.pick_merchants_when_plan
        return frozenset(plans)

    def variant_for(self, config):
        """config 中決定回饋率的設定值;沒有 rate_by 的卡固定為 ''。"""
        if self.rate_by is None:
            return ''
        return config.get(self.rate_by, '')


@dataclass(frozen=True)
class Rules:
    cards: dict                # card_id → CardRule

    def by_crawl_name(self, crawl_name):
        for card in self.cards.values():
            if card.crawl_name == crawl_name:
                return card
        return None


# ---------------------------------------------------------------------------

def load_rules(path):
    path = Path(path)
    try:
        raw = yaml.safe_load(path.read_text(encoding='utf-8'))
    except yaml.YAMLError as e:
        raise RulesError(f'{path.name} 不是合法的 YAML:{e}') from e
    if not isinstance(raw, dict) or not isinstance(raw.get('cards'), dict) or not raw['cards']:
        raise RulesError(f'{path.name} 最上層需要 cards:,底下至少一張卡')

    cards = {cid: _parse_card(cid, body) for cid, body in raw['cards'].items()}

    crawl_names = [c.crawl_name for c in cards.values()]
    dup = {n for n in crawl_names if crawl_names.count(n) > 1}
    if dup:
        raise RulesError(f'crawl_name 重複:{"、".join(sorted(dup))}')
    return Rules(cards=cards)


def _parse_card(card_id, body):
    where = f'cards.{card_id}'
    _require_mapping(body, where)
    _no_unknown_keys(body, _CARD_KEYS, where)
    for key in ('name', 'bank', 'crawl_name'):
        if not isinstance(body.get(key), str) or not body[key].strip():
            raise RulesError(f'{where}.{key} 必填')

    rate_by = body.get('rate_by')
    if rate_by is not None and rate_by not in RATE_BY_VALUES:
        raise RulesError(f'{where}.rate_by 只能是 level、plan 或 null')

    settings = body.get('settings') or {}
    _require_mapping(settings, f'{where}.settings')
    _no_unknown_keys(settings, _SETTINGS_KEYS, f'{where}.settings')
    options = ()
    if rate_by is not None:
        options = tuple(_str_list(settings.get(rate_by), f'{where}.settings.{rate_by}'))
        if not options:
            raise RulesError(f'{where}.rate_by 是 {rate_by},settings.{rate_by} 要列出選項')
    for other in RATE_BY_VALUES:
        if other != rate_by and other in settings:
            raise RulesError(f'{where}.settings.{other} 只能在 rate_by 是 {other} 時使用')

    toggles = settings.get('toggles') or {}
    _require_mapping(toggles, f'{where}.settings.toggles')
    for key, label in toggles.items():
        if not isinstance(label, str) or not label.strip():
            raise RulesError(f'{where}.settings.toggles.{key} 要寫畫面上顯示的名稱')
        if key in SYSTEM_CONDITIONS or key in RATE_BY_VALUES or key == 'chosen_merchants':
            raise RulesError(f'{where}.settings.toggles.{key} 是保留名稱,不能當開關')
    allowed_conditions = frozenset(toggles) | SYSTEM_CONDITIONS

    def conditions(value, at):
        conds = frozenset(_str_list(value, at))
        unknown = conds - allowed_conditions
        if unknown:
            raise RulesError(f'{at} 有未定義的條件:{"、".join(sorted(unknown))}'
                             f'(可用的:{"、".join(sorted(allowed_conditions))})')
        return conds

    schemes = {}
    for name, sbody in (body.get('schemes') or {}).items():
        at = f'{where}.schemes.{name}'
        sbody = sbody or {}
        _require_mapping(sbody, at)
        _no_unknown_keys(sbody, _SCHEME_KEYS, at)
        covers = []
        for i, c in enumerate(sbody.get('covers') or []):
            _require_mapping(c, f'{at}.covers[{i}]')
            _no_unknown_keys(c, _COVER_KEYS, f'{at}.covers[{i}]')
            if not c:
                raise RulesError(f'{at}.covers[{i}] 至少要指定 category、country 或 overseas 其中之一')
            covers.append(Cover(category=c.get('category'), country=c.get('country'), overseas=c.get('overseas')))
        pick = frozenset(_str_list(sbody.get('pick_merchants_when_plan'), f'{at}.pick_merchants_when_plan'))
        if pick:
            if rate_by is None:
                raise RulesError(f'{at}.pick_merchants_when_plan 需要卡片設定 rate_by')
            bad = pick - set(options)
            if bad:
                raise RulesError(f'{at}.pick_merchants_when_plan 中的「{"、".join(sorted(bad))}」不在 settings.{rate_by} 選項中')
        schemes[name] = SchemeRule(
            name=name,
            action=sbody.get('action'),
            requires=conditions(sbody.get('requires'), f'{at}.requires'),
            covers=tuple(covers),
            stacks_with_general=bool(sbody.get('stacks_with_general', False)),
            pick_merchants_when_plan=pick,
            notes=tuple(_str_list(sbody.get('notes'), f'{at}.notes')),
        )

    max_chosen = settings.get('max_chosen_merchants')
    if any(s.pick_merchants_when_plan for s in schemes.values()):
        if not isinstance(max_chosen, int) or max_chosen <= 0:
            raise RulesError(f'{where}.settings.max_chosen_merchants 要填正整數(有方案需要挑店)')
    elif max_chosen is not None:
        raise RulesError(f'{where}.settings.max_chosen_merchants 只能在有方案需要挑店時使用')

    general = []
    for i, g in enumerate(body.get('general') or []):
        at = f'{where}.general[{i}]'
        _require_mapping(g, at)
        _no_unknown_keys(g, _GENERAL_KEYS, at)
        if not isinstance(g.get('name'), str) or not g['name'].strip():
            raise RulesError(f'{at}.name 必填')
        w = g.get('where')
        if w is not None and not isinstance(w, str):
            raise RulesError(f'{at}.where 要是 domestic、overseas 或國別代碼')
        general.append(GeneralTier(
            name=g['name'],
            rate=_decimal(g.get('rate'), f'{at}.rate'),
            requires=conditions(g.get('requires'), f'{at}.requires'),
            where=w,
            notes=tuple(_str_list(g.get('notes'), f'{at}.notes')),
            crawl_name=g.get('crawl_name'),
        ))
    if not general:
        raise RulesError(f'{where}.general 至少要有一層一般消費')
    if any(s in {g.name for g in general} for s in schemes):
        raise RulesError(f'{where}:方案與一般消費層不能同名')

    targets = set(schemes) | {g.name for g in general}
    bonuses = []
    for i, b in enumerate(body.get('bonuses') or []):
        at = f'{where}.bonuses[{i}]'
        _require_mapping(b, at)
        _no_unknown_keys(b, _BONUS_KEYS, at)
        applies = frozenset(_str_list(b.get('applies_to'), f'{at}.applies_to'))
        if not applies:
            raise RulesError(f'{at}.applies_to 要列出加在哪些方案或一般消費層')
        bad = applies - targets
        if bad:
            raise RulesError(f'{at}.applies_to 中的「{"、".join(sorted(bad))}」不是這張卡的方案或一般消費層')
        bonuses.append(Bonus(
            requires=conditions(b.get('requires'), f'{at}.requires'),
            add=_decimal(b.get('add'), f'{at}.add'),
            applies_to=applies,
        ))

    skip = body.get('skip_crawl_schemes') or {}
    _require_mapping(skip, f'{where}.skip_crawl_schemes')
    overlap = set(skip) & set(schemes)
    if overlap:
        raise RulesError(f'{where}:「{"、".join(sorted(overlap))}」同時出現在 schemes 與 skip_crawl_schemes')

    return CardRule(
        card_id=card_id,
        name=body['name'],
        bank=body['bank'],
        crawl_name=body['crawl_name'],
        rate_by=rate_by,
        options=options,
        toggles=dict(toggles),
        max_chosen_merchants=max_chosen,
        notes=tuple(_str_list(body.get('notes'), f'{where}.notes')),
        schemes=schemes,
        general=tuple(general),
        bonuses=tuple(bonuses),
        skip_crawl_schemes={k: str(v) for k, v in skip.items()},
    )


def consistency_warnings(rules, db_scheme_keys):
    """比對 cards.yaml 與資料庫中的方案(docs/DB_DESIGN.md 6.5)。

    db_scheme_keys:資料庫中的 {(card_id, scheme_name)}。回傳警告訊息清單。
    資料庫有、cards.yaml 沒有的方案,計算時會被忽略;cards.yaml 有、資料庫沒有的方案,
    代表爬蟲還沒匯入,點名店家的部分不會生效(分類涵蓋也一樣,因為沒有回饋率)。
    """
    warnings = []
    yaml_keys = {(c.card_id, name) for c in rules.cards.values() for name in c.schemes}
    for card_id, name in sorted(db_scheme_keys - yaml_keys):
        if card_id not in rules.cards:
            warnings.append(f'資料庫有卡片 {card_id} 的方案,但 cards.yaml 沒有這張卡,計算時忽略')
        else:
            warnings.append(f'資料庫有方案 {card_id}・{name},但 cards.yaml 沒有規則,計算時忽略')
    for card_id, name in sorted(yaml_keys - db_scheme_keys):
        warnings.append(f'cards.yaml 有方案 {card_id}・{name},但資料庫沒有資料(爬蟲還沒匯入?)')
    return warnings


# ---------------------------------------------------------------------------

def _require_mapping(value, at):
    if not isinstance(value, dict):
        raise RulesError(f'{at} 要是 key: value 的格式')


def _no_unknown_keys(mapping, allowed, at):
    unknown = set(mapping) - allowed
    if unknown:
        raise RulesError(f'{at} 有不認得的欄位:{"、".join(sorted(map(str, unknown)))}')


def _str_list(value, at):
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        raise RulesError(f'{at} 要是文字清單,例如 [a, b]')
    return value


def _decimal(value, at):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise RulesError(f'{at} 要是數字')
    return Decimal(str(value))
