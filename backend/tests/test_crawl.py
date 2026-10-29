"""爬蟲匯出檔的格式檢查、標記與匯入計畫(不需要資料庫)。"""

import json
from datetime import date
from decimal import Decimal

import pytest

from backend.config import BACKEND_DIR, REPO_ROOT
from backend.crawl import (Label, append_label, check_rows, classify, load_labels, load_rows,
                           row_in_effect)
from backend.importer import plan_import
from backend.rules import load_rules

TODAY = date(2026, 10, 1)


def row(**over):
    base = {'bank_name': '玉山銀行', 'card_name': 'Unicard', 'card_level': '任意選',
            'scheme_name': '百大特店', 'merchant_name': '台北101', 'reward_rate': 2.5}
    base.update(over)
    return base


# ---------------------------------------------------------------------------
# 格式檢查
# ---------------------------------------------------------------------------

def test_real_crawl_file_passes():
    rows = load_rows(REPO_ROOT / 'db' / 'crawl' / 'card_rewards_export_0908.json')
    result = check_rows(rows, ['CUBE卡', 'Unicard', '吉鶴卡'], today=TODAY)
    assert result.ok and result.warnings == []
    assert any(line.startswith('CUBE卡:867 列') for line in result.summary)


def test_errors_block_import():
    rows = [
        row(),
        {'card_name': 'Unicard'},                                  # 缺欄位
        row(reward_rate='2.5%'),                                   # 不是數字
        row(reward_rate=250),                                      # 超出範圍
        row(merchant_name='  '),                                   # 空的
        row(valid_from='2026/10/01'),                              # 日期格式
        row(valid_from='2026-12-01', valid_to='2026-11-01'),       # 起訖顛倒
        'not an object',
    ]
    result = check_rows(rows, today=TODAY)
    assert not result.ok
    joined = '\n'.join(result.errors)
    for text in ('第 2 列:缺少欄位', '第 3 列:reward_rate 要是數字', '第 4 列:reward_rate 250',
                 '第 5 列:merchant_name 是空的', '第 6 列:valid_from 要是 YYYY-MM-DD',
                 '第 7 列:valid_from 晚於 valid_to', '第 8 列:不是物件'):
        assert text in joined
    assert len(result.errors) == 7


def test_warnings_do_not_block():
    rows = [
        row(),
        row(reward_rate=3.5),                          # 同卡同等級同方案同店,回饋率不同
        row(merchant_name='鼎泰豐 '),                   # 前後空白
        row(merchant_name='誠品', reward_rate=0),
        row(merchant_name='舊活動', valid_to='2026-09-30'),
        row(card_name='新卡'),
        row(merchant_name='遠百', extra_field='x'),
    ]
    result = check_rows(rows, known_cards=['Unicard'], today=TODAY)
    assert result.ok
    joined = '\n'.join(result.warnings)
    for text in ('回饋率不同 2.5% / 3.5%', '前後有空白', 'reward_rate 是 0', '1 列的 valid_to 已過',
                 'cards.yaml 還沒有這張卡:「新卡」', '不認得的欄位(匯入時忽略):extra_field'):
        assert text in joined


def test_empty_file_is_an_error():
    assert not check_rows([]).ok


def test_load_csv_converts_types(tmp_path):
    path = tmp_path / 'crawl.csv'
    path.write_text('﻿bank_name,card_name,card_level,scheme_name,merchant_name,reward_rate,section\n'
                    '聯邦銀行,吉鶴卡,,國內日系特店,UNIQLO,5,\n', encoding='utf-8')
    (r,) = load_rows(path)
    assert r['reward_rate'] == 5.0 and r['card_level'] == '' and 'section' not in r
    assert check_rows([r], today=TODAY).ok


def test_load_json_must_be_a_list(tmp_path):
    path = tmp_path / 'crawl.json'
    path.write_text(json.dumps({'rows': []}), encoding='utf-8')
    with pytest.raises(ValueError, match='陣列'):
        load_rows(path)


def test_row_in_effect():
    assert row_in_effect(row(), TODAY)
    assert row_in_effect(row(valid_from='2026-10-01', valid_to='2026-10-01'), TODAY)
    assert not row_in_effect(row(valid_to='2026-09-30'), TODAY)
    assert not row_in_effect(row(valid_from='2026-10-02'), TODAY)


# ---------------------------------------------------------------------------
# 標記
# ---------------------------------------------------------------------------

def test_real_labels_file_loads():
    labels = load_labels()
    assert labels['國內一般消費'] == Label('general')
    assert labels['日本'].type == 'category'
    assert labels['玉山Wallet愛心捐款'].type == 'ignore'
    assert labels['國內餐飲(不含餐券)'].note.startswith('CUBE 樂饗購')


