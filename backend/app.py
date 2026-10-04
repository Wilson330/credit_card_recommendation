"""後端 API(docs/DB_DESIGN.md 7.6)。

本機啟動(在專案根目錄):
  python -m backend.app                     http://127.0.0.1:5000,只有本機連得到
  python -m backend.app --host 0.0.0.0      讓同網路的手機連(此時強制關閉 debug)
  python -m backend.app --debug             開除錯模式(只允許在 127.0.0.1)

除了 /api/register、/api/login、/api/health,其他 API 都要帶
  Authorization: Bearer <登入取得的 token>
"""

import argparse
import logging
import sys
from functools import wraps

from flask import Flask, g, jsonify, request
from flask_cors import CORS
from werkzeug.exceptions import HTTPException

from . import auth, service
from .cardconfig import validate_config
from .config import load_settings
from .db import connection
from .errors import ApiError
from .recommend import recommend as compute_recommendations, today_in_taiwan
from .rules import consistency_warnings, load_rules

log = logging.getLogger('backend')

NOT_FOUND_MESSAGE = '此店家不在回饋名單中,以一般消費計算'


def create_app(settings=None, rules=None):
    settings = settings or load_settings()
    rules = rules or load_rules(settings.cards_yaml)   # cards.yaml 有錯就在啟動時失敗

    app = Flask(__name__)
    app.config['JSON_AS_ASCII'] = False                 # 回應中的中文不要轉成 \uXXXX
    app.config['JSON_SORT_KEYS'] = False
    CORS(app)

    _check_consistency(settings, rules)

    def db():
        return connection(settings)

    def require_login(view):
        @wraps(view)
        def wrapper(*args, **kwargs):
            g.user_id = auth.user_id_from_header(request.headers.get('Authorization'), settings.secret_key)
            return view(*args, **kwargs)
        return wrapper

    def body():
        data = request.get_json(silent=True)
        if not isinstance(data, dict):
            raise ApiError(400, '請用 JSON 格式送出資料')
        return data

    def card_rule_or_404(card_id):
        card = rules.cards.get(card_id)
        if card is None:
            raise ApiError(404, f'沒有這張卡:{card_id}')
        return card

    @app.errorhandler(ApiError)
    def handle_api_error(e):
        return jsonify({'error': e.message}), e.status

    @app.errorhandler(404)
    def handle_not_found(_):
        return jsonify({'error': '找不到這個 API'}), 404

    @app.errorhandler(405)
    def handle_method(_):
        return jsonify({'error': '這個 API 不支援這個方法'}), 405

    @app.errorhandler(Exception)
    def handle_unexpected(e):
        if isinstance(e, HTTPException):
            return jsonify({'error': e.description}), e.code
        log.exception('未預期的錯誤')
        return jsonify({'error': '伺服器發生錯誤'}), 500

    # ---- 不需要登入 ----

    @app.route('/api/health', methods=['GET'])
    def health():
        with db() as conn:
            cur = conn.cursor()
            cur.execute('SELECT COUNT(*) FROM merchants')
            (merchants,) = cur.fetchone()
        return jsonify({'status': 'ok', 'cards': list(rules.cards), 'merchants': merchants})

    @app.route('/api/register', methods=['POST'])
    def register():
        with db() as conn:
            user_id = auth.register(conn, body())
        return jsonify({'message': '註冊成功', 'user_id': user_id}), 201

    @app.route('/api/login', methods=['POST'])
    def login():
        with db() as conn:
            user = auth.login(conn, body())
        return jsonify({
            'token': auth.create_token(user['id'], settings.secret_key),
            'user': {'email': user['email'], 'full_name': user['full_name'],
                     'birthday': user['birthday'].isoformat()},
        })

    # ---- 搜尋與推薦 ----

    @app.route('/api/merchants/suggest', methods=['GET'])
    @require_login
    def suggest():
        with db() as conn:
            return jsonify(service.suggest(conn, request.args.get('q', '')))

    @app.route('/api/recommend', methods=['POST'])
    @require_login
    def recommend():
        data = body()
        merchant_id, query = data.get('merchant_id'), data.get('query')
        if (merchant_id is None) == (query is None):
            raise ApiError(400, '請給 merchant_id 或 query 其中之一')
        with db() as conn:
            if merchant_id is not None:
                if not isinstance(merchant_id, int) or isinstance(merchant_id, bool):
                    raise ApiError(400, 'merchant_id 要是數字')
                merchant = service.merchant_by_id(conn, merchant_id)
                if merchant is None:
                    raise ApiError(404, f'沒有這家店:{merchant_id}')
            else:
                if not isinstance(query, str) or not query.strip():
                    raise ApiError(400, 'query 不能是空的')
                merchant = service.resolve(conn, query)
            birthday, user_cards = service.user_profile(conn, g.user_id)
            card_ids = [cid for cid, _ in user_cards if cid in rules.cards]
            rows = service.scheme_rows(conn, card_ids, merchant.merchant_id if merchant else None)

        results = compute_recommendations(rules, user_cards, rows, merchant, birthday, today_in_taiwan())
        return jsonify({
            'merchant': None if merchant is None else {
                'merchant_id': merchant.merchant_id, 'name': merchant.name,
                'category': merchant.category, 'country': merchant.country},
            'merchant_found': merchant is not None,
            'message': None if merchant is not None else NOT_FOUND_MESSAGE,
            'results': [_result_json(r) for r in results],
        })

    # ---- 卡片設定選項 ----

    @app.route('/api/cards', methods=['GET'])
    @require_login
    def cards():
        return jsonify([_card_json(c) for c in rules.cards.values()])

    @app.route('/api/cards/<card_id>/pickable_merchants', methods=['GET'])
    @require_login
    def pickable(card_id):
        card = card_rule_or_404(card_id)
        with db() as conn:
            return jsonify(service.pickable_merchants(conn, card))

    # ---- 使用者的卡片 ----

    @app.route('/api/user/cards', methods=['GET'])
    @require_login
    def my_cards():
        with db() as conn:
            saved = service.list_user_cards(conn, g.user_id)
        return jsonify([dict(c, card_name=rules.cards[c['card_id']].name) if c['card_id'] in rules.cards else c
                        for c in saved])

    @app.route('/api/user/cards/<card_id>', methods=['PUT'])
    @require_login
    def save_card(card_id):
        card = card_rule_or_404(card_id)
        data = body()
        if 'config' not in data:
            raise ApiError(400, '請用 {"config": {...}} 的格式送出卡片設定')
        with db() as conn:
            pickable_ids = {m['merchant_id'] for m in service.pickable_merchants(conn, card)}
            config = validate_config(card, data['config'], pickable_ids)
            service.save_user_card(conn, g.user_id, card_id, config)
        return jsonify({'card_id': card_id, 'card_name': card.name, 'config': config})

    @app.route('/api/user/cards/<card_id>', methods=['DELETE'])
    @require_login
    def delete_card(card_id):
        with db() as conn:
            if not service.delete_user_card(conn, g.user_id, card_id):
                raise ApiError(404, '你沒有這張卡')
        return jsonify({'message': '已移除'})

    return app


def _result_json(r):
    return {
        'card_id': r.card_id,
        'card_name': r.card_name,
        'bank_name': r.bank_name,
        'reward_rate': float(r.reward_rate),
        'scheme_name': r.scheme_name,
        'is_general': r.is_general,
        'required_action': r.required_action,
        'notes': list(r.notes),
    }


def _card_json(c):
    return {
        'card_id': c.card_id,
        'name': c.name,
        'bank': c.bank,
        'rate_by': c.rate_by,                               # 'level' / 'plan' / null
        'options': list(c.options),                         # 等級或方案的選項
        'toggles': [{'key': k, 'label': v} for k, v in c.toggles.items()],
        'pick_merchants_when': sorted(c.pick_plans),        # 選到這些方案時要挑店
        'max_chosen_merchants': c.max_chosen_merchants,
    }


def _check_consistency(settings, rules):
    try:
        with connection(settings) as conn:
            for msg in consistency_warnings(rules, service.db_scheme_keys(conn)):
                log.warning(msg)
    except Exception as e:          # 資料庫連不上時不阻止啟動,讓 /api/health 回報問題
        log.warning('啟動時無法檢查資料庫:%s', e)


def main(argv=None):
    sys.stdout.reconfigure(encoding='utf-8')
    logging.basicConfig(level=logging.INFO, format='%(levelname)s %(message)s')
    parser = argparse.ArgumentParser(description='啟動回饋推薦後端')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=5000)
    parser.add_argument('--debug', action='store_true')
    args = parser.parse_args(argv)

    debug = args.debug
    if debug and args.host not in ('127.0.0.1', 'localhost'):
        # 除錯模式會開一個可以執行任意程式的除錯頁面,不能讓同網路的人連到
        log.warning('對外開放(--host %s)時不允許除錯模式,已關閉 debug', args.host)
        debug = False
    create_app().run(host=args.host, port=args.port, debug=debug)


if __name__ == '__main__':
    main()
