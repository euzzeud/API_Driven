#!/bin/bash
set -e

echo "========================================="
echo "  🚀 Déploiement API-Driven Infrastructure"
echo "========================================="

# --- Variables ---
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-test}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-test} # Ces variables sont stockées dans GitHub Secrets, par défaut, "test".
export AWS_ENDPOINT_URL=http://localhost:4566

echo ""
echo "📦 [1/5] Vérification de LocalStack..."
localstack status services | grep -q "ec2" && echo "✅ LocalStack est actif" || { echo "❌ LocalStack n'est pas démarré. Lance: localstack start -d"; exit 1; }

echo ""
echo "🖥️  [2/5] Création de l'instance EC2..."
AMI_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL ec2 describe-images --query 'Images[0].ImageId' --output text)
echo "   AMI trouvée : $AMI_ID"

aws --endpoint-url=$AWS_ENDPOINT_URL ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --count 1 > /dev/null

export INSTANCE_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL ec2 describe-instances \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
echo "   ✅ Instance créée : $INSTANCE_ID"

echo ""
echo "⚡ [3/5] Déploiement de la fonction Lambda..."
zip -q lambda.zip lambda_function.py

# Supprimer si elle existe déjà
aws --endpoint-url=$AWS_ENDPOINT_URL lambda delete-function --function-name ec2-controller 2>/dev/null || true

aws --endpoint-url=$AWS_ENDPOINT_URL lambda create-function \
  --function-name ec2-controller \
  --runtime python3.11 \
  --handler lambda_function.handler \
  --zip-file fileb://lambda.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --environment Variables={INSTANCE_ID=$INSTANCE_ID} > /dev/null
echo "   ✅ Lambda déployée"

echo ""
echo "🌐 [4/5] Configuration de l'API Gateway..."
API_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL apigateway create-rest-api \
  --name "EC2ControlAPI" --query 'id' --output text)

ROOT_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL apigateway get-resources \
  --rest-api-id $API_ID --query 'items[0].id' --output text)

RESOURCE_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL apigateway create-resource \
  --rest-api-id $API_ID --parent-id $ROOT_ID --path-part ec2 --query 'id' --output text)

aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-method \
  --rest-api-id $API_ID --resource-id $RESOURCE_ID \
  --http-method GET --authorization-type NONE > /dev/null

aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-integration \
  --rest-api-id $API_ID --resource-id $RESOURCE_ID \
  --http-method GET --type AWS_PROXY --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:ec2-controller/invocations > /dev/null

aws --endpoint-url=$AWS_ENDPOINT_URL apigateway create-deployment \
  --rest-api-id $API_ID --stage-name prod > /dev/null

echo "   ✅ API Gateway déployée : $API_ID"

echo ""
echo "🧪 [5/5] Test de l'infrastructure..."
RESULT=$(aws --endpoint-url=$AWS_ENDPOINT_URL lambda invoke \
  --function-name ec2-controller \
  --payload "{\"queryStringParameters\": {\"action\": \"status\", \"instance_id\": \"$INSTANCE_ID\"}}" \
  /tmp/response.json 2>/dev/null && cat /tmp/response.json)
echo "   Réponse Lambda : $RESULT"

echo ""
echo "========================================="
echo "  ✅ Déploiement terminé !"
echo "========================================="
echo ""
echo "  Instance ID : $INSTANCE_ID"
echo "  API ID      : $API_ID"
echo ""
echo "  URLs de test :"
echo "  Status : curl 'http://localhost:4566/restapis/$API_ID/prod/_user_request_/ec2?action=status&instance_id=$INSTANCE_ID'"
echo "  Stop   : curl 'http://localhost:4566/restapis/$API_ID/prod/_user_request_/ec2?action=stop&instance_id=$INSTANCE_ID'"
echo "  Start  : curl 'http://localhost:4566/restapis/$API_ID/prod/_user_request_/ec2?action=start&instance_id=$INSTANCE_ID'"
echo ""
