"""資料庫連線。"""

from contextlib import contextmanager

import mysql.connector


def connect(settings):
    # collation 一定要指定:MySQL 8 連線預設是 utf8mb4_0900_ai_ci,跟資料表的
    # utf8mb4_unicode_ci 不同,拿變數與欄位比較時會出現 "Illegal mix of collations"
    return mysql.connector.connect(
        host=settings.db_host,
        port=settings.db_port,
        user=settings.db_user,
        password=settings.db_password,
        database=settings.db_name,
        charset='utf8mb4',
        collation='utf8mb4_unicode_ci',
    )


@contextmanager
def connection(settings):
    """一次請求用一條連線;區塊內的寫入在結束時 commit,發生例外則 rollback。"""
    conn = connect(settings)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
