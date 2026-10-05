"""後端設定。

優先讀環境變數;本機開發時若沒設,資料庫連線改讀 db/my.local.cnf,
token 簽名密鑰則自動產生並存在 backend/.secret_key(兩者都在 .gitignore 內)。

環境變數:
  DB_HOST、DB_PORT、DB_USER、DB_PASSWORD、DB_NAME   資料庫連線
  APP_SECRET_KEY                                     token 簽名密鑰
  CARDS_YAML                                         卡片規則檔路徑(預設 backend/cards.yaml)
"""

import configparser
import os
import secrets
from dataclasses import dataclass
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent
REPO_ROOT = BACKEND_DIR.parent
LOCAL_CNF = REPO_ROOT / 'db' / 'my.local.cnf'
SECRET_KEY_FILE = BACKEND_DIR / '.secret_key'

TOKEN_DAYS = 30


@dataclass
class Settings:
    db_host: str
    db_port: int
    db_user: str
    db_password: str
    db_name: str
    secret_key: str
    cards_yaml: Path


def _local_cnf():
    if not LOCAL_CNF.exists():
        return {}
    cnf = configparser.RawConfigParser()
    cnf.read(LOCAL_CNF, encoding='utf-8')
    return dict(cnf['client']) if cnf.has_section('client') else {}


def _secret_key():
    key = os.environ.get('APP_SECRET_KEY')
    if key:
        return key
    if SECRET_KEY_FILE.exists():
        return SECRET_KEY_FILE.read_text(encoding='utf-8').strip()
    key = secrets.token_hex(32)
    SECRET_KEY_FILE.write_text(key, encoding='utf-8')
    return key


def load_settings():
    cnf = _local_cnf()
    return Settings(
        db_host=os.environ.get('DB_HOST', cnf.get('host', '127.0.0.1')),
        db_port=int(os.environ.get('DB_PORT', cnf.get('port', 3306))),
        db_user=os.environ.get('DB_USER', cnf.get('user', 'root')),
        db_password=os.environ.get('DB_PASSWORD', cnf.get('password', '')),
        db_name=os.environ.get('DB_NAME', 'credit_card_app'),
        secret_key=_secret_key(),
        cards_yaml=Path(os.environ.get('CARDS_YAML', BACKEND_DIR / 'cards.yaml')),
    )
