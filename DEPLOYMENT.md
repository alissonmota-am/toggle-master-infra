# Guia de Deployment - ToggleMaster (Terraform + ArgoCD)

## Pre-requisitos

- AWS CLI configurada (perfil `default`) com um usuario IAM com permissao para criar VPC, EKS, IAM, RDS, ElastiCache, SQS, DynamoDB e Lambda (ex.: `AdministratorAccess`). Conferir com `aws sts get-caller-identity`
- Bucket S3 `toggle-master-terraform-state-<ACCOUNT_ID>` criado (bootstrap manual, feito uma vez)
  - Account ID atual: `344258592914`
  - Criar com: `aws s3api create-bucket --bucket toggle-master-terraform-state-344258592914 --region us-east-1`
  - Habilitar versionamento: `aws s3api put-bucket-versioning --bucket toggle-master-terraform-state-344258592914 --versioning-configuration Status=Enabled`
  - Bloquear acesso publico: `aws s3api put-public-access-block --bucket toggle-master-terraform-state-344258592914 --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true`
  - O account ID e fixo em todos os repositorios (ver "Conta AWS" abaixo)
- Repositorios GitHub com branch `develop` atualizada
- GitHub CLI (`gh`) autenticado localmente
- `kubectl` instalado

### Conta AWS

Todos os repositorios (infra e os 5 servicos) estao alinhados com a conta `344258592914`: bucket de state, `ECR_REGISTRY`
dos builds, `image:` dos deployments e `AWS_SQS_URL` dos ConfigMaps. Se a conta mudar um dia, localizar todas as
ocorrencias com `grep -rn "<ACCOUNT_ID_ANTIGO>" --include="*.yml" --include="*.yaml" --include="*.tf" --include="*.tfvars" .`

**Nota:** apos recriar o ambiente, o ECR esta vazio. Os pods dos servicos ficam em `ImagePullBackOff` ate o CI publicar
as imagens (passo 6). O nome da fila SQS vem do Terraform do analytics-service (`analytics-service-dev-queue`) e a URL
no ConfigMap deve corresponder a ele.

## 1. Configurar Secrets nos Repositorios GitHub

### 1.1 Atualizar credenciais AWS (todos os repos)

Garantir que o perfil `default` da AWS CLI aponta para o usuario IAM do projeto e rodar (aceita outro perfil como argumento):

```bash
./update-secrets.sh
```

Isso atualiza `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` nos 6 repositorios e remove o antigo `AWS_SESSION_TOKEN` (as chaves do usuario IAM sao permanentes).

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
- Roles IAM do cluster e dos nodes (modulo `iam`) e Access Entry de admin para o usuario IAM (`eks_admin_principal_arn`)

Tempo estimado: ~15-20 minutos

### 2.1 Validar cluster

```bash
aws eks update-kubeconfig --name toggle-master-dev-cluster --region us-east-1
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
- **Stack de Observabilidade** (Fase 4):
  - kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
  - loki-stack (Loki + Promtail)
  - OTel Collector (recebe telemetria dos microsservicos e roteia para Prometheus/Loki/New Relic)
  - Datasource do Loki no Grafana
  - Dashboard "ToggleMaster - Saude do Ecossistema" (ConfigMap lido pelo sidecar do Grafana)
  - Regras de alerta (`modules/observability/rules/togglemaster-alerts.yaml`, via Helm values)
  - Alertmanager com receivers Slack e PagerDuty

Tempo estimado: ~15 minutos (os Helm charts de observabilidade levam alguns minutos)

O workflow de addons tambem dispara automaticamente em push que altere `addons/**` ou `modules/observability/**`
(editar regras de alerta, dashboard ou config do OTel Collector aplica a mudanca via `terraform apply`).

### Secrets necessarios para a stack de observabilidade

Antes de rodar o workflow de addons, garantir que estes secrets existem no repositorio `toggle-master-infra`:

| Secret | Descricao |
|--------|-----------|
| `GRAFANA_ADMIN_PASSWORD` | Senha do admin do Grafana |
| `NEW_RELIC_LICENSE_KEY` | Ingest License Key da conta New Relic (sem ela os traces nao aparecem no APM) |
| `SLACK_WEBHOOK_URL` | Incoming Webhook do canal `#toggle-master-alerts` |
| `PAGERDUTY_ROUTING_KEY` | Integration Key de um servico no PagerDuty (aceita no endpoint Events API v2) |
| `SELF_HEALING_GITHUB_TOKEN` | GitHub PAT (fine-grained, `Actions: Read and write` em `toggle-master-infra`) que a Lambda usa para disparar o workflow |
| `SELF_HEALING_WEBHOOK_TOKEN` | Token compartilhado entre o Alertmanager e a Lambda, protege a Function URL publica |

Esses seis secrets ja estao configurados com valores reais no repositorio e **nao precisam ser recriados** ao subir o
ambiente de novo, pois pertencem ao repositorio e nao ao cluster. Os secrets `AWS_*` so precisam ser atualizados
se a access key do usuario IAM for trocada (ver 1.1).

Para conferir ou trocar algum valor:
```bash
gh secret list --repo alissonmota-am/toggle-master-infra
gh secret set <NOME_DO_SECRET> --repo alissonmota-am/toggle-master-infra   # pede o valor no terminal
```

Sem um valor valido, o `terraform apply` continua funcionando, mas a integracao correspondente nao entrega nada:
traces ausentes no New Relic, alertas que nao chegam ao Slack ou incidentes que nao abrem no PagerDuty.

### Validar stack de observabilidade

```bash
kubectl get pods -n observability
# Pegar URL do Grafana (usuario: admin, senha: secret GRAFANA_ADMIN_PASSWORD)
kubectl get svc -n observability kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# Confirmar que o OTel Collector esta Running
kubectl get pods -n observability -l app=otel-collector
# Confirmar que as regras de alerta foram carregadas
kubectl get prometheusrules -n observability
```

No Grafana, o dashboard aparece em Dashboards, e o datasource Loki em Connections > Data sources.

### 3.1 Criar secret de credenciais AWS no cluster

O External Secrets Operator precisa de credenciais pra acessar o Secrets Manager:

```bash
kubectl create secret generic aws-credentials -n external-secrets \
  --from-literal=access-key="$(aws configure get aws_access_key_id)" \
  --from-literal=secret-access-key="$(aws configure get aws_secret_access_key)"
```

**Nota:** as chaves sao permanentes, entao o secret so precisa ser recriado se a access key for trocada.
Considere criar um usuario IAM dedicado ao External Secrets, com permissao somente de leitura no Secrets Manager
(`secretsmanager:GetSecretValue` e `DescribeSecret`), em vez de reutilizar o usuario administrador.

### 3.2 Validar addons

```bash
kubectl get pods -n argocd
kubectl get pods -n ingress-nginx
kubectl get pods -n external-secrets
kubectl get clustersecretstore
```

O `ClusterSecretStore` deve estar `Valid` e `Ready: True`.

### 3.3 Acesso externo aos load balancers (sob demanda, so o seu IP)

Os 3 load balancers publicos (ingress-nginx/API, ArgoCD e Grafana) nascem acessiveis **somente pela VPC**
(`lb_allowed_cidrs` em `addons/environments/<env>.tfvars`). Isso evita que bots e scanners explorem os endpoints.
A restricao e feita pelo `loadBalancerSourceRanges` dos Services (security groups), sem custo extra.

Para acessar de fora, libere o seu IP **sem pipeline**, direto no cluster:

```bash
cd toggle-master-infra
./scripts/lb-access.sh open           # detecta seu IP publico e libera VPC + IP/32
./scripts/lb-access.sh open 203.0.113.7   # ou informe o IP manualmente
./scripts/lb-access.sh status         # mostra ranges e enderecos dos 3 LBs
./scripts/lb-access.sh close          # volta para so a VPC (rode ao terminar)
```

Pontos de atencao:
- A lista de ranges **nunca pode ficar vazia**: no Kubernetes vazio significa `0.0.0.0/0` (aberto para o mundo). O Terraform
  recusa lista vazia e `0.0.0.0/0` (validation da variavel), e o script sempre mantem o CIDR da VPC.
- Um apply do Terraform dos addons **nem sempre reverte** o `open`: o Helm so reaplica o campo se o valor no Terraform mudar.
  Rode `close` ao terminar, e confira com `status`.
- Se o seu IP mudar (rede, VPN, 4G), rode `open` de novo. Cada `open` substitui a lista anterior, nao acumula IPs.
- O pipeline e o cluster nao dependem desses LBs: ArgoCD, Alertmanager, workflows e kubectl usam a rede interna ou a API do EKS.
- Os LBs continuam existindo (e cobrando a hora fixa) mesmo fechados.
- Depois do primeiro apply, validar o bloqueio de fora do seu IP (ex.: celular em 4G): a conexao deve dar timeout.

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

Os bancos (auth, flag, targeting) nascem vazios. E preciso rodar o `db/init.sql` de cada
servico uma vez por recriacao. Os RDS ficam em subnets privadas, entao a conexao parte de
dentro do cluster.

**Pre-requisito:** os ExternalSecrets ja materializados (o Secret `<svc>-service-secret` existe
no namespace), pois a `DATABASE_URL` vem dele. Ver passo 3.1 e 3.2.

### Metodo recomendado: Job no cluster (nao depende de bastion)

Roda um `psql` como Job em cada namespace, lendo o `init.sql` de um ConfigMap e a
`DATABASE_URL` do Secret do servico. O resultado e lido pelo **status do Job** (via API
server), o que e util quando o kubelet esta instavel e bloqueia `kubectl logs/exec`
(erro `tls: internal error`).

```bash
# 1) ConfigMap com o init.sql de cada servico (os repos estao clonados localmente)
for svc in auth flag targeting; do
  kubectl create configmap ${svc}-initsql -n ${svc}-service \
    --from-file=init.sql=../${svc}-service/db/init.sql \
    --dry-run=client -o yaml | kubectl apply -f -
done

# 2) Job que executa o psql (repetir o bloco trocando NS/CM/SECRET por servico,
#    ou usar o manifesto multi-Job que aplica os 3 de uma vez)
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: db-init, namespace: auth-service }
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: psql
          image: postgres:15-alpine
          command: ["sh","-c","psql \"$PGURL\" -v ON_ERROR_STOP=1 -f /sql/init.sql"]
          env:
            - name: PGURL
              valueFrom: { secretKeyRef: { name: auth-service-secret, key: DATABASE_URL } }
          volumeMounts: [{ name: sql, mountPath: /sql }]
      volumes: [{ name: sql, configMap: { name: auth-initsql } }]
EOF
# (repetir para flag-service/flag-initsql/flag-service-secret e
#  targeting-service/targeting-initsql/targeting-service-secret)

# 3) Conferir sucesso (sem depender de logs)
for ns in auth-service flag-service targeting-service; do
  echo "$ns: $(kubectl get job db-init -n $ns -o jsonpath='{.status.succeeded}')"
done   # 1 = sucesso

# 4) Limpar
for ns in auth-service flag-service targeting-service; do
  kubectl delete job db-init -n $ns
  kubectl delete configmap ${ns%%-service}-initsql -n $ns
done
```

### Alternativa: bastion EC2 (Session Manager)

```bash
sudo yum install -y postgresql15
psql -h auth-service-dev-db.<RDS_SUFFIX>.us-east-1.rds.amazonaws.com -U fiap -d auth_db -f auth-service/db/init.sql
psql -h flag-service-dev-db.<RDS_SUFFIX>.us-east-1.rds.amazonaws.com -U fiap -d flag_db -f flag-service/db/init.sql
psql -h targeting-service-dev-db.<RDS_SUFFIX>.us-east-1.rds.amazonaws.com -U fiap -d targeting_db -f targeting-service/db/init.sql
```

Substituir `<RDS_SUFFIX>` pelo sufixo real do endpoint (output do Terraform ou console RDS).

## 6. Builds e Deploy (Automatico)

O push de codigo nos microsservicos dispara automaticamente:
1. **GitHub Actions** → build da imagem + push pro ECR + atualiza tag no `k8s/deployment.yaml`
2. **ArgoCD** → detecta mudanca no `k8s/` → aplica no cluster

Os servicos estao instrumentados com OpenTelemetry (Fase 4). Os pods enviam traces para o OTel Collector
(`otel-collector.observability.svc.cluster.local:4317`, configurado nos ConfigMaps via `OTEL_*`).
Se o Collector nao estiver acessivel, os servicos sobem normalmente, apenas sem telemetria. Por isso a ordem
recomendada e instalar os addons (passo 3) antes dos servicos.

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
  --region us-east-1
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

## 8.1 Validar Observabilidade e Self-Healing (Fase 4)

Gerar trafego para produzir traces, metricas e logs:

```bash
for i in $(seq 1 30); do curl -s "http://$NLB/evaluate?user_id=user-$i&flag_name=enable-dashboard" > /dev/null; done
```

- **Traces:** New Relic > APM & Services > Service Map / Distributed tracing (precisa da `NEW_RELIC_LICENSE_KEY` real)
- **Metricas e logs:** dashboard do Grafana; logs no Explore com `{namespace="auth-service"}`
- **Alertas:** Prometheus/Alertmanager (`kubectl get prometheusrules -n observability`)

**Self-Healing.** O fluxo automatico e: Prometheus dispara o alerta critical -> Alertmanager
notifica Slack, abre incidente no PagerDuty e chama a Lambda (`modules/self_healing`, funcao
`toggle-master-self-healing`) -> a Lambda dispara o workflow `self-healing.yml` -> o workflow
roda `kubectl rollout restart` no servico afetado. A Lambda e usada porque o trial do PagerDuty
nao habilita Incident Workflows (a ponte do PagerDuty para o GitHub).

Teste manual, do mais completo ao mais direto:

```bash
# 1) Simular o webhook do Alertmanager chamando a Lambda (ponta a ponta)
#    FUNCTION_URL: terraform output -raw function_url no modulo self_healing
#    O token e o secret SELF_HEALING_WEBHOOK_TOKEN
curl -X POST "$FUNCTION_URL" \
  -H "Authorization: Bearer $SELF_HEALING_WEBHOOK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"alerts":[{"status":"firing","labels":{"alertname":"AuthServiceHighErrorRate","severity":"critical","service":"auth-service"}}]}'

# 2) Disparar o workflow direto, sem passar pela Lambda
gh workflow run self-healing.yml --repo alissonmota-am/toggle-master-infra \
  -f service=auth-service -f namespace=auth-service
```

Detalhes e roteiro de demonstracao em `ROTEIRO-FASE4-OBSERVABILIDADE.md`.

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

- As credenciais sao chaves permanentes do usuario IAM. Se trocar a access key, rodar `./update-secrets.sh` e recriar o secret `aws-credentials` no cluster.
- O ArgoCD faz polling a cada ~3 minutos. Mudancas no `k8s/` podem levar ate 3 min pra refletir.
- O External Secrets Operator tem `refreshInterval: 1h`. Usar annotation `force-sync` pra forcar.
- **`tls: internal error` no kubelet** (`kubectl logs/exec/port-forward` falhando, paineis de CPU/memoria vazios,
  Metrics Server sem dados): ocorre se a role dos nodes tiver uma access entry `STANDARD` (admin). O modulo `eks` nao
  cria essa entry; o node group gerenciado cria sozinho a `EC2_LINUX`. Se o sintoma aparecer, conferir com
  `aws eks list-access-entries --cluster-name toggle-master-dev-cluster` e remover a entry `STANDARD` da role dos nodes.
- **Pods sem credencial AWS** (`NoCredentialProviders` no evaluation, `Unable to locate credentials` no analytics):
  os nodes precisam de IMDS com hop limit 2 (o módulo `eks` define isso via launch template) e a role dos nodes precisa das permissões de SQS/DynamoDB (módulo `iam`). Num cluster antigo:
  `aws ec2 modify-instance-metadata-options --instance-id <id> --http-put-response-hop-limit 2 --http-tokens required`
  em cada node e depois `kubectl rollout restart` do evaluation e do analytics.
- Adicionar o launch template a um node group existente força a **substituição** do node group. Não rode o workflow do
  `platform` com o cluster no ar só para isso: os pods caem até os nodes novos subirem.
- O `SERVICE_API_KEY` do evaluation-service e um passo manual pos-deploy (depende do auth-service estar rodando).
- A stack de observabilidade consome memoria (Prometheus principalmente). Com 2 nodes `t3.medium` cabe, mas para a gravacao do video considere subir `eks_node_desired_size` para 3.
- Para destruir tudo localmente: `terraform destroy` em `addons/` e depois em `platform/` (mesma ordem do workflow de destroy). O bucket de state e mantido.


SELF_HEALING_WEBHOOK_TOKEN: nx7d5TMLr3AxlcyLjpMr24_gMXzD6UKQsUAP-PfrzLU (guarde)