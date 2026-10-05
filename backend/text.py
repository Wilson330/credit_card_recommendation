"""店名相關的文字處理,後端查詢與匯入腳本共用。"""

import re

FULLWIDTH_SPACE = '　'


def normalize(text):
    """與資料庫產生欄位相同的正規化:去頭尾空白、轉小寫、移除半形與全形空白。

    改這裡就要同步改 db/schema.sql 中 normalized_name / normalized_alias 的定義,
    否則使用者輸入與資料庫比對的結果會不一致。
    """
    return text.strip().lower().replace(' ', '').replace(FULLWIDTH_SPACE, '')


def like_escape(text):
    """跳脫 LIKE 的萬用字元,讓使用者輸入的 % 與 _ 被當成一般字元。"""
    return text.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')


# ---- 爬蟲中「不是店家」的列 ----

COUNTRY_NAMES = {
    '日本', '韓國', '美國', '中國', '香港', '新加坡', '馬來西亞', '泰國', '越南',
    '菲律賓', '澳洲', '紐西蘭', '加拿大', '英國', '法國', '德國', '義大利', '西班牙', '澳門',
}
_BUCKET_RE = re.compile(r'(一般消費|海外實體消費|日幣消費|飯店住宿|行動支付|保費)')
_PAYMENT_RE = re.compile(r'(支付|錢包|Wallet|iPASS|icash|悠遊付|Pay$|PAY$)')


def non_merchant_reason(name):
    """不是店家時回傳原因(國別、付款工具、一般消費類),是店家回傳 None。"""
    n = name.strip()
    if n in COUNTRY_NAMES:
        return '國別'
    if _BUCKET_RE.search(n):
        return '一般消費/地點/保費類'
    if _PAYMENT_RE.search(n):
        return '付款工具'
    return None


# ---- 括號中的限制說明 ----

_CONSTRAINT_KEYWORDS = ['限', '不含', '僅', '需', '限定', '週', '街邊店', '儲值', '電子票券', '結帳']
_BRACKET_RE = re.compile(r'^(.*?)\s*[\(（](.+?)[\)）]\s*$')


def split_constraint(raw):
    """把結尾括號中的限制說明拆出來:'金子半之助(限週一至週四)' → ('金子半之助', '限週一至週四')。

    只處理名稱結尾的括號,而且括號內要有限制關鍵字。像「7-ELEVEN(日本)」這種括號是店名的
    一部分,不含限制關鍵字,原樣保留。
    """
    name = raw.strip()
    m = _BRACKET_RE.match(name)
    if m and any(kw in m.group(2).strip() for kw in _CONSTRAINT_KEYWORDS):
        return m.group(1).strip(), m.group(2).strip()
    return name, None
