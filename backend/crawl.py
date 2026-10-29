"""爬蟲匯出檔的讀取、格式檢查與列的標記(docs/CRAWL_FORMAT.md)。

格式檢查不需要資料庫,Allen 跑完爬蟲後就能先檢查:
  python -m backend.importer 匯出檔.json --check
"""

import csv
import json
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

import yaml

from .config import REPO_ROOT
from .text import non_merchant_reason

LABELS_FILE = REPO_ROOT / 'db' / 'crawl' / 'labels.yaml'

REQUIRED_FIELDS = ('bank_name', 'card_name', 'card_level', 'scheme_name', 'merchant_name', 'reward_rate')
OPTIONAL_FIELDS = ('id', 'updated_at', 'source_url', 'section', 'valid_from', 'valid_to')
TEXT_FIELDS = ('bank_name', 'card_name', 'card_level', 'scheme_name', 'merchant_name')

_DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')


# ---------------------------------------------------------------------------
# 讀檔
# ---------------------------------------------------------------------------

class CrawlFileError(ValueError):
    """檔案讀不進來(不是 JSON 陣列、CSV 沒有標題列等)。"""


def load_rows(path):
    """讀爬蟲匯出檔,回傳 dict 清單。支援 .json(物件陣列)與 .csv(第一列是欄位名稱)。"""
    path = Path(path)
    if path.suffix.lower() == '.csv':
        with path.open(encoding='utf-8-sig', newline='') as f:
            reader = csv.DictReader(f)
            if not reader.fieldnames:
                raise CrawlFileError(f'{path.name} 沒有標題列')
            return [_from_csv(row) for row in reader]
    try:
        data = json.loads(path.read_text(encoding='utf-8-sig'))
    except json.JSONDecodeError as e:
        raise CrawlFileError(f'{path.name} 不是合法的 JSON:{e}') from e
    if not isinstance(data, list):
        raise CrawlFileError(f'{path.name} 最外層要是陣列,每一列是一個物件')
    return data


def _from_csv(row):
    """CSV 的值都是字串:空字串視為沒填,reward_rate 轉成數字(轉不了就留給格式檢查報錯)。"""
    out = {k: v for k, v in row.items() if k is not None and v != ''}
    if 'card_level' in row and row['card_level'] == '':
        out['card_level'] = ''
    if 'reward_rate' in out:
        try:
            out['reward_rate'] = float(out['reward_rate'])
        except ValueError:
            pass
    return out


# ---------------------------------------------------------------------------
# 格式檢查
# ---------------------------------------------------------------------------

@dataclass
class CheckResult:
    errors: list
    warnings: list
    summary: list          # 每張卡一行的摘要

    @property
    def ok(self):
        return not self.errors


def _where(i, row):
    rid = row.get('id') if isinstance(row, dict) else None
    return f'第 {i + 1} 列' + (f'(id {rid})' if rid is not None else '')


def _parse_date(value):
    if not isinstance(value, str) or not _DATE_RE.match(value):
        return None
    try:
        return datetime.strptime(value, '%Y-%m-%d').date()
    except ValueError:
        return None


def check_rows(rows, known_cards=(), today=None):
    """檢查爬蟲列的格式。errors 代表不能匯入;warnings 要看過,但不擋匯入。

    known_cards:cards.yaml 中各卡的 crawl_name,用來提醒哪些卡還沒設定(新卡要先加進 cards.yaml)。
    """
    today = today or date.today()
    errors, warnings = [], []
    if not rows:
        errors.append('檔案中沒有任何資料列')
        return CheckResult(errors, warnings, [])

    unknown_fields = set()
    seen = {}                                   # (卡, 等級, 方案, 店名) → (列號, 回饋率)
    per_card = defaultdict(lambda: {'rows': 0, 'levels': set(), 'schemes': set()})
    expired = not_yet = 0

    for i, row in enumerate(rows):
        where = _where(i, row)
        if not isinstance(row, dict):
            errors.append(f'{where}:不是物件')
            continue
        unknown_fields.update(k for k in row if k not in REQUIRED_FIELDS + OPTIONAL_FIELDS)

        missing = [k for k in REQUIRED_FIELDS if k not in row or row[k] is None]
        if missing:
            errors.append(f'{where}:缺少欄位 {"、".join(missing)}')
            continue
        bad_text = [k for k in TEXT_FIELDS if not isinstance(row[k], str)]
        if bad_text:
            errors.append(f'{where}:{"、".join(bad_text)} 要是文字')
            continue
        empty = [k for k in TEXT_FIELDS if k != 'card_level' and not row[k].strip()]
        if empty:
            errors.append(f'{where}:{"、".join(empty)} 是空的')
            continue
        spaced = [k for k in TEXT_FIELDS if row[k] != row[k].strip()]
        if spaced:
            warnings.append(f'{where}:{"、".join(spaced)} 前後有空白「{row[spaced[0]]}」')

        rate = row['reward_rate']
        if isinstance(rate, bool) or not isinstance(rate, (int, float)):
            errors.append(f'{where}:reward_rate 要是數字(單位 %,例如 2.5),目前是「{rate}」')
            continue
        if not 0 <= rate <= 100:
            errors.append(f'{where}:reward_rate {rate} 不在 0 ~ 100 之間(單位是 %)')
            continue
        if rate == 0:
            warnings.append(f'{where}:reward_rate 是 0「{row["merchant_name"]}」')

        dates = {}
        for k in ('valid_from', 'valid_to'):
            if row.get(k) is None:
                continue
            d = _parse_date(row[k])
            if d is None:
                errors.append(f'{where}:{k} 要是 YYYY-MM-DD,目前是「{row[k]}」')
            else:
                dates[k] = d
        if 'valid_from' in dates and 'valid_to' in dates and dates['valid_from'] > dates['valid_to']:
            errors.append(f'{where}:valid_from 晚於 valid_to')
        if dates.get('valid_to') and dates['valid_to'] < today:
            expired += 1
        if dates.get('valid_from') and dates['valid_from'] > today:
            not_yet += 1

        key = (row['card_name'], row['card_level'], row['scheme_name'], row['merchant_name'].strip())
        if key in seen:
            first, first_rate = seen[key]
            if first_rate != rate:
                warnings.append(f'{where}:與第 {first + 1} 列重複(同卡、同等級、同方案、同店),'
                                f'回饋率不同 {first_rate}% / {rate}%,匯入時取較高者')
            else:
                warnings.append(f'{where}:與第 {first + 1} 列完全重複')
        else:
            seen[key] = (i, rate)

        card = per_card[row['card_name']]
        card['rows'] += 1
        card['levels'].add(row['card_level'])
        card['schemes'].add(row['scheme_name'])

    if unknown_fields:
        warnings.append(f'不認得的欄位(匯入時忽略):{"、".join(sorted(unknown_fields))}')
    if expired:
        warnings.append(f'{expired} 列的 valid_to 已過,匯入時略過')
    if not_yet:
        warnings.append(f'{not_yet} 列的 valid_from 還沒到,匯入時略過')
    known = set(known_cards)
    for name in sorted(per_card):
        if known and name not in known:
            warnings.append(f'cards.yaml 還沒有這張卡:「{name}」(新卡要先在 cards.yaml 加一段才能匯入)')

    summary = [
        f'{name}:{c["rows"]} 列、{len(c["schemes"])} 個方案、等級 {"、".join(sorted(c["levels"])) or "(無)"}'
        for name, c in sorted(per_card.items())
    ]
    return CheckResult(errors, warnings, summary)


