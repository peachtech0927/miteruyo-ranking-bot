import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

def get_db_connection():
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        print("エラー: 環境変数 DATABASE_URL が設定されていません。")
        return None

    try:
        conn = psycopg2.connect(database_url, connect_timeout=3)
        print("🐘PostgreSQLへの接続に成功しました！")
        return conn
    except psycopg2.OperationalError as e:
        print(f"DATABASE_URL 経由での接続に失敗しました: error={e}")

    return None