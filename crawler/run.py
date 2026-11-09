"""執行爬蟲:python -m crawler.run <card_id> [--refresh] [--out 路徑] [--compare 參考檔]

抓網頁(預設讀快取)→ 解析 → 寫匯出檔與條款檔 → 自動檢查並寫報告。

解析方式二選一:
  - crawler/sites/<card_id>.yaml 有食譜就用食譜引擎(crawler/recipe.py)
  - 否則用 crawler/<card_id>.py 模組(頁面太特殊、食譜寫不出來時)
"""
import argparse
import importlib
import sys
from pathlib import Path

from crawler import checks, diff, recipe
from crawler.common import CRAWL_DIR, ROOT, fetch, finalize, write_export, write_terms

MODULE_CARDS = ['taishin_richart']
LEVEL_MARK = {checks.ERROR: '❌', checks.WARN: '⚠️', checks.INFO: 'ℹ️'}


def available_cards():
    return sorted(set(MODULE_CARDS) | {p.stem for p in recipe.SITES_DIR.glob('*.yaml')})


def _crawl_recipe(card_id, rcp, refresh):
    html, fetched_at = fetch(rcp['url'], card_id, refresh=refresh)
    text = recipe.page_text(html)
    rows, notes = recipe.parse(rcp, html, rcp['url'])
    source = rcp.get('source_url', rcp['url'])
    write_terms(card_id, '00_卡片頁', source, fetched_at, text)
    fetched = [fetched_at]
    for i, url in enumerate(rcp.get('terms_urls') or [], start=1):
        try:
            t_html, t_at = fetch(url, card_id, refresh=refresh)
        except Exception as e:   # 條款頁抓不到不擋匯出,記在報告
            notes.append(f'條款頁抓取失敗:{url}({e})')
            continue
        write_terms(card_id, f'{i:02d}_條款', url, t_at, recipe.page_text(t_html))
    return rows, notes, [text], fetched


def _crawl_module(card_id, refresh):
    module = importlib.import_module(f'crawler.{card_id}')
    rows, notes, texts, fetched = [], [], [], []
    for url in module.URLS:
        html, fetched_at = fetch(url, card_id, refresh=refresh)
        fetched.append(fetched_at)
        page_rows, terms, page_notes, text = module.parse(html, url)
        rows += page_rows
        notes += page_notes
        texts.append(text)
        for title, body in terms.items():
            write_terms(card_id, title, url, fetched_at, body)
    return rows, notes, texts, fetched


def run(card_id, refresh=False, out=None, compare=None):
    rcp = recipe.load(card_id)
    if rcp:
        rows, notes, texts, fetched = _crawl_recipe(card_id, rcp, refresh)
    else:
        rows, notes, texts, fetched = _crawl_module(card_id, refresh)

    fetched_at = max(fetched)
    rows = finalize(rows, fetched_at)
    stamp = fetched_at[:10].replace('-', '')
    out = Path(out) if out else CRAWL_DIR / f'card_rewards_export_{stamp}_{card_id}.json'
    previous = compare or diff.latest_previous(card_id, out, rows[0]['card_name'] if rows else None)
    write_export(rows, out)

    issues = checks.check(rows, '\n'.join(texts))
    changes = diff.compare(diff.load(previous), rows) if previous else None
    report = ROOT / 'crawler' / 'reports' / f'{card_id}_{stamp}.md'
    write_report(report, card_id, out, rows, notes, issues, fetched_at, previous, changes)
    return out, report, rows, notes, issues, changes


def _rel(path):
    """專案內的檔案顯示相對路徑,專案外的顯示完整路徑。"""
    path = Path(path).resolve()
    return (path.relative_to(ROOT) if ROOT in path.parents else path).as_posix()


def write_report(path, card_id, out, rows, notes, issues, fetched_at, previous=None, changes=None):
    lines = [f'# {card_id} 爬蟲檢查報告', '',
             f'- 抓取時間:{fetched_at}',
             f'- 匯出檔:`{_rel(out)}`({len(rows)} 列)', '',
             '## 列數與回饋率', '', '```', checks.summary(rows), '```', '',
             '## 解析備註', '']
    lines += [f'- {n}' for n in dict.fromkeys(notes)] or ['- (無)']
    lines += ['', '## 自動檢查', '']
    if not issues:
        lines.append('- 沒有發現問題')
    for i in sorted(issues, key=lambda x: [checks.ERROR, checks.WARN, checks.INFO].index(x['level'])):
        ids = f'(id {", ".join(map(str, i["ids"][:8]))}{"…" if len(i["ids"]) > 8 else ""})' if i['ids'] else ''
        lines.append(f'- {LEVEL_MARK[i["level"]]} [{i["check"]}] {i["message"]} {ids}'.rstrip())
    lines += ['', '## 與參考檔比較', '']
    if previous is None:
        lines.append('- 沒有參考檔(第一次爬這張卡)。可用 `--compare <檔案>` 指定')
    else:
        lines.append(f'參考檔:`{_rel(previous)}`')
        lines.append('')
        lines += diff.format_changes(changes)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('card', choices=available_cards())
    parser.add_argument('--refresh', action='store_true', help='重新抓網頁,不用快取')
    parser.add_argument('--out', help='匯出檔路徑(預設 db/crawl/card_rewards_export_<日期>_<卡>.json)')
    parser.add_argument('--compare', help='拿來比較的參考檔(預設:db/crawl 中同一張卡最近的一份)')
    args = parser.parse_args(argv)

    try:
        out, report, rows, notes, issues, changes = run(args.card, args.refresh, args.out, args.compare)
    except recipe.RecipeError as e:
        print(f'食譜與網頁對不上:{e}\n網頁可能改版了,請更新 crawler/sites/{args.card}.yaml')
        return 2
    counts = {lv: sum(i['level'] == lv for i in issues) for lv in LEVEL_MARK}
    print(f'匯出 {len(rows)} 列 → {_rel(out)}')
    print(checks.summary(rows))
    print(f'檢查:錯誤 {counts["error"]}、警告 {counts["warn"]}、提示 {counts["info"]};備註 {len(set(notes))} 則')
    if changes is not None:
        print('比較:' + diff.one_line(changes))
    print(f'報告 → {_rel(report)}')
    return 1 if counts['error'] else 0


if __name__ == '__main__':
    sys.exit(main())
