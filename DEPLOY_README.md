# Miteruyo Ranking Bot - デプロイガイド

このドキュメントでは、ランキングBotをAWS Lambdaにデプロイする手順を説明します。

## 前提条件

- Docker Desktop がインストールされていること
- AWS CLI がインストールされていること
- AWS プロファイル `miteruyo-ranking-bot` が設定されていること
- 必要な環境変数:
  - `DISCORD_BOT_TOKEN`
  - `DISCORD_CHANNEL_ID`
  - `DATABASE_URL`

## デプロイ手順

### 1. IAM権限の設定

最初に、デプロイに必要なIAM権限を設定します。

```bash
./setup-iam-permissions.sh
```

このスクリプトは以下の権限を付与します:
- ECR (Docker イメージのプッシュ)
- Lambda (関数の作成・更新)
- EventBridge (スケジュール設定)
- IAM (Lambda実行ロールの作成)

### 2. アプリケーションのデプロイ

以下のコマンドでECRへのイメージプッシュとLambda関数の作成を行います。

```bash
./deploy.sh
```

このスクリプトは以下の処理を実行します:
1. ECRリポジトリの作成(存在しない場合)
2. ECRへのログイン
3. Dockerイメージのビルド
4. ECRへのプッシュ
5. Lambda実行ロールの作成
6. Lambda関数の作成または更新

### 3. 環境変数の設定

Lambda関数に環境変数を設定します。

#### AWS Console での設定

1. AWS Lambda コンソールを開く
2. `miteruyo-ranking-bot` 関数を選択
3. 「設定」タブ → 「環境変数」を選択
4. 以下の環境変数を追加:
   - `DISCORD_BOT_TOKEN`: Discord Botのトークン
   - `DISCORD_CHANNEL_ID`: 投稿先のチャンネルID
   - `DATABASE_URL`: PostgreSQLの接続URL

#### AWS CLI での設定

```bash
aws lambda update-function-configuration \
  --function-name miteruyo-ranking-bot \
  --environment Variables='{DISCORD_BOT_TOKEN=your_token,DISCORD_CHANNEL_ID=your_channel_id,DATABASE_URL=your_db_url}' \
  --profile miteruyo-ranking-bot \
  --region ap-northeast-1
```

### 4. スケジュール実行の設定

EventBridgeで毎月1日午前9時(JST)に自動実行されるように設定します。

```bash
./setup-schedule.sh
```

### 5. テスト実行

手動でLambda関数を実行してテストします。

```bash
aws lambda invoke \
  --function-name miteruyo-ranking-bot \
  --profile miteruyo-ranking-bot \
  --region ap-northeast-1 \
  output.json

cat output.json
```

## ローカルでの開発・テスト

ローカルでの実行も可能です。

### 環境変数の設定

`.env` ファイルを作成し、以下の環境変数を設定します:

```bash
DISCORD_BOT_TOKEN=your_token
DISCORD_CHANNEL_ID=your_channel_id
DATABASE_URL=your_database_url
```

### ローカル実行

Dockerコンテナで実行する場合:

```bash
docker-compose up
```

または、直接Pythonで実行する場合:

```bash
python app/main.py
```

## アーキテクチャ

### コード構成

- `app/main.py`: メインのアプリケーションコード
  - `lambda_handler(event, context)`: Lambda用のエントリーポイント
  - `run_ranking_bot()`: ランキング生成とDiscord投稿の処理
  - ローカル実行時は`if __name__ == '__main__'`ブロックから実行

- `app/get_data.py`: データベース接続処理

### Lambda関数の設定

- **メモリ**: 2048MB
- **タイムアウト**: 300秒(5分)
- **実行環境**: Python 3.11
- **パッケージタイプ**: Container Image (ECR)

### スケジュール設定

- **実行頻度**: 毎月1日午前9時(JST) = 毎月1日0時(UTC)
- **Cron式**: `cron(0 0 1 * ? *)`

## トラブルシューティング

### デプロイが失敗する場合

1. Docker Desktopが起動しているか確認
2. AWS認証情報が正しく設定されているか確認
3. IAM権限が正しく付与されているか確認

### Lambda実行時にエラーが発生する場合

1. CloudWatch Logsでエラーログを確認
   ```bash
   aws logs tail /aws/lambda/miteruyo-ranking-bot \
     --profile miteruyo-ranking-bot \
     --region ap-northeast-1 \
     --follow
   ```

2. 環境変数が正しく設定されているか確認
3. データベース接続が可能か確認
4. Lambda関数のタイムアウト設定を確認

### イメージのサイズが大きい場合

Lambda Container Imageの上限は10GBですが、デプロイ時間を短縮するために、不要なパッケージを削除することを検討してください。

## 更新手順

コードを更新した場合は、以下のコマンドで再デプロイします:

```bash
./deploy.sh
```

このスクリプトは既存のLambda関数を自動的に更新します。

## コスト試算

- **Lambda実行**: 月1回実行、実行時間約30秒と仮定
  - 2048MBメモリ × 30秒 ≈ 無料枠内
- **ECR**: イメージストレージ 約2GB
  - 月額約$0.20
- **CloudWatch Logs**: ログ保存
  - 月額約$0.05

**月額総コスト**: 約$0.25 (無料枠適用後)

## セキュリティ

- 環境変数に機密情報(トークン、パスワード)を保存する場合は、AWS Secrets Managerの使用を検討してください
- Lambda実行ロールには最小限の権限のみを付与しています
- VPC内のデータベースにアクセスする場合は、Lambda関数をVPC内に配置してください

## サポート

問題が発生した場合は、以下を確認してください:
- CloudWatch Logsのエラーログ
- Lambda関数の設定
- IAM権限
- 環境変数

それでも解決しない場合は、開発チームにお問い合わせください。
