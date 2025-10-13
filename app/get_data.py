import os
import psycopg2
from dotenv import load_dotenv
from typing import List, Optional

load_dotenv()

def _candidate_hosts(explicit_host: Optional[str]) -> List[str]:
    if explicit_host:
        return [explicit_host]
    return [
        "data-collect-bot",        # ルート docker-compose.yml のサービス名想定
        "postgres",                # data-collect-bot/docker-compose.yml のサービス名想定
        "data-collect-postgres",   # コンテナ名想定
        "localhost",               # ホスト側から直接接続する場合
    ]


def get_db_connection():
    dbname = os.getenv("POSTGRES_DB", "datacollect")
    user = os.getenv("POSTGRES_USER", "admin")
    password = os.getenv("POSTGRES_PASSWORD", "password123")
    explicit_host = os.getenv("POSTGRES_HOST")
    port = int(os.getenv("POSTGRES_PORT", "5432"))

    last_error: Optional[Exception] = None
    for host in _candidate_hosts(explicit_host):
        try:
            conn = psycopg2.connect(
                dbname=dbname,
                user=user,
                password=password,
                host=host,
                port=port,
                connect_timeout=3,
            )
            print(f"PostgreSQLへの接続に成功しました！（host={host}）")
            return conn
        except psycopg2.OperationalError as e:
            print(f"接続試行に失敗: host={host} error={e}")
            last_error = e
            continue

    print("データベースに接続できませんでした。候補ホストでの接続が全て失敗しました。")
    if last_error:
        print(f"最後のエラー: {last_error}")
    return None