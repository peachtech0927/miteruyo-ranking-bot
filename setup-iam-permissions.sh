#!/bin/bash
set -e

# 設定
AWS_PROFILE="miteruyo-ranking-bot"
AWS_REGION="ap-northeast-1"
IAM_USER="miteruyo-rankingbot-dev"
POLICY_NAME="MiteruyoRankingBotDeployPolicy"

echo "👤 IAM権限設定スクリプト"
echo "=========================================="
echo "IAMユーザー: ${IAM_USER}"
echo "ポリシー名: ${POLICY_NAME}"
echo ""

# AWS Account IDを取得
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile ${AWS_PROFILE} --query Account --output text)
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
echo ""

# ポリシードキュメントを作成
cat > /tmp/deploy-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRPermissions",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:CreateRepository"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaPermissions",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:ListFunctions",
        "lambda:InvokeFunction",
        "lambda:AddPermission",
        "lambda:RemovePermission",
        "lambda:GetPolicy"
      ],
      "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:miteruyo-ranking-bot*"
    },
    {
      "Sid": "IAMPassRolePermission",
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/miteruyo-ranking-bot-role"
    },
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:GetRole",
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy"
      ],
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/miteruyo-ranking-bot-role"
    },
    {
      "Sid": "EventBridgePermissions",
      "Effect": "Allow",
      "Action": [
        "events:PutRule",
        "events:DescribeRule",
        "events:PutTargets",
        "events:RemoveTargets",
        "events:DeleteRule",
        "events:ListRules",
        "events:ListTargetsByRule"
      ],
      "Resource": "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/miteruyo-ranking-bot*"
    },
    {
      "Sid": "LogsPermissions",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/lambda/miteruyo-ranking-bot*"
    }
  ]
}
EOF

echo "📝 ポリシードキュメントを作成しました"
echo ""

# 既存のポリシーを確認
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
if aws iam get-policy --policy-arn ${POLICY_ARN} --profile ${AWS_PROFILE} >/dev/null 2>&1; then
    echo "🔄 既存のポリシーを更新中..."

    # 新しいポリシーバージョンを作成
    aws iam create-policy-version \
        --policy-arn ${POLICY_ARN} \
        --policy-document file:///tmp/deploy-policy.json \
        --set-as-default \
        --profile ${AWS_PROFILE}

    echo "✅ ポリシーを更新しました"
else
    echo "🔨 新しいポリシーを作成中..."

    # ポリシーを作成
    aws iam create-policy \
        --policy-name ${POLICY_NAME} \
        --policy-document file:///tmp/deploy-policy.json \
        --description "Miteruyo Ranking Botのデプロイに必要な権限" \
        --profile ${AWS_PROFILE}

    echo "✅ ポリシーを作成しました"
fi
echo ""

# ユーザーにポリシーをアタッチ
echo "🔗 ポリシーをユーザーにアタッチ中..."
aws iam attach-user-policy \
    --user-name ${IAM_USER} \
    --policy-arn ${POLICY_ARN} \
    --profile ${AWS_PROFILE} 2>/dev/null || echo "✅ ポリシーは既にアタッチされています"
echo ""

echo "=========================================="
echo "✅ IAM権限の設定が完了しました！"
echo ""
echo "設定内容:"
echo "  - ユーザー: ${IAM_USER}"
echo "  - ポリシー: ${POLICY_NAME}"
echo "  - ポリシーARN: ${POLICY_ARN}"
echo ""
echo "次のステップ:"
echo "  ./deploy.sh を実行してデプロイを開始してください"
echo ""

# 一時ファイルの削除
rm -f /tmp/deploy-policy.json
