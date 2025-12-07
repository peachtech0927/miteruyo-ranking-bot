# MeCab + pandas + wordcloudの処理

import MeCab
import pandas as pd
from wordcloud import WordCloud
import os
from datetime import datetime
import numpy as np
from PIL import Image
import discord
from dotenv import load_dotenv
from collections import Counter
import emoji
import unicodedata
import asyncio

# Lambda/ローカル両対応のインポート
try:
    from app.get_data import get_db_connection
except ImportError:
    from get_data import get_db_connection

# .envファイルから環境変数を読み込む（ローカル実行時）
load_dotenv()

# 環境変数からトークンとチャンネルIDを取得
DISCORD_BOT_TOKEN = os.getenv('DISCORD_BOT_TOKEN')
DISCORD_CHANNEL_ID = int(os.getenv('DISCORD_CHANNEL_ID')) if os.getenv('DISCORD_CHANNEL_ID') else None

# MeCab Taggerの初期化
mecab = MeCab.Tagger()

# データベースからメッセージ内容を取得してリストに入れる
def get_messages(conn):
    if not conn:
        return []
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT content FROM messages WHERE content IS NOT NULL AND content != '' AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month');")
            rows = cur.fetchall()
            return [row[0] for row in rows if row[0].strip()]  # 空でないコンテンツのみ
    except Exception as e:
        print(f"メッセージ取得中にエラーが発生しました: {e}")
        return []
    finally:
        if conn:
            conn.close()
            print("\n🐘 データベース接続を閉じました。")

# 絵文字と空白を除いたテキストのみ抽出
def separate_text(messages):
    text_list = []

    for sentence in messages:
        texts = []
        for char in sentence:
            if emoji.is_emoji(char):
                continue
            if unicodedata.category(char).startswith(("P", "S")):
                continue
            if char.isdigit() and len(char) == 1:
                continue
            if not char.isspace():  # 空白文字は無視
                texts.append(char)

        text_list.append("".join(texts))

    return text_list

def analyze_messages(messages):
    """メッセージを形態素解析して単語の頻度を計算"""
    data = []
    text_list = separate_text(messages)

    for sentence in text_list:
        words, roots, parts = [], [], []
        node = mecab.parseToNode(sentence)
        while node:
            surface = node.surface
            features = node.feature.split(",")
            base = features[6] if len(features) > 6 else "*"
            if base == "*" or not base.strip():
                base = surface
            pos = features[0]
            if surface:
                words.append(surface)
                roots.append(base)
                parts.append(pos)
            node = node.next
        data.append({"sentence": sentence, "words": words, "root": roots, "part": parts})

    df = pd.DataFrame(data)

    # 意味のある単語を抽出
    filtered_words = []
    STOP_WORDS = {"の", "そう", "ない", "いい", "ん", "とき", "よう", "これ", "こと","人","今","時","感じ","的","何","なに","なん","化","他","HTTPS"}

    for _, row in df.iterrows():
        for root, part in zip(row["root"], row["part"]):
            if part in ["形容詞", "形容動詞", "名詞", "感動詞"] and root not in STOP_WORDS and len(root) != 1 and root.strip():
                filtered_words.append(root)

    return Counter(filtered_words)

def create_wordcloud(frequencies):
    """ワードクラウド画像を生成"""
    OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/tmp/output")
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Lambda/ローカル両対応のロゴパス
    logo_paths = [
        "/var/task/app/logo/PeachTech_black.png",  # Lambda環境
        "app/logo/PeachTech_black.png",             # ローカル（プロジェクトルートから実行）
        "logo/PeachTech_black.png",                 # ローカル（appディレクトリから実行）
    ]

    logo_path = None
    for path in logo_paths:
        if os.path.exists(path):
            logo_path = path
            break

    if not logo_path:
        raise FileNotFoundError("ロゴファイルが見つかりません")

    mask_image = np.array(Image.open(logo_path))

    wordcloud = WordCloud(
        font_path="/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        background_color="white",
        mask=mask_image,
        colormap="tab10",
        width=800,
        height=800
    ).generate_from_frequencies(frequencies)

    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    output_filename = f"wordcloud_output_{timestamp}.png"
    output_path = os.path.join(OUTPUT_DIR, output_filename)
    wordcloud.to_file(output_path)
    print(f"✅ WordCloud画像を保存しました → {output_path}")
    return output_path

async def send_discord_message(word_frequencies):
    """Discordにメッセージと画像を送信"""
    intents = discord.Intents.default()
    client = discord.Client(intents=intents)

    @client.event
    async def on_ready():
        print(f'{client.user} としてログインしました。')

        try:
            top_words = word_frequencies.most_common(3)

            rank_strings = []
            for rank, (word, count) in enumerate(top_words, 1):
                crown = "👑 " if rank == 1 else ""
                rank_strings.append(f"{crown}{rank} 位  「**{word}**」  {count}回")

            last_month = (datetime.now().month - 1) or 12
            last_month_year = (datetime.now().year - 1) if last_month == 12 else datetime.now().year
            ranking_text = "\n".join(rank_strings)
            final_message = f"🍑{last_month_year}年{last_month}月のぴちてくトレンドワードは…🗣️\n## {ranking_text}\n\nでした！"

            image_path = create_wordcloud(word_frequencies)
            channel = client.get_channel(DISCORD_CHANNEL_ID)

            if channel:
                await channel.send(
                    final_message,
                    file=discord.File(image_path)
                )
                print(f"チャンネル '{channel.name}' にメッセージと画像を投稿しました。")
            else:
                print(f"エラー: チャンネルID {DISCORD_CHANNEL_ID} が見つかりません。")

        except Exception as e:
            print(f"エラーが発生しました: {e}")
            raise

        finally:
            await client.close()

    await client.start(DISCORD_BOT_TOKEN)

def run_ranking_bot():
    """メイン処理: ランキング生成とDiscord投稿"""
    print("🍑 ランキングBotを開始します...")

    # データベース接続
    connection = get_db_connection()
    if not connection:
        raise Exception("データベース接続に失敗しました")

    # メッセージ取得
    messages = get_messages(connection)
    if not messages:
        raise Exception("データベースからメッセージが取得できませんでした")

    print(f"📊 {len(messages)}件のメッセージを取得しました")

    # 形態素解析
    word_frequencies = analyze_messages(messages)
    print(f"📝 {len(word_frequencies)}個の単語を解析しました")

    # Discord投稿
    asyncio.run(send_discord_message(word_frequencies))

# Lambda用ハンドラー関数
def lambda_handler(event, context):
    """AWS Lambda用のハンドラー関数"""
    try:
        run_ranking_bot()
        return {
            'statusCode': 200,
            'body': 'ランキングBotの実行が完了しました'
        }
    except Exception as e:
        print(f"エラー: {e}")
        return {
            'statusCode': 500,
            'body': f'エラーが発生しました: {str(e)}'
        }

# ローカル実行用
if __name__ == '__main__':
    if not DISCORD_BOT_TOKEN or not DISCORD_CHANNEL_ID:
        print("エラー: 環境変数 DISCORD_BOT_TOKEN または DISCORD_CHANNEL_ID が設定されていません。")
        exit(1)

    run_ranking_bot()