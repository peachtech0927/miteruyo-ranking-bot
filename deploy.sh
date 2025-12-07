#!/bin/bash
set -e

# 設定
AWS_PROFILE="miteruyo-ranking-bot"
AWS_REGION="ap-northeast-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile ${AWS_PROFILE} --query Account --output text)
ECR_REPOSITORY_NAME="miteruyo-ranking-bot"
LAMBDA_FUNCTION_NAME="miteruyo-ranking-bot"
IMAGE_TAG="latest"

echo "🍑 Miteruyo Ranking Bot デプロイスクリプト"
echo "=========================================="
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
echo "AWS Region: ${AWS_REGION}"
echo "AWS Profile: ${AWS_PROFILE}"
echo ""

# 1. ECRリポジトリの作成（存在しない場合）
echo "📦 Step 1: ECRリポジトリの確認・作成"
if aws ecr describe-repositories --repository-names ${ECR_REPOSITORY_NAME} --profile ${AWS_PROFILE} --region ${AWS_REGION} >/dev/null 2>&1; then
    echo "✅ ECRリポジトリは既に存在します"
else
    echo "🔨 ECRリポジトリを作成中..."
    aws ecr create-repository \
        --repository-name ${ECR_REPOSITORY_NAME} \
        --profile ${AWS_PROFILE} \
        --region ${AWS_REGION} \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    echo "✅ ECRリポジトリを作成しました"
fi
echo ""

# 2. ECRにログイン
echo "🔐 Step 2: ECRにログイン"
aws ecr get-login-password --profile ${AWS_PROFILE} --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
echo "✅ ECRにログインしました"
echo ""

# 3. Dockerイメージのビルド
echo "🔨 Step 3: Dockerイメージのビルド（キャッシュなし）"
docker build --no-cache --platform linux/amd64 -f Dockerfile.lambda -t ${ECR_REPOSITORY_NAME}:${IMAGE_TAG} .
echo "✅ Dockerイメージをビルドしました"
echo ""

# 4. Dockerイメージのタグ付け
echo "🏷️  Step 4: Dockerイメージのタグ付け"
docker tag ${ECR_REPOSITORY_NAME}:${IMAGE_TAG} ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}:${IMAGE_TAG}
echo "✅ Dockerイメージにタグを付けました"
echo ""

# 5. ECRへのプッシュ
echo "⬆️  Step 5: ECRへDockerイメージをプッシュ"
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}:${IMAGE_TAG}
echo "✅ ECRへDockerイメージをプッシュしました"
echo ""

# 6. Lambda実行ロールの確認・作成
echo "👤 Step 6: Lambda実行ロールの確認・作成"
LAMBDA_ROLE_NAME="${LAMBDA_FUNCTION_NAME}-role"
LAMBDA_ROLE_ARN=$(aws iam get-role --role-name ${LAMBDA_ROLE_NAME} --profile ${AWS_PROFILE} --query 'Role.Arn' --output text 2>/dev/null || echo "")

if [ -z "${LAMBDA_ROLE_ARN}" ]; then
    echo "🔨 Lambda実行ロールを作成中..."

    # 信頼ポリシーの作成
    cat > /tmp/lambda-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    # ロールの作成
    LAMBDA_ROLE_ARN=$(aws iam create-role \
        --role-name ${LAMBDA_ROLE_NAME} \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --profile ${AWS_PROFILE} \
        --query 'Role.Arn' \
        --output text)

    # 基本実行ポリシーのアタッチ
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        --profile ${AWS_PROFILE}

    # VPC実行ポリシーのアタッチ（必要に応じて）
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole \
        --profile ${AWS_PROFILE}

    echo "✅ Lambda実行ロールを作成しました: ${LAMBDA_ROLE_ARN}"
    echo "⏳ ロールの伝播を待っています（10秒）..."
    sleep 10
else
    echo "✅ Lambda実行ロールは既に存在します: ${LAMBDA_ROLE_ARN}"
fi
echo ""

# 7. Lambda関数の作成または更新
echo "🚀 Step 7: Lambda関数の作成・更新"

# ECRから実際のイメージダイジェストを取得（OCI Image Indexではなく実際のマニフェストを使用）
echo "📋 ECRからイメージダイジェストを取得中..."
IMAGE_DIGEST=$(aws ecr describe-images \
    --repository-name ${ECR_REPOSITORY_NAME} \
    --profile ${AWS_PROFILE} \
    --region ${AWS_REGION} \
    --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageDigest' \
    --output text \
    --image-ids imageTag=${IMAGE_TAG})

# マニフェストリストではなく実際のイメージマニフェストを取得
ACTUAL_IMAGE_DIGEST=$(aws ecr batch-get-image \
    --repository-name ${ECR_REPOSITORY_NAME} \
    --profile ${AWS_PROFILE} \
    --region ${AWS_REGION} \
    --image-ids imageDigest=${IMAGE_DIGEST} \
    --accepted-media-types "application/vnd.oci.image.index.v1+json" \
    --query 'images[0].imageManifest' \
    --output text | python3 -c "import sys, json; manifest = json.load(sys.stdin); print(manifest['manifests'][0]['digest'])" 2>/dev/null || echo ${IMAGE_DIGEST})

# Lambda用のイメージURIを構築（ダイジェストを使用）
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}@${ACTUAL_IMAGE_DIGEST}"
echo "📦 使用するイメージ: ${IMAGE_URI}"

if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} --profile ${AWS_PROFILE} --region ${AWS_REGION} >/dev/null 2>&1; then
    echo "🔄 Lambda関数を更新中..."
    aws lambda update-function-code \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --image-uri ${IMAGE_URI} \
        --profile ${AWS_PROFILE} \
        --region ${AWS_REGION}

    echo "⏳ Lambda関数の更新完了を待っています..."
    aws lambda wait function-updated \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --profile ${AWS_PROFILE} \
        --region ${AWS_REGION}

    echo "✅ Lambda関数を更新しました"
else
    echo "🔨 Lambda関数を作成中..."
    aws lambda create-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --package-type Image \
        --code ImageUri=${IMAGE_URI} \
        --role ${LAMBDA_ROLE_ARN} \
        --timeout 300 \
        --memory-size 2048 \
        --profile ${AWS_PROFILE} \
        --region ${AWS_REGION}

    echo "✅ Lambda関数を作成しました"
fi
echo ""

# 8. 環境変数の設定（必要に応じて手動で設定してください）
echo "⚙️  Step 8: 環境変数の確認"
echo ""
echo "⚠️  重要: Lambda関数に以下の環境変数を設定してください："
echo "   - DISCORD_BOT_TOKEN"
echo "   - DISCORD_CHANNEL_ID"
echo "   - DATABASE_URL"
echo ""
echo "AWS Console または以下のコマンドで設定できます："
echo "aws lambda update-function-configuration \\"
echo "  --function-name ${LAMBDA_FUNCTION_NAME} \\"
echo "  --environment Variables='{DISCORD_BOT_TOKEN=your_token,DISCORD_CHANNEL_ID=your_channel_id,DATABASE_URL=your_db_url}' \\"
echo "  --profile ${AWS_PROFILE} \\"
echo "  --region ${AWS_REGION}"
echo ""

echo "=========================================="
echo "✅ デプロイが完了しました！"
echo ""
echo "次のステップ:"
echo "1. Lambda関数に環境変数を設定してください"
echo "2. EventBridgeでスケジュール実行を設定してください（月初1日午前9時など）"
echo "3. テスト実行: aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} --profile ${AWS_PROFILE} --region ${AWS_REGION} output.json"
echo ""
