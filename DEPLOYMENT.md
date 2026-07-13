# Guia de Deployment - ToggleMaster no AWS Academy

## Pre-requisitos

- Acesso ao AWS Academy com Session Manager na EC2
- kubectl instalado na EC2
- Imagens publicadas no ECR com prefixo `toggle-master/` (634115191566.dkr.ecr.us-east-1.amazonaws.com/toggle-master/<service>:latest)
- VPC existente com subnets publicas (para NLB) e privadas (para nodes) em pelo menos 2 AZs
- NAT Gateway configurado nas subnets privadas
- LabRole (`arn:aws:iam::634115191566:role/LabRole`) com permissoes para EKS, EC2, ECR, ELB, SQS, DynamoDB

## Sobre Security Groups

As regras de Security Group sao criadas automaticamente pelos templates CloudFormation usando cross-stack references:
- RDS porta 5432 ← cluster SG managed dos nodes (via ImportValue)
- ElastiCache porta 6379 ← cluster SG managed dos nodes (via ImportValue)

## Sobre ConfigMaps e Secrets

As variaveis de ambiente dos pods sao gerenciadas por:
- **ConfigMap** — valores nao sensiveis (PORT, URLs de servicos internos, AWS_REGION, AWS_SQS_URL)
- **Secret** — credenciais (DATABASE_URL, MASTER_KEY, REDIS_URL, SERVICE_API_KEY)

Para alterar uma configuracao sem redesploiar:
1. Editar o ConfigMap ou Secret
2. `kubectl apply -f <arquivo>`
3. `kubectl rollout restart deployment <nome> -n <namespace>`

## 1. Infraestrutura (CloudFormation)

### 1.1 EKS Cluster + SQS/DynamoDB (paralelo)

```bash
aws cloudformation create-stack \
  --stack-name toggle-master-eks \
  --template-body file://cloudformation/eks-cluster.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=<VPC_ID> \
    ParameterKey=SubnetIds,ParameterValue="<SUBNET_PRIVADA_1>\,<SUBNET_PRIVADA_2>" \
    ParameterKey=NodeInstanceType,ParameterValue=t3.medium \
    ParameterKey=NodeGroupDesiredSize,ParameterValue=2

aws cloudformation create-stack \
  --stack-name toggle-master-sqs-dynamo \
  --template-body file://cloudformation/sqs-dynamodb.yaml
```

Aguardar (~15-20 minutos):

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

Aguardar:

```bash
aws cloudformation wait stack-create-complete --stack-name toggle-master-rds
aws cloudformation wait stack-create-complete --stack-name toggle-master-redis
```

## 2. Obter Outputs da Infraestrutura

```bash
aws cloudformation describe-stacks --stack-name toggle-master-rds \
  --query "Stacks[0].Outputs[?OutputKey=='DBEndpoint'].OutputValue" --output text

aws cloudformation describe-stacks --stack-name toggle-master-redis \
  --query "Stacks[0].Outputs[?OutputKey=='RedisEndpoint'].OutputValue" --output text

aws cloudformation describe-stacks --stack-name toggle-master-sqs-dynamo \
  --query "Stacks[0].Outputs[?OutputKey=='QueueUrl'].OutputValue" --output text
```

## 3. Configurar kubectl

```bash
aws eks update-kubeconfig --name toggle-master-cluster --region us-east-1
kubectl get nodes
```

### 3.1 Configurar acesso admin no cluster

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::634115191566:role/LabRole
      groups:
      - system:bootstrappers
      - system:nodes
      - system:masters
      username: system:node:{{EC2PrivateDNSName}}
EOF
```

**Nota:** `kubectl logs` e `kubectl exec` nao funcionam no Academy devido a limitacao de kubelet-serving certificates. Use `kubectl describe pod` e verificacoes externas para diagnosticar.

## 4. Criar Bancos de Dados

```bash
sudo yum install -y postgresql15

psql -h <RDS_ENDPOINT> -U fiap -d togglemaster -f auth-service/db/init.sql
psql -h <RDS_ENDPOINT> -U fiap -d togglemaster -f flag-service/db/init.sql
psql -h <RDS_ENDPOINT> -U fiap -d togglemaster -f targeting-service/db/init.sql
```

## 5. Instalar Nginx Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/aws/deploy.yaml

kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

Aguardar o EXTERNAL-IP aparecer no service `ingress-nginx-controller`.

**Nota sobre Metrics Server:** No AWS Academy, o Metrics Server nao funciona devido a limitacao de kubelet-serving certificates. Em producao, instale com:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

## 6. Criar Namespaces, ConfigMaps e Secrets

### 6.1 Criar namespaces

```bash
kubectl apply -f auth-service/k8s/namespace.yaml
kubectl apply -f flag-service/k8s/namespace.yaml
kubectl apply -f targeting-service/k8s/namespace.yaml
kubectl apply -f evaluation-service/k8s/namespace.yaml
kubectl apply -f analytics-service/k8s/namespace.yaml
```

### 6.2 Atualizar e aplicar ConfigMaps

Editar `AWS_SQS_URL` nos configmaps do evaluation-service e analytics-service com o output do passo 2.

```bash
kubectl apply -f auth-service/k8s/configmap.yaml
kubectl apply -f flag-service/k8s/configmap.yaml
kubectl apply -f targeting-service/k8s/configmap.yaml
kubectl apply -f evaluation-service/k8s/configmap.yaml
kubectl apply -f analytics-service/k8s/configmap.yaml
```

### 6.3 Atualizar e aplicar Secrets

Gerar base64 dos valores reais:

```bash
echo -n "postgres://fiap:bhimA123@toggle-master-db.chr1dgso7byg.us-east-1.rds.amazonaws.com:5432/togglemaster?sslmode=require" | base64 -w 0
echo -n "admin-secreto-123" | base64 -w 0
echo -n "redis://toggle-master-redis.p56ynu.0001.use1.cache.amazonaws.com:6379" | base64 -w 0
```

Substituir nos arquivos `secret.yaml` e aplicar:

```bash
kubectl apply -f auth-service/k8s/secret.yaml
kubectl apply -f flag-service/k8s/secret.yaml
kubectl apply -f targeting-service/k8s/secret.yaml
kubectl apply -f evaluation-service/k8s/secret.yaml
```

## 7. Deploy dos Microsservicos

```bash
kubectl apply -f auth-service/k8s/ -f flag-service/k8s/ -f targeting-service/k8s/ -f evaluation-service/k8s/ -f analytics-service/k8s/
```

## 8. Injetar Credenciais AWS nos Pods

No AWS Academy, os pods nao herdam credenciais via IMDS. Execute este script para obter e injetar automaticamente:

```bash
# Obter credenciais temporarias do IMDS
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
CREDS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/LabRole)

AWS_KEY=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKeyId'])")
AWS_SECRET=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['SecretAccessKey'])")
AWS_TOKEN=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['Token'])")

# Injetar nos servicos que acessam AWS
kubectl set env deployment/analytics-service -n analytics-service \
  AWS_ACCESS_KEY_ID=$AWS_KEY \
  AWS_SECRET_ACCESS_KEY=$AWS_SECRET \
  AWS_SESSION_TOKEN="$AWS_TOKEN"

kubectl set env deployment/evaluation-service -n evaluation-service \
  AWS_ACCESS_KEY_ID=$AWS_KEY \
  AWS_SECRET_ACCESS_KEY=$AWS_SECRET \
  AWS_SESSION_TOKEN="$AWS_TOKEN"
```

**Importante:** Credenciais expiram em ~6 horas. Se os pods pararem de acessar SQS/DynamoDB, execute novamente.

## 9. Verificar Deploy

```bash
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A

NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $NLB

kubectl get hpa -A
```

## 10. Criar API Key e Atualizar Secret do Evaluation

```bash
# Criar a API key
NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

API_KEY=$(curl -s -X POST http://$NLB/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer admin-secreto-123" \
  -d '{"name": "evaluation-service-key"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")

echo "API Key gerada: $API_KEY"

# Gerar base64 e atualizar o secret
REDIS_URL_B64=$(kubectl get secret evaluation-service-secret -n evaluation-service -o jsonpath='{.data.REDIS_URL}')
API_KEY_B64=$(echo -n "$API_KEY" | base64 -w 0)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: evaluation-service-secret
  namespace: evaluation-service
type: Opaque
data:
  REDIS_URL: $REDIS_URL_B64
  SERVICE_API_KEY: $API_KEY_B64
EOF

# Reiniciar o pod para pegar o novo secret
kubectl rollout restart deployment evaluation-service -n evaluation-service
```
kubectl geet pods =
## 11. Testar

```bash
curl http://$NLB/health
curl http://$NLB/validate

curl -X POST http://$NLB/flags \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <API_KEY>" \
  -d '{"name": "enable-dashboard", "description": "Test flag", "is_enabled": true}'

curl "http://$NLB/evaluate?user_id=user-123&flag_name=enable-dashboard"
```

## 12. Cleanup (IMPORTANTE - preservar budget)

```bash
kubectl delete ingress --all -A
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/aws/deploy.yaml

aws cloudformation delete-stack --stack-name toggle-master-redis
aws cloudformation delete-stack --stack-name toggle-master-rds
aws cloudformation delete-stack --stack-name toggle-master-sqs-dynamo
aws cloudformation delete-stack --stack-name toggle-master-eks

aws cloudformation wait stack-delete-complete --stack-name toggle-master-eks
```

**Nota:** Deletar NAT Gateway manualmente no console se nao for mais necessario.

## Troubleshooting

| Problema | Causa | Solucao |
|----------|-------|---------|
| ImagePullBackOff | Imagem nao existe no ECR | Verificar `aws ecr describe-repositories` e corrigir nome no deployment |
| CrashLoopBackOff | Secret com valor errado | Verificar secret com `kubectl get secret -o jsonpath` e base64 -d |
| 503 no curl via NLB | Pod nao esta Running | `kubectl get pods -A` e resolver o pod com erro |
| NLB sem EXTERNAL-IP | Nginx controller nao subiu | `kubectl get pods -n ingress-nginx` |
| Pods nao acessam SQS/DynamoDB | Credenciais AWS nao injetadas | Executar passo 8 novamente |
| HPA mostra unknown | Metrics Server nao funciona | Limitacao do Academy - escalar manualmente |
