# Guia de Deployment - ToggleMaster (Terraform + ArgoCD)

## Pre-requisitos

- Conta AWS Academy ativa com sessao iniciada
- Bucket S3 `toggle-master-terraform-state-103568492404` criado (bootstrap manual, feito uma vez)
- Repositorios GitHub com branch `develop` atualizada
- GitHub CLI (`gh`) autenticado localmente
- `kubectl` instalado

## 1. Configurar Secrets nos Repositorios GitHub

### 1.1 Atualizar credenciais AWS (todos os repos)

Atualizar o arquivo `~/.aws/credentials` com as novas credenciais do Academy e rodar:

```bash
./update-secrets.sh
```

Isso atualiza `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` nos 6 repositorios.

### 1.2 Secrets adicionais (configurar uma vez)

| Repositorio | Secret | Descricao |
|-------------|--------|-----------|
| auth-service | `DB_PASSWORD` | Senha do banco RDS |
| auth-service | `MASTER_KEY` | Chave admin para gerar API keys |
| flag-service | `DB_PASSWORD` | Senha do banco RDS |
| targeting-service | `DB_PASSWORD` | Senha do banco RDS |

## 2. Criar Infraestrutura Base (Platform)

Disparar workflow via GitHub CLI:

```bash
gh workflow run "Terraform Dev - Platform" --repo alissonmota-am/toggle-master-infra --ref develop
```

Recursos criados:
- VPC (subnets publicas/privadas, NAT, IGW)
- EKS Cluster + Node Group
- ECR (5 repositorios de imagens)
- Access Entries (LabRole + voclabs)

Tempo estimado: ~15-20 minutos

### 2.1 Validar cluster

```bash
aws eks update-kubeconfig --name toggle-master-dev-cluster --region us-east-1 --profile academy
kubectl get nodes
```

## 3. Instalar Addons no Cluster

```bash
gh workflow run "Terraform Dev - Addons" --repo alissonmota-am/toggle-master-infra --ref develop
```

Recursos instalados:
- ArgoCD (GitOps controller)
- Nginx Ingress Controller (LoadBalancer)
- Metrics Server (HPA)
- External Secrets Operator

Tempo estimado: ~5 minutos

### 3.1 Criar secret de credenciais AWS no cluster

O External Secrets Operator precisa de credenciais pra acessar o Secrets Manager:

```bash
AWS_PROFILE=academy kubectl create secret generic aws-credentials -n external-secrets \
  --from-literal=access-key=$(awk '/\[academy\]/,0' ~/.aws/credentials | grep aws_access_key_id | head -1 | cut -d= -f2 | tr -d ' ') \
  --from-literal=secret-access-key="$(awk '/\[academy\]/,0' ~/.aws/credentials | grep aws_secret_access_key | head -1 | cut -d= -f2- | tr -d ' ')" \
  --from-literal=session-token="$(awk '/\[academy\]/,0' ~/.aws/credentials | grep aws_session_token | head -1 | cut -d= -f2- | tr -d ' ')"
```

**Nota:** Esse secret precisa ser recriado quando a sessao do Academy expirar.

### 3.2 Validar addons

```bash
kubectl get pods -n argocd
kubectl get pods -n ingress-nginx
kubectl get pods -n external-secrets
kubectl get clustersecretstore
```

O `ClusterSecretStore` deve estar `Valid` e `Ready: True`.

## 4. Criar Infraestrutura dos Microsservicos

Disparar workflows de Terraform em cada servico:

```bash
gh workflow run "Terraform Dev - Auth Service" --repo alissonmota-am/auth-service --ref develop
gh workflow run "Terraform Dev - Flag Service" --repo alissonmota-am/flag-service --ref develop
gh workflow run "Terraform Dev - Targeting Service" --repo alissonmota-am/targeting-service --ref develop
gh workflow run "Terraform Dev - Evaluation Service" --repo alissonmota-am/evaluation-service --ref develop
gh workflow run "Terraform Dev - Analytics Service" --repo alissonmota-am/analytics-service --ref develop
```

Recursos criados por servico:
- auth-service → RDS + secrets (database-url, master-key) no Secrets Manager
- flag-service → RDS + secret (database-url) no Secrets Manager
- targeting-service → RDS + secret (database-url) no Secrets Manager
- evaluation-service → ElastiCache Redis + secret (redis-url) no Secrets Manager
- analytics-service → SQS + DynamoDB

Tempo estimado: ~10-15 minutos por RDS, ~5 minutos para Redis/SQS

## 5. Inicializar Bancos de Dados

