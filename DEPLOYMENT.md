# Guia de Deployment - ToggleMaster (Terraform + ArgoCD)

## Pre-requisitos

- Conta AWS Academy ativa com sessao iniciada
- Bucket S3 `toggle-master-terraform-state-103568492404` criado (bootstrap manual, feito uma vez)
- Repositorios GitHub com branch `develop` atualizada
- Docker instalado (para builds locais, se necessario)

## 1. Configurar Secrets nos Repositorios GitHub

### 1.1 Todos os repositorios (6 repos)

Settings → Secrets and variables → Actions → New repository secret:

| Secret | Valor |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | Da sessao AWS Academy |
| `AWS_SECRET_ACCESS_KEY` | Da sessao AWS Academy |
| `AWS_SESSION_TOKEN` | Da sessao AWS Academy |

Repositorios:
- toggle-master-infra
- auth-service
- flag-service
- targeting-service
- evaluation-service
- analytics-service

### 1.2 Repositorios com RDS (adicionalmente)

| Secret | Valor |
|--------|-------|
| `DB_PASSWORD` | Senha do banco (minimo 8 caracteres) |

Repositorios:
- auth-service
- flag-service
- targeting-service

## 2. Criar Infraestrutura Base (Platform)

### 2.1 Disparar workflow da plataforma

No repositorio `toggle-master-infra`:
- Actions → **Terraform Dev - Platform** → Run workflow → branch `develop`

Ou fazer push com alteracao em `platform/` na branch `develop`.

Recursos criados:
- VPC (subnets publicas/privadas, NAT, IGW)
- EKS Cluster + Node Group
- ECR (5 repositorios de imagens)
- Access Entries (LabRole + voclabs)

Tempo estimado: ~15-20 minutos

### 2.2 Validar cluster

```bash
aws eks update-kubeconfig --name toggle-master-dev-cluster --region us-east-1 --profile academy
kubectl get nodes
```

Deve mostrar 2 nodes com status `Ready`.

## 3. Instalar Addons no Cluster

### 3.1 Disparar workflow de addons

No repositorio `toggle-master-infra`:
- Actions → **Terraform Dev - Addons** → Run workflow → branch `develop`

Ou fazer push com alteracao em `addons/` na branch `develop`.

Recursos instalados:
- ArgoCD (GitOps controller)
- Nginx Ingress Controller (LoadBalancer)
- Metrics Server (HPA)
- External Secrets Operator (sincroniza secrets do AWS Secrets Manager)

Tempo estimado: ~5 minutos

### 3.2 Validar addons

```bash
kubectl get pods -n argocd
kubectl get pods -n ingress-nginx
kubectl get pods -n kube-system | grep metrics
kubectl get pods -n external-secrets
```

Todos devem estar `Running`.

## 4. Criar Infraestrutura dos Microsservicos

### 4.1 Disparar workflows de Terraform em cada servico

Para cada microsservico, disparar o workflow **Terraform Dev** via:
- Push com alteracao em `infra/` na branch `develop`
- Ou re-run de execucao anterior

Ordem sugerida (pode ser paralelo):
1. auth-service → cria RDS + secret no Secrets Manager
2. flag-service → cria RDS + secret no Secrets Manager
3. targeting-service → cria RDS + secret no Secrets Manager
4. evaluation-service → cria ElastiCache Redis
5. analytics-service → cria SQS + DynamoDB

Tempo estimado: ~10-15 minutos por RDS, ~5 minutos para Redis/SQS

### 4.2 Validar recursos criados

```bash
aws rds describe-db-instances --profile academy --query "DBInstances[].DBInstanceIdentifier"
aws elasticache describe-cache-clusters --profile academy --query "CacheClusters[].CacheClusterId"
aws sqs list-queues --profile academy
```

## 5. Inicializar Bancos de Dados

Executar os scripts de inicializacao de schema (antes do deploy dos pods):

```bash
RDS_AUTH=$(aws secretsmanager get-secret-value --secret-id auth-service-dev/database-url --profile academy --query SecretString --output text)
RDS_FLAG=$(aws secretsmanager get-secret-value --secret-id flag-service-dev/database-url --profile academy --query SecretString --output text)
RDS_TARGETING=$(aws secretsmanager get-secret-value --secret-id targeting-service-dev/database-url --profile academy --query SecretString --output text)

psql "$RDS_AUTH" -f auth-service/db/init.sql
psql "$RDS_FLAG" -f flag-service/db/init.sql
psql "$RDS_TARGETING" -f targeting-service/db/init.sql
```

## 6. Build das Imagens Docker

### 6.1 Disparar workflows de build

Para cada microsservico, disparar o workflow **Build & Push** via:
- Push com alteracao no codigo (fora de `infra/`, `k8s/`, `.github/workflows/terraform-*`)
- Ou Run workflow manualmente (se disponivel na main)

Repositorios:
1. auth-service
2. flag-service
3. targeting-service
4. evaluation-service
5. analytics-service

### 6.2 Validar imagens no ECR

```bash
aws ecr list-images --repository-name toggle-master-dev/auth-service --profile academy
aws ecr list-images --repository-name toggle-master-dev/flag-service --profile academy
aws ecr list-images --repository-name toggle-master-dev/targeting-service --profile academy
aws ecr list-images --repository-name toggle-master-dev/evaluation-service --profile academy
aws ecr list-images --repository-name toggle-master-dev/analytics-service --profile academy
```

## 7. ArgoCD Aplica os Manifests

O ArgoCD ja esta monitorando a pasta `k8s/` de cada repositorio (branch `develop`).
Apos o build, ele detecta os manifests e aplica automaticamente:
- Namespaces
- Deployments (com imagem do ECR)
- Services
- ConfigMaps
- ExternalSecrets (cria K8s Secrets via Secrets Manager)
- Ingress
- HPA

Polling interval: ~3 minutos. Para forcar sync imediato:

```bash
kubectl get applications -n argocd
```

### 7.1 Validar pods rodando

```bash
kubectl get pods -A
```

Todos os microsservicos devem estar com status `Running` (1/1 Ready).

### 7.2 Validar ingress e acesso externo

```bash
kubectl get svc -n ingress-nginx
```

O EXTERNAL-IP do `ingress-nginx-controller` e o endpoint publico (NLB).

```bash
NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$NLB/health
```

## 8. Teste Final

```bash
NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Health checks
curl http://$NLB/health

# Criar API key
curl -X POST http://$NLB/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <MASTER_KEY>" \
  -d '{"name": "test-key"}'

# Criar flag
curl -X POST http://$NLB/flags \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <API_KEY>" \
  -d '{"name": "enable-dashboard", "description": "Test flag", "is_enabled": true}'

# Avaliar flag
curl "http://$NLB/evaluate?user_id=user-123&flag_name=enable-dashboard"
```

## Destruir Ambiente (evitar cobrancas)

Ordem obrigatoria (inversa da criacao):

### 1. Destruir infra dos microsservicos

Para cada microsservico, executar workflow de destroy ou rodar localmente:
```bash
cd <service>/infra
terraform init -backend-config="key=<service>/dev/terraform.tfstate"
terraform destroy -var-file=environments/dev.tfvars -var="db_password=<senha>"
```

### 2. Destruir addons

No repositorio `toggle-master-infra`:
- Actions → **Destroy Dev - Addons** → Run workflow → digitar "destroy"

### 3. Destruir plataforma

No repositorio `toggle-master-infra`:
- Actions → **Destroy Dev - Platform** → Run workflow → digitar "destroy"

## Notas Importantes

- Credenciais do AWS Academy expiram em ~4 horas. Atualize os secrets do GitHub quando expirar.
- O ArgoCD faz polling a cada ~3 minutos. Mudancas no `k8s/` podem levar ate 3 min pra refletir.
- Se um pod ficar em `ImagePullBackOff`, verifique se o build foi feito e se o nome da imagem no deployment.yaml bate com o ECR.
- O External Secrets Operator precisa que o pod tenha credenciais AWS (via IRSA ou env vars) pra acessar o Secrets Manager.
