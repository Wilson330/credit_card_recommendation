"""各卡爬蟲共用:抓網頁(含快取與 robots.txt)、切店名、寫匯出檔與條款檔。"""
import hashlib
import json
import re
import time
import urllib.robotparser
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit

import requests

ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = ROOT / 'crawler' / '.cache'
CRAWL_DIR = ROOT / 'db' / 'crawl'

USER_AGENT = 'Mozilla/5.0 (compatible; my-first-app-crawler/0.1; personal research)'
DELAY_SECONDS = 3
_last_request = 0.0

# 段落有兩層時(例如 Chill刷 的「瘋聚會」底下的「【日常續命】」)用這個接起來
SECTION_SEP = ' > '

# 匯出檔欄位順序,照 docs/CRAWL_FORMAT.md
FIELDS = ['id', 'bank_name', 'card_name', 'card_level', 'scheme_name', 'merchant_name', 'reward_rate',
          'section', 'source_url', 'valid_from', 'valid_to', 'updated_at']


def robots_allowed(url):
    """robots.txt 不存在或讀不到時視為允許;明確禁止才回 False。"""
    parts = urlsplit(url)
    robots_url = f'{parts.scheme}://{parts.netloc}/robots.txt'
    try:
        resp = requests.get(robots_url, headers={'User-Agent': USER_AGENT}, timeout=15)
    except requests.RequestException:
        return True
    if resp.status_code != 200 or 'text/plain' not in resp.headers.get('Content-Type', ''):
        return True
    parser = urllib.robotparser.RobotFileParser()
    parser.parse(resp.text.splitlines())
    return parser.can_fetch(USER_AGENT, url)


def fetch(url, card_id, refresh=False):
    """抓網頁並存快取。回傳 (html, 抓取時間)。

    有快取且沒有 refresh 時直接讀快取,所以重跑結果一致;要抓最新版請加 refresh。
    """
    global _last_request
    key = hashlib.sha1(url.encode('utf-8')).hexdigest()[:12]
    html_path = CACHE_DIR / card_id / f'{key}.html'
    meta_path = html_path.with_suffix('.json')
    if html_path.exists() and meta_path.exists() and not refresh:
        meta = json.loads(meta_path.read_text(encoding='utf-8'))
        return html_path.read_text(encoding='utf-8'), meta['fetched_at']

    if not robots_allowed(url):
        raise RuntimeError(f'robots.txt 不允許抓取:{url}')
    wait = DELAY_SECONDS - (time.time() - _last_request)
    if wait > 0:
        time.sleep(wait)
    resp = requests.get(url, headers={'User-Agent': USER_AGENT}, timeout=30)
    _last_request = time.time()
    resp.raise_for_status()
    resp.encoding = resp.apparent_encoding if resp.encoding in (None, 'ISO-8859-1') else resp.encoding
    fetched_at = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    html_path.parent.mkdir(parents=True, exist_ok=True)
    html_path.write_text(resp.text, encoding='utf-8')
    meta_path.write_text(json.dumps({'url': url, 'fetched_at': fetched_at}, ensure_ascii=False),
                         encoding='utf-8')
    return resp.text, fetched_at


def clean(text):
    """把換行、全形空白、連續空白收成一個半形空白;括號內側的空白(網頁換行造成)去掉。"""
    text = re.sub(r'\s+', ' ', text.replace('　', ' ')).strip()
    return re.sub(r'\s+([)）])', r'\1', re.sub(r'([(（])\s+', r'\1', text))


def split_names(text, separators='｜/、'):
    """依分隔符號切店名,括號裡的不切(例如「MITSUI OUTLET PARK (林口/台中港/台南)」)。"""
    names, buf, depth = [], [], 0
    for ch in text:
        if ch in '(（':
            depth += 1
        elif ch in ')）':
            depth = max(depth - 1, 0)
        if ch in separators and depth == 0:
            names.append(''.join(buf))
            buf = []
        else:
            buf.append(ch)
    names.append(''.join(buf))
    return [clean(n) for n in names if clean(n)]


def rate(text):
    """'3.3' -> 3.3;整數回傳 float,與 0908 一致。"""
    return float(text.strip())


def finalize(rows, fetched_at):
    """排序、編號、補 updated_at,並依 FIELDS 排欄位。排序固定,重跑輸出一致。"""
    def key(r):
        return (r['card_name'], r['card_level'], r['scheme_name'], r.get('section', ''), r['merchant_name'])

    out = []
    for i, r in enumerate(sorted(rows, key=key), start=1):
        r = dict(r, id=i, updated_at=fetched_at)
        out.append({f: r[f] for f in FIELDS if r.get(f) not in (None, '')})
    return out


def write_export(rows, path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(rows, ensure_ascii=False, indent=4) + '\n', encoding='utf-8')
    return path


def write_terms(card_id, name, url, fetched_at, text):
    """條款存成 db/crawl/terms/<card_id>/<name>.txt,開頭寫來源與抓取日期。"""
    safe = re.sub(r'[\\/:*?"<>|\s]+', '_', name).strip('_')
    path = CRAWL_DIR / 'terms' / card_id / f'{safe}.txt'
    path.parent.mkdir(parents=True, exist_ok=True)
    body = '\n'.join(line.strip() for line in text.splitlines() if line.strip())
    path.write_text(f'來源:{url}\n抓取時間:{fetched_at}\n標題:{name}\n\n{body}\n', encoding='utf-8')
    return path
