# MeCab + pandas + wordcloudの処理

import MeCab
import pandas as pd
from wordcloud import WordCloud
import matplotlib.pyplot as plt
import japanize_matplotlib
import os
from datetime import datetime
import numpy as np
from PIL import Image
import discord
from dotenv import load_dotenv
from collections import Counter
import emoji
from get_data import get_db_connection

def fetch_data(conn):
    if not conn:
        return
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT message_id, user_id, content, channel_id, created_at FROM messages;")
    except Exception as e:
        print(f"データ取得中にエラーが発生しました: {e}")

if __name__ == "__main__":
    connection = get_db_connection()
    fetch_data(connection)

# .envファイルから環境変数を読み込む
load_dotenv()
# 環境変数からトークンとチャンネルIDを取得
DISCORD_BOT_TOKEN = os.getenv('DISCORD_BOT_TOKEN')
DISCORD_CHANNEL_ID = int(os.getenv('DISCORD_CHANNEL_ID'))
# DISCORD_CHANNEL_ID = os.getenv('DISCORD_CHANNEL_ID')

# Discord Botの権限設定
intents = discord.Intents.default()  # 最低限のみ
client = discord.Client(intents=intents)  # どのイベントを扱えるか

# MeCab Taggerの初期化
mecab = MeCab.Tagger()

# データベースからメッセージ内容を取得してリストに入れる
def get_messages(conn):
    if not conn:
        return []
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT content FROM messages WHERE content IS NOT NULL AND content != '';")
            rows = cur.fetchall()
            return [row[0] for row in rows if row[0].strip()]  # 空でないコンテンツのみ
    except Exception as e:
        print(f"メッセージ取得中にエラーが発生しました: {e}")
        return []
    finally:
        if conn:
            conn.close()
            print("\n🐘 データベース接続を閉じました。")

# 結果格納用
data = []

# データベースからメッセージを取得
messages = get_messages(connection)
if not messages:
    print("データベースからメッセージが取得できませんでした。")
    exit(1)

# 絵文字と記号・文章をあらかじめ分ける
def separate_by_type(messages):
    text_list = []
    emoji_list = []
    
    for sentence in messages:
        texts = []
        emojis = []
        for char in sentence:
            if emoji.is_emoji(char):
                emojis.append(char)
            elif  not char.isspace(): # 空白文字は無視
                texts.append(char)

        text_list.append("".join(texts))
        emoji_list.append("".join(emojis))

    return text_list, emoji_list
text_list, emoji_list = separate_by_type(messages)

for sentence in text_list:
    words, roots, parts = [], [], []
    node = mecab.parseToNode(sentence) # nodeは文節のこと
    while node:
        surface = node.surface # 表層形
        features = node.feature.split(",") # mecabの出力結果をコンマ区切りで取得
        base = features[6] if len(features) > 6 else "*" # 原形
        pos = features[0] # 品詞
        if surface:
            words.append(surface)
            roots.append(base)
            parts.append(pos)
        node = node.next
    data.append({"sentence": sentence, "words": words, "root": roots, "part": parts})

# 解析結果をDataFrameに変換
df = pd.DataFrame(data)

def filter():
    # 意味のある単語を新リスト（filtered_words）に格納
    filtered_words = []
    # 除外したい単語リスト
    STOP_WORDS = {"の", "そう", "ない", "いい", "ん", "とき", "よう", "これ", "こと","人","今","時","感じ","的","何","なに","なん","化","他"}

    for i, row in df.iterrows():
        for root, part in zip(row["root"], row["part"]):
            if part in ["形容詞", "形容動詞", "名詞"] and root not in STOP_WORDS:
                filtered_words.append(root)
    return filtered_words

# intransitiveの要素をスペース区切りで連結
text_for_wc = " ".join(filter())

def create_wordcloud():
    # 画像保存場所を作成
    OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/app/output")
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    mask_image = np.array(Image.open("/app/logo/PeachTech_black.png"))

    # ワードクラウド生成（フォント指定なし）
    wordcloud = WordCloud(
        font_path="/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        background_color="white",
        mask=mask_image,
        colormap="Paired",
        width=800,
        height=800
    ).generate(text_for_wc)

    # タイムスタンプ付きのファイル名を生成
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    output_filename = f"wordcloud_output_{timestamp}.png"
    output_path = os.path.join(OUTPUT_DIR, output_filename)
    wordcloud.to_file(output_path)
    print(f"✅ WordCloud画像を保存しました → {output_path}")
    return output_path

# Botが起動したときに一度だけ実行される処理
@client.event
async def on_ready():
    print(f'{client.user} としてログインしました。')
    
    try:
        word_counts = Counter(filter())
        top_words = word_counts.most_common(3)
        rank_strings = []
        for rank, (word, count) in enumerate(top_words, 1):
            if rank == 1:
                crown = "👑 "  # 1位
            else:
                crown = "" 
            rank_strings.append(f"{crown}{rank} 位  「**{word}**」  {count}回")
        
        ranking_text = "\n".join(rank_strings)
        final_message = f"🍑先月のぴちてくトレンドワードは…🗣️\n## {ranking_text}\n\nでした！"

        image_path = create_wordcloud()
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
        
    finally:
        await client.close()

# Botを実行
if __name__ == '__main__':
    if not DISCORD_BOT_TOKEN or not DISCORD_CHANNEL_ID:
        print("エラー: 環境変数 DISCORD_BOT_TOKEN または DISCORD_CHANNEL_ID が設定されていません。")
    else:
        client.run(DISCORD_BOT_TOKEN)