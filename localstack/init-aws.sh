#!/bin/bash
echo "Criando fila SQS..."
awslocal sqs create-queue --queue-name toggle-master-queue --region us-east-1

echo "Criando tabela DynamoDB..."
awslocal dynamodb create-table \
    --table-name ToggleMasterAnalytics \
    --attribute-definitions AttributeName=event_id,AttributeType=S \
    --key-schema AttributeName=event_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-east-1

echo "Recursos AWS criados com sucesso!"
