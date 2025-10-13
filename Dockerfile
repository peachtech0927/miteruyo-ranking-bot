FROM python:3.11-slim

# タイムゾーン等の環境設定
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo
WORKDIR /app

# MeCab, NEologd辞書、その他依存関係を一つのRUN命令でインストール・設定
RUN apt-get update && apt-get install -y \
    mecab \
    mecab-ipadic-utf8 \
    libmecab-dev \
    git \
    make \
    curl \
    file \
    xz-utils \
    build-essential \
    sudo \
    fonts-noto-cjk \
    # NEologd辞書をクローンしてインストール
    && git clone --depth 1 https://github.com/neologd/mecab-ipadic-neologd.git /tmp/neologd \
    && /tmp/neologd/bin/install-mecab-ipadic-neologd -n -y \
    && echo "dicdir = $(mecab-config --dicdir)/mecab-ipadic-neologd" > /etc/mecabrc \
    && cp /etc/mecabrc /usr/local/etc/mecabrc \
    # 後片付け
    && rm -rf /tmp/neologd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Pythonライブラリのインストール
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# アプリケーションコードをコピー
COPY . .

# コンテナ起動時に実行するコマンド
CMD ["python", "app/main.py"]