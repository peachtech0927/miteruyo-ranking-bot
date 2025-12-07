#!/bin/bash
set -e

# 設定
AWS_PROFILE="miteruyo-ranking-bot"
AWS_REGION="ap-northeast-1"
LAMBDA_FUNCTION_NAME="miteruyo-ranking-bot"
RULE_NAME="miteruyo-ranking-bot-monthly"
SCHEDULE_EXPRESSION="cron(0 0 1 * ? *)"  # 毎月1日午前9時（JST） = 毎月1日0時（UTC）

echo "⏰ EventBridgeスケジュール設定"
echo "=========================================="
echo "Lambda関数: ${LAMBDA_FUNCTION_NAME}"
echo "スケジュール: 毎月1日午前9時（JST）"
echo ""

# Lambda関数のARNを取得
LAMBDA_ARN=$(aws lambda get-function \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --profile ${AWS_PROFILE} \
    --region ${AWS_REGION} \
    --query 'Configuration.FunctionArn' \
    --output text)

echo "Lambda ARN: ${LAMBDA_ARN}"
echo ""

# 1. EventBridgeルールの作成または更新
echo "📅 Step 1: EventBridgeルールの作成・更新"
if aws events describe-rule --name ${RULE_NAME} --profile ${AWS_PROFILE} --region ${AWS_REGION} >/dev/null 2>&1; then
    echo "🔄 既存のルールを更新中..."
else
    echo "🔨 新しいルールを作成中..."
fi

aws events put-rule \
    --name ${RULE_NAME} \
    --schedule-expression "${SCHEDULE_EXPRESSION}" \
    --state ENABLED \
    --description "月初にランキングBotを実行" \
    --profile ${AWS_PROFILE} \
    --region ${AWS_REGION}

echo "✅ EventBridgeルールを設定しました"
echo ""

# 2. Lambda関数に実行権限を付与
echo "🔐 Step 2: Lambda関数にEventBridge実行権限を付与"
aws lambda add-permission \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --statement-id ${RULE_NAME}-permission \
    --action 'lambda:InvokeFunction' \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${AWS_REGION}:$(aws sts get-caller-identity --profile ${AWS_PROFILE} --query Account --output text):rule/${RULE_NAME}" \
    --profile ${AWS_PROFILE} \
    --region ${AWS_REGION} 2>/dev/null || echo "✅ 権限は既に付与されています"
echo ""

# 3. EventBridgeルールのターゲットを設定
echo "🎯 Step 3: EventBridgeルールのターゲットを設定"
aws events put-targets \
    --rule ${RULE_NAME} \
    --targets "Id"="1","Arn"="${LAMBDA_ARN}" \
    --profile ${AWS_PROFILE} \
    --region ${AWS_REGION}

echo "✅ ターゲットを設定しました"
echo ""

echo "=========================================="
echo "✅ EventBridgeスケジュールの設定が完了しました！"
echo ""
echo "設定内容:"
echo "  - ルール名: ${RULE_NAME}"
echo "  - スケジュール: 毎月1日午前9時（JST）"
echo "  - ターゲット: ${LAMBDA_FUNCTION_NAME}"
echo ""
echo "次回実行予定: $(date -v+1d '+%Y年%m月1日 09:00 JST' 2>/dev/null || date -d 'next month' '+%Y年%m月1日 09:00 JST' 2>/dev/null || echo '来月1日 09:00 JST')"
echo ""