Conectar na instancia EC2 bastion (via Session Manager) que tem acesso a VPC e executar os scripts de init:

```bash
# Instalar cliente PostgreSQL (se necessario)
sudo yum install -y postgresql15

# Executar scripts de schema
psql -h auth-service-dev-db.<RDS_SUFFIX>.us-east-1.rds.amazonaws.com -U fiap -d auth_db -f auth-service/db/init.sql
psql -h flag-service-dev-db.<RDS_SUFFIX>.us-east-1.rds.amazonaws.com -U fiap -d flag_db -f flag-service/db/init.sql
psql -h targeting-service-dev-db.<RDS_SUFFIX>.us-east-1.rds.amazonaws.com -U fiap -d targeting_db -f targeting-service/db/init.sql
```

Substituir `<RDS_SUFFIX>` pelo sufixo real do endpoint (visivel nos outputs do Terraform ou no console RDS).

## 6. Builds e Deploy (Automatico)

O push de codigo nos microsservicos dispara automaticamente:
1. **GitHub Actions** → build da imagem + push pro ECR + atualiza tag no `k8s/deployment.yaml`
2. **ArgoCD** → detecta mudanca no `k8s/` → aplica no cluster

Para forcar build sem alterar codigo:

```bash
gh workflow run "Build & Push - Auth Service" --repo alissonmota-am/auth-service --ref develop
gh workflow run "Build & Push - Flag Service" --repo alissonmota-am/flag-service --ref develop
gh workflow run "Build & Push - Targeting Service" --repo alissonmota-am/targeting-service --ref develop
gh workflow run "Build & Push - Evaluation Service" --repo alissonmota-am/evaluation-service --ref develop
gh workflow run "Build & Push - Analytics Service" --repo alissonmota-am/analytics-service --ref develop
```

## 7. Gerar SERVICE_API_KEY (pos-deploy)

Apos o auth-service estar rodando, gerar a API key e salvar no Secrets Manager:

```bash
NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Gerar API key
API_KEY=$(curl -s -X POST http://$NLB/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer admin-secreto-123" \
  -d '{"name": "evaluation-service-key"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")

echo "API Key: $API_KEY"

# Salvar no Secrets Manager
aws secretsmanager create-secret \
  --name evaluation-service-dev/service-api-key \
  --secret-string "$API_KEY" \
  --region us-east-1 \
  --profile academy
```

Depois, atualizar o ExternalSecret do evaluation-service para incluir `SERVICE_API_KEY` e forcar sync:

```bash
kubectl annotate externalsecret evaluation-service-secret -n evaluation-service force-sync=$(date +%s) --overwrite
```

## 8. Validacao Final

```bash
NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Health checks
curl http://$NLB/health

# Testar flag
curl -X POST http://$NLB/flags \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <API_KEY>" \
  -d '{"name": "enable-dashboard", "description": "Test flag", "is_enabled": true}'

# Avaliar flag
curl "http://$NLB/evaluate?user_id=user-123&flag_name=enable-dashboard"
```

## 9. Forcar Sync dos External Secrets

Se um secret foi criado/atualizado no Secrets Manager e o pod nao atualizou (refresh interval de 1h):

```bash
kubectl annotate externalsecret <nome> -n <namespace> force-sync=$(date +%s) --overwrite
```

## Destruir Ambiente

Ordem obrigatoria (inversa da criacao):

### 1. Destruir infra dos microsservicos

```bash
gh workflow run "Terraform Dev - Auth Service" --repo alissonmota-am/auth-service --ref develop
# (usar workflow de destroy quando disponivel, ou rodar localmente)
```

### 2. Destruir addons

No repositorio toggle-master-infra:
- Actions → **Destroy Dev - Addons** → Run workflow → digitar "destroy"

### 3. Destruir plataforma

No repositorio toggle-master-infra:
- Actions → **Destroy Dev - Platform** → Run workflow → digitar "destroy"

## Notas Importantes

- Credenciais do AWS Academy expiram em ~4 horas. Rodar `./update-secrets.sh` e recriar o secret `aws-credentials` no cluster.
- O ArgoCD faz polling a cada ~3 minutos. Mudancas no `k8s/` podem levar ate 3 min pra refletir.
- O External Secrets Operator tem `refreshInterval: 1h`. Usar annotation `force-sync` pra forcar.
- O Metrics Server pode nao funcionar no AWS Academy (limitacao de certificados kubelet).
- O `SERVICE_API_KEY` do evaluation-service e um passo manual pos-deploy (depende do auth-service estar rodando).