def row_in_effect(row, today=None):
    """依 valid_from / valid_to 判斷這一列今天是否有效;沒填就視為有效。"""
    today = today or date.today()
    start, end = _parse_date(row.get('valid_from')), _parse_date(row.get('valid_to'))
    return not ((start and start > today) or (end and end < today))


# ---------------------------------------------------------------------------
# 列的標記
# ---------------------------------------------------------------------------

LABEL_TYPES = {
    'merchant': '店家',
    'general': '一般消費',
    'payment_method': '行動支付',
    'category': '一整類消費或地區',
    'ignore': '不是消費,略過',
}


@dataclass(frozen=True)
class Label:
    type: str
    note: str = None


def load_labels(path=LABELS_FILE):
    """讀 db/crawl/labels.yaml:爬蟲 merchant_name 原文 → Label。"""
    path = Path(path)
    if not path.exists():
        return {}
    raw = yaml.safe_load(path.read_text(encoding='utf-8')) or {}
    entries = raw.get('labels') or {}
    if not isinstance(entries, dict):
        raise ValueError(f'{path.name}:labels 要是「原文: 類型」的對照')
    labels = {}
    for text, value in entries.items():
        if isinstance(value, str):
            label = Label(value)
        elif isinstance(value, dict) and set(value) <= {'type', 'note'} and 'type' in value:
            label = Label(value['type'], value.get('note'))
        else:
            raise ValueError(f'{path.name}:「{text}」的值要是類型,或 {{type: 類型, note: 說明}}')
        if label.type not in LABEL_TYPES:
            raise ValueError(f'{path.name}:「{text}」的類型 {label.type} 不存在,'
                             f'可用的類型:{"、".join(LABEL_TYPES)}')
        labels[str(text).strip()] = label
    return labels


def append_label(text, label_type, note=None, path=LABELS_FILE):
    """在 labels.yaml 最後加一筆(labels 必須是檔案中最後一個區塊)。已有同一原文時回傳 False。"""
    if label_type not in LABEL_TYPES:
        raise ValueError(f'類型 {label_type} 不存在,可用的類型:{"、".join(LABEL_TYPES)}')
    path = Path(path)
    if text.strip() in load_labels(path):
        return False
    key = json.dumps(text.strip(), ensure_ascii=False)          # JSON 字串也是合法的 YAML 字串
    value = label_type if note is None else '{ type: %s, note: %s }' % (label_type, json.dumps(note, ensure_ascii=False))
    content = path.read_text(encoding='utf-8') if path.exists() else 'labels:\n'
    if not content.endswith('\n'):
        content += '\n'
    path.write_text(content + f'  {key}: {value}\n', encoding='utf-8')
    return True


def classify(text, labels, payment_crawl_names=frozenset()):
    """判斷爬蟲的一列是什麼。回傳 (類型, 依據)。

    依據:cards.yaml(列在方案的 payment_methods)> label(labels.yaml)> keyword(依店名關鍵字猜)
    > default(當成店家)。keyword 的結果要補進 labels.yaml,下次就不用猜。
    """
    key = text.strip()
    if key in payment_crawl_names:
        return 'payment_method', 'cards.yaml'
    if key in labels:
        return labels[key].type, 'label'
    reason = non_merchant_reason(key)
    if reason == '付款工具':
        return 'payment_method', 'keyword'
    if reason == '國別':
        return 'category', 'keyword'
    if reason:
        return 'general', 'keyword'
    return 'merchant', 'default'