def test_classify_precedence():
    labels = {'日本': Label('category'), '王品瘋Pay': Label('merchant'), 'LINE Pay': Label('ignore')}
    assert classify('LINE Pay', labels, {'LINE Pay'}) == ('payment_method', 'cards.yaml')   # cards.yaml 優先
    assert classify(' 日本 ', labels) == ('category', 'label')
    assert classify('王品瘋Pay', labels) == ('merchant', 'label')                           # 標記蓋過關鍵字
    assert classify('街口支付', {}) == ('payment_method', 'keyword')
    assert classify('韓國', {}) == ('category', 'keyword')
    assert classify('國內一般消費', {}) == ('general', 'keyword')
    assert classify('鼎泰豐', {}) == ('merchant', 'default')


def test_append_label(tmp_path):
    path = tmp_path / 'labels.yaml'
    path.write_text('# 說明\nlabels:\n  日本: category\n', encoding='utf-8')
    assert append_label('Apple錢包指定交通卡', 'payment_method', note='趣旅行,目前不計算', path=path)
    assert append_label('foo: [bar]', 'ignore', path=path)                    # 特殊字元也能存
    assert not append_label('日本', 'general', path=path)                     # 已有標記不覆蓋
    labels = load_labels(path)
    assert labels['Apple錢包指定交通卡'] == Label('payment_method', '趣旅行,目前不計算')
    assert labels['foo: [bar]'] == Label('ignore')
    assert labels['日本'] == Label('category')
    with pytest.raises(ValueError, match='類型'):
        append_label('x', 'shop', path=path)


def test_bad_label_type_is_rejected(tmp_path):
    path = tmp_path / 'labels.yaml'
    path.write_text('labels:\n  日本: country\n', encoding='utf-8')
    with pytest.raises(ValueError, match='country'):
        load_labels(path)


# ---------------------------------------------------------------------------
# 匯入計畫
# ---------------------------------------------------------------------------

class FakeConn:
    """plan_import 只讀兩種東西:爬蟲原名對照,以及資料庫中現有的方案(這裡當成空的)。"""

    def __init__(self, source_map):
        self.source_map = source_map

    def cursor(self):
        conn = self

        class Cursor:
            def execute(self, sql, params=None):
                self.rows = list(conn.source_map.items()) if 'merchant_source_names' in sql else []

            def fetchall(self):
                return self.rows
        return Cursor()


@pytest.fixture(scope='module')
def rules():
    return load_rules(BACKEND_DIR / 'cards.yaml')


def test_plan_uses_labels(rules):
    rows = [row(card_level=lvl, merchant_name=name, reward_rate=rate)
            for lvl, rate in (('簡單選', 2.0), ('任意選', 2.5), ('UP選', 3.5))
            for name in ('台北101', 'LINE Pay', '日本', '玉山Wallet愛心捐款', '國內一般消費', '新開的店', '某某Pay')]
    labels = {'日本': Label('category', '百大特店含日本'), '玉山Wallet愛心捐款': Label('ignore'),
              '國內一般消費': Label('general')}
    plan = plan_import(FakeConn({'台北101': 54}), rules, rows, labels, today=TODAY)

    (scheme,) = plan.schemes
    assert scheme.rates == {'簡單選': Decimal('2.0'), '任意選': Decimal('2.5'), 'UP選': Decimal('3.5')}
    assert scheme.members == [(54, None, [])]
    assert plan.report['類別列:cards.yaml 沒有設定 covers,目前不計算'] == ['Unicard・百大特店:日本(百大特店含日本)']
    assert plan.report['方案內的一般消費列(略過)'] == ['Unicard・百大特店:國內一般消費']
    assert plan.report['行動支付(依 cards.yaml 計算)'][0] == 'Unicard・百大特店:LINE Pay'
    assert set(plan.unmapped) == {'新開的店'}                         # 店家要人確認
    assert plan.unlabeled == {'某某Pay': ('payment_method', 'esun_unicard', '百大特店', None)}
    assert not any('玉山Wallet愛心捐款' in line for lines in plan.report.values() for line in lines)


def test_plan_skips_rows_out_of_effect(rules):
    rows = [row(card_level=lvl) for lvl in ('簡單選', '任意選', 'UP選')]
    rows.append(row(merchant_name='遠百', valid_to='2026-09-30'))
    plan = plan_import(FakeConn({'台北101': 54, '遠百': 99}), rules, rows, {}, today=TODAY)
    assert plan.schemes[0].members == [(54, None, [])]
    assert plan.report['不在有效期間的列(略過)'] == ['1 列(valid_from 未到或 valid_to 已過)']


def test_real_crawl_needs_no_new_labels(rules):
    """0908 的每個非店家原文都已經在 labels.yaml 中,不需要再靠關鍵字猜。"""
    rows = load_rows(REPO_ROOT / 'db' / 'crawl' / 'card_rewards_export_0908.json')
    names = {r['merchant_name'] for r in rows}
    plan = plan_import(FakeConn({n: 1 for n in names}), rules, rows, load_labels(), today=TODAY)
    assert plan.unlabeled == {}
