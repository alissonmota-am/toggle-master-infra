# Guia de Deployment - ToggleMaster no AWS Academy

## Pre-requisitos

- Acesso ao AWS Academy com Session Manager na EC2
- Docker instalado na EC2 (`sudo yum install -y docker && sudo systemctl start docker`)
- kubectl instalado na EC2
- Imagens publicadas no ECR com prefixo `toggle-master/` (634115191566.dkr.ecr.us-east-1.amazonaws.com/toggle-master/<service>:latest)
- VPC existente com subnets publicas (para NLB) e privadas (para nodes) em pelo menos 2 AZs
- NAT Gateway configurado nas subnets privadas
- LabRole (`arn:aws:iam::634115191566:role/LabRole`) com permissoes para EKS, EC2, ECR, ELB, SQS, DynamoDB

## Sobre Security Groups

As regras de Security Group sao criadas automaticamente pelos templates CloudFormation usando cross-stack references:
- RDS porta 5432 ← additional SG dos nodes (via ImportValue)
- ElastiCache porta 6379 ← additional SG dos nodes (via ImportValue)
- Nodes porta 10250 ← cluster SG managed (no template EKS)

## Sobre ConfigMaps e Secrets

As variaveis de ambiente dos pods sao gerenciadas por:
- **ConfigMap** — valores nao sensiveis (PORT, URLs de servicos internos, AWS_REGION, AWS_SQS_URL)
- **Secret** — credenciais (DATABASE_URL, MASTER_KEY, REDIS_URL, SERVICE_API_KEY)

Os deployments referenciam ambos via `envFrom` (ConfigMap) e `env.valueFrom.secretKeyRef` (Secret).

Para alterar uma configuracao sem redesploiar:
1. Editar o ConfigMap ou Secret
2. `kubectl apply -f <arquivo>`
3. `kubectl rollout restart deployment <nome> -n <namespace>`

## 1. Infraestrutura (CloudFormation)

### 1.1 EKS Cluster + SQS/DynamoDB (paralelo)

```bash
# EKS Cluster (usa LabRole, Spot instances)
aws cloudformation create-stack \
  --stack-name toggle-master-eks \
  --template-body file://cloudformation/eks-cluster.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=<VPC_ID> \
    ParameterKey=SubnetIds,ParameterValue="<SUBNET_PRIVADA_1>\,<SUBNET_PRIVADA_2>" \
    ParameterKey=NodeInstanceType,ParameterValue=t3.medium \
    ParameterKey=NodeGroupDesiredSize,ParameterValue=2

# SQS + DynamoDB (pode rodar em paralelo, sem dependencias)
aws cloudformation create-stack \
  --stack-name toggle-master-sqs-dynamo \
  --template-body file://cloudformation/sqs-dynamodb.yaml
```

Aguardar o EKS ficar com status CREATE_COMPLETE (~15-20 minutos):

```bash
aws cloudformation wait stack-create-complete --stack-name toggle-master-eks
```

### 1.2 RDS PostgreSQL

```bash
aws cloudformation create-stack \
  --stack-name toggle-master-rds \
  --template-body file://cloudformation/rds-postgres.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=<VPC_ID> \
    ParameterKey=SubnetIds,ParameterValue="<SUBNET_PRIVADA_1>\,<SUBNET_PRIVADA_2>" \
    ParameterKey=MasterUserPassword,ParameterValue=<SENHA_MINIMO_8_CHARS>
```

### 1.3 ElastiCache Redis

```bash
aws cloudformation create-stack \
  --stack-name toggle-master-redis \
  --template-body file://cloudformation/elasticache-redis.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=<VPC_ID> \
    ParameterKey=SubnetIds,ParameterValue="<SUBNET_PRIVADA_1>\,<SUBNET_PRIVADA_2>"
```

Aguardar ambos:

```bash
aws cloudformation wait stack-create-complete --stack-name toggle-master-rds
aws cloudformation wait stack-create-complete --stack-name toggle-master-redis
```

## 2. Obter Outputs da Infraestrutura

```bash
# Endpoint do RDS
aws cloudformation describe-stacks --stack-name toggle-master-rds \
  --query "Stacks[0].Outputs[?OutputKey=='DBEndpoint'].OutputValue" --output text

# Endpoint do Redis
aws cloudformation describe-stacks --stack-name toggle-master-redis \
  --query "Stacks[0].Outputs[?OutputKey=='RedisEndpoint'].OutputValue" --output text

# URL do SQS
aws cloudformation describe-stacks --stack-name toggle-master-sqs-dynamo \
  --query "Stacks[0].Outputs[?OutputKey=='QueueUrl'].OutputValue" --output text
```

## 3. Configurar kubectl

```bash
aws eks update-kubeconfig --name toggle-master-cluster --region us-east-1
kubectl get nodes  # verificar se os nodes estao Ready
```

## 4. Criar Bancos de Dados

```bash
# Instalar cliente psql (se nao tiver)
sudo yum install -y postgresql15

# Executar scripts de criacao de tabelas (senha sera solicitada)
psql -h <RDS_ENDPOINT> -U fiap -d togglemaster -f auth-service/db/init.sql
psql -h <RDS_ENDPOINT> -U fiap -d togglemaster -f flag-service/db/init.sql
psql -h <RDS_ENDPOINT> -U fiap -d togglemaster -f targeting-service/db/init.sql
```

## 5. Instalar Add-ons

```bash
# Metrics Server (necessario para HPA funcionar)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Nginx Ingress Controller (cria NLB automaticamente nas subnets publicas)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/aws/deploy.yaml

# Verificar se o controller subiu e o NLB foi criado
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

Aguardar o EXTERNAL-IP aparecer no service `ingress-nginx-controller` (endpoint do NLB).

## 6. Criar Namespaces, ConfigMaps e Secrets

### 6.1 Criar namespaces

```bash
kubectl apply -f auth-service/k8s/namespace.yaml
kubectl apply -f flag-service/k8s/namespace.yaml
kubectl apply -f targeting-service/k8s/namespace.yaml
kubectl apply -f evaluation-service/k8s/namespace.yaml
kubectl apply -f analytics-service/k8s/namespace.yaml
```

### 6.2 Atualizar os ConfigMaps

Editar os arquivos `configmap.yaml` de cada servico com os valores reais obtidos no passo 2:

- **evaluation-service/k8s/configmap.yaml** — `AWS_SQS_URL` com o output `QueueUrl`
- **analytics-service/k8s/configmap.yaml** — `AWS_SQS_URL` com o output `QueueUrl`

### 6.3 Aplicar os ConfigMaps

```bash
kubectl apply -f auth-service/k8s/configmap.yaml
kubectl apply -f flag-service/k8s/configmap.yaml
kubectl apply -f targeting-service/k8s/configmap.yaml
kubectl apply -f evaluation-service/k8s/configmap.yaml
kubectl apply -f analytics-service/k8s/configmap.yaml
```

### 6.4 Atualizar os arquivos secret.yaml

Gerar base64 dos valores reais (usar `-w 0` para nao quebrar linha):

```bash
# DATABASE_URL (usar sslmode=require para RDS)
echo -n "postgres://fiap:<SENHA>@<RDS_ENDPOINT>:5432/togglemaster?sslmode=require" | base64 -w 0

# MASTER_KEY
echo -n "admin-secreto-123" | base64 -w 0

# REDIS_URL
echo -n "redis://<REDIS_ENDPOINT>:6379" | base64 -w 0
```

Substituir os valores nos arquivos `secret.yaml` de cada servico.

### 6.5 Aplicar os Secrets

```bash
kubectl apply -f auth-service/k8s/secret.yaml
kubectl apply -f flag-service/k8s/secret.yaml
kubectl apply -f targeting-service/k8s/secret.yaml
kubectl apply -f evaluation-service/k8s/secret.yaml
```

## 7. Deploy dos Microsservicos

Aplicar tudo de uma vez:

```bash
kubectl apply -f auth-service/k8s/ -f flag-service/k8s/ -f targeting-service/k8s/ -f evaluation-service/k8s/ -f analytics-service/k8s/
```

## 8. Verificar Deploy

```bash
# Todos os pods devem estar Running
kubectl get pods -A

# Services
kubectl get svc -A

# Ingress
kubectl get ingress -A

# Endpoint do NLB (ponto de acesso externo)
NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $NLB

# HPA
kubectl get hpa -A
```

## 9. Criar API Key e Atualizar Secret do Evaluation

Apos o auth-service estar Running:

```bash
# Criar chave de API
curl -X POST http://$NLB/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer admin-secreto-123" \
  -d '{"name": "evaluation-service-key"}'
```

Copiar a chave retornada (`tm_key_...`) e atualizar o secret:

```bash
# Gerar base64 da chave
echo -n "tm_key_..." | base64 -w 0
```

Substituir o valor de `SERVICE_API_KEY` em `evaluation-service/k8s/secret.yaml`, aplicar e reiniciar:

```bash
kubectl apply -f evaluation-service/k8s/secret.yaml
kubectl rollout restart deployment evaluation-service -n evaluation-service
```

## 10. Testar

```bash
# Auth - validar endpoint
curl http://$NLB/validate

# Criar flag
curl -X POST http://$NLB/flags \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <API_KEY>" \
  -d '{"name": "enable-dashboard", "description": "Test flag", "is_enabled": true}'

# Avaliar flag
curl "http://$NLB/evaluate?user_id=user-123&flag_name=enable-dashboard"
```

## 11. Demonstrar HPA

O auth-service esta configurado para escalar facilmente (cpu request: 10m, threshold: 30%).

```bash
# Terminal 1: observar HPA em tempo real
kubectl get hpa -n auth-service --watch

# Terminal 2: gerar carga com hey (instalar: sudo snap install hey)
hey -z 120s -c 200 "http://$NLB/validate"
```

As replicas devem subir de 1 para 2, 3... conforme CPU ultrapassa 30% do request.

Para escalar de volta, parar o teste e aguardar ~5 minutos (cooldown padrao do HPA).

## 12. Cleanup (IMPORTANTE - preservar budget)

Deletar recursos Kubernetes primeiro, depois stacks:

```bash
# Deletar ingress (remove regras do NLB)
kubectl delete ingress --all -A

# Deletar o Nginx Controller (remove o NLB da AWS)
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/aws/deploy.yaml

# Deletar stacks CloudFormation
aws cloudformation delete-stack --stack-name toggle-master-redis
aws cloudformation delete-stack --stack-name toggle-master-rds
aws cloudformation delete-stack --stack-name toggle-master-sqs-dynamo
aws cloudformation delete-stack --stack-name toggle-master-eks
```

Aguardar:

```bash
aws cloudformation wait stack-delete-complete --stack-name toggle-master-eks
```

**Nota:** O NAT Gateway nao e gerenciado pelo CloudFormation neste setup. Deletar manualmente no console se nao for mais necessario.

## Troubleshooting

| Problema | Causa | Solucao |
|----------|-------|---------|
| ImagePullBackOff | Imagem nao existe no ECR | Verificar `aws ecr describe-repositories` e corrigir nome no deployment |
| CrashLoopBackOff | Secret com valor errado (senha, endpoint) | Verificar secret com `kubectl get secret -o jsonpath` e base64 -d |
| 503 no curl via NLB | Pod nao esta Running | `kubectl get pods -A` e resolver o pod com erro |
| NLB sem EXTERNAL-IP | Nginx controller nao subiu | `kubectl get pods -n ingress-nginx` e verificar logs |
| Node unhealthy no NLB | Nginx controller so tem 1 replica | `kubectl scale deployment ingress-nginx-controller -n ingress-nginx --replicas=2` |
| HPA nao escala | CPU muito baixa para o threshold | Aumentar concorrencia do teste ou reduzir cpu request no deployment |
