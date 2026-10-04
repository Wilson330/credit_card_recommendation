"""本機手動測試工具:用終端機打後端 API,看推薦結果。

先在另一個視窗啟動後端:python -m backend.app
再執行(在專案根目錄):

  python -m backend.try_api
      用測試帳號 demo@local.test 登入(沒有就自動註冊),沿用上次的卡片設定

  python -m backend.try_api --cube "Level 2" --jiho-new --unicard 任意選 --e-bill --auto-debit --pick 台北101 --pick UNIQLO
      先設定卡片再開始查詢。沒指定的卡維持原本設定;--no-cube 等可移除卡片

  python -m backend.try_api --birthday-this-month
      把測試帳號的生日改成本月(測慶生月)。生日只能在註冊時設定,所以會換一個新的測試帳號

進入後輸入店名就會顯示自動補全的建議與推薦結果;輸入 #編號 可以直接用店家編號查;空白 Enter 離開。
直接用 curl 或 PowerShell 測試時要注意中文必須以 UTF-8 送出,這個工具已經處理好了。
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date

from .recommend import today_in_taiwan

PASSWORD = 'demo-password'


class Api:
    def __init__(self, base):
        self.base = base.rstrip('/')
        self.token = None

    def call(self, method, path, body=None, query=None):
        url = self.base + path
        if query:
            url += '?' + urllib.parse.urlencode(query)          # urlencode 一律用 UTF-8
        data = json.dumps(body, ensure_ascii=False).encode('utf-8') if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header('Content-Type', 'application/json; charset=utf-8')
        if self.token:
            req.add_header('Authorization', f'Bearer {self.token}')
        try:
            with urllib.request.urlopen(req) as resp:
                return resp.status, json.loads(resp.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode('utf-8') or '{}')


def login_or_register(api, email, birthday):
    status, data = api.call('POST', '/api/login', {'email': email, 'password': PASSWORD})
    if status == 401:
        status, data = api.call('POST', '/api/register', {
            'email': email, 'password': PASSWORD, 'full_name': '本機測試', 'birthday': birthday.isoformat()})
        if status != 201:
            raise SystemExit(f'註冊失敗:{data}')
        print(f'已註冊測試帳號 {email}(生日 {birthday})')
        status, data = api.call('POST', '/api/login', {'email': email, 'password': PASSWORD})
    if status != 200:
        raise SystemExit(f'登入失敗:{data}')
    api.token = data['token']
    print(f'已登入 {email}(生日 {data["user"]["birthday"]})')


def resolve_ids(api, names):
    ids = []
    for name in names:
        _, suggestions = api.call('GET', '/api/merchants/suggest', query={'q': name})
        if not suggestions:
            raise SystemExit(f'找不到店家:{name}')
        ids.append(suggestions[0]['merchant_id'])
        print(f'  挑店:{name} → #{suggestions[0]["merchant_id"]} {suggestions[0]["name"]}')
    return ids


def apply_card_args(api, args):
    def put(card_id, config):
        status, data = api.call('PUT', f'/api/user/cards/{card_id}', {'config': config})
        if status != 200:
            raise SystemExit(f'設定 {card_id} 失敗:{data.get("error")}')

    if args.cube:
        put('cathay_cube', {'level': args.cube, 'kids_club': args.kids_club})
    if args.jiho_new is not None:
        put('ubot_jiho', {'new_customer': args.jiho_new})
    if args.unicard:
        config = {'plan': args.unicard, 'e_bill': args.e_bill, 'auto_debit': args.auto_debit}
        if args.pick:
            config['chosen_merchants'] = resolve_ids(api, args.pick)
        put('esun_unicard', config)
    for flag, card_id in (('no_cube', 'cathay_cube'), ('no_jiho', 'ubot_jiho'), ('no_unicard', 'esun_unicard')):
        if getattr(args, flag):
            api.call('DELETE', f'/api/user/cards/{card_id}')


def show_cards(api):
    _, cards = api.call('GET', '/api/user/cards')
    print('\n目前的卡片:' if cards else '\n目前沒有卡片,用 --cube / --jiho-new / --unicard 新增')
    for c in cards:
        print(f'  {c.get("card_name", c["card_id"])}:{json.dumps(c["config"], ensure_ascii=False)}')


def show_recommendation(api, text):
    if text.startswith('#') and text[1:].isdigit():
        status, data = api.call('POST', '/api/recommend', {'merchant_id': int(text[1:])})
    else:
        _, suggestions = api.call('GET', '/api/merchants/suggest', query={'q': text})
        if suggestions:
            print('  建議:' + '、'.join(f'#{s["merchant_id"]} {s["name"]}' for s in suggestions))
        status, data = api.call('POST', '/api/recommend', {'query': text})
    if status != 200:
        print(f'  錯誤:{data.get("error")}')
        return
    m = data['merchant']
    print(f'  店家:{m["name"]}(#{m["merchant_id"]},{m["category"]},{m["country"]})' if m else f'  {data["message"]}')
    for i, r in enumerate(data['results'], 1):
        action = f',{r["required_action"]}' if r['required_action'] else ''
        print(f'  {i}. {r["card_name"]:<8} {r["reward_rate"]:>5.2f}%  {r["scheme_name"]}{action}')
        extra = [n for n in r['notes'] if n != '實際回饋依當期公告為準']
        if extra:
            print(f'       註:{";".join(extra)}')
    if not data['results']:
        print('  (沒有卡片)')


def main(argv=None):
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stdin.reconfigure(encoding='utf-8')
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--base', default='http://127.0.0.1:5000')
    p.add_argument('--email', default='demo@local.test')
    p.add_argument('--birthday-this-month', action='store_true')
    p.add_argument('--cube', choices=['Level 1', 'Level 2', 'Level 3'])
    p.add_argument('--kids-club', action='store_true')
    p.add_argument('--jiho-new', dest='jiho_new', action='store_true', default=None)
    p.add_argument('--jiho-old', dest='jiho_new', action='store_false')
    p.add_argument('--unicard', choices=['簡單選', '任意選', 'UP選'])
    p.add_argument('--e-bill', action='store_true')
    p.add_argument('--auto-debit', action='store_true')
    p.add_argument('--pick', action='append', help='任意選挑的店,可重複')
    p.add_argument('--no-cube', action='store_true')
    p.add_argument('--no-jiho', action='store_true')
    p.add_argument('--no-unicard', action='store_true')
    args = p.parse_args(argv)

    api = Api(args.base)
    try:
        api.call('GET', '/api/health')
    except urllib.error.URLError:
        raise SystemExit(f'連不到後端 {args.base},請先在另一個視窗執行:python -m backend.app')

    email, birthday = args.email, date(1990, 1, 1)
    if args.birthday_this_month:
        month = today_in_taiwan().month
        email, birthday = email.replace('@', f'+bday{month}@'), date(1990, month, 1)
    login_or_register(api, email, birthday)
    apply_card_args(api, args)
    show_cards(api)

    print('\n輸入店名查推薦(#編號 = 用店家編號查;直接 Enter 離開)')
    while True:
        try:
            text = input('\n店名> ').strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not text:
            break
        show_recommendation(api, text)


if __name__ == '__main__':
    main()
