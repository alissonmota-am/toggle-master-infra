#!/usr/bin/env bash
# Libera ou fecha o acesso externo aos load balancers (ingress-nginx, ArgoCD e Grafana).
#
# Por padrao o Terraform deixa os 3 LBs acessiveis so pela VPC (lb_allowed_cidrs).
# Este script altera o campo loadBalancerSourceRanges direto nos Services, sem
# Terraform e sem pipeline, para liberar o seu IP quando voce precisar.
#
# Uso:
#   ./scripts/lb-access.sh open [IPV4]   libera VPC + seu IP (detecta o IP se omitido)
#   ./scripts/lb-access.sh close         volta para so a VPC
#   ./scripts/lb-access.sh status        mostra os ranges e os enderecos atuais
#
# Variaveis opcionais: CLUSTER_NAME (padrao toggle-master-dev-cluster), AWS_REGION (padrao us-east-1)
#
# Observacao: um apply do Terraform dos addons nem sempre reverte a alteracao feita aqui
# (o Helm so reaplica o campo se o valor no Terraform mudar). Nao conte com o apply para
# fechar: rode "close" ao terminar.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-toggle-master-dev-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# namespace/service
SERVICES=(
  "ingress-nginx/ingress-nginx-controller"
  "argocd/argocd-server"
  "observability/kube-prometheus-stack-grafana"
)

uso() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

valida_ipv4() {
  local ip="$1" o
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for o in "${BASH_REMATCH[@]:1}"; do
    ((10#$o <= 255)) || return 1
  done
  # Recusa enderecos que nao fazem sentido como IP publico do operador
  [[ "$ip" != "0.0.0.0" && "$ip" != "255.255.255.255" ]] || return 1
}

ACAO="${1:-}"
IP_INFORMADO="${2:-}"

case "$ACAO" in
  open)
    if [[ -n "$IP_INFORMADO" ]] && ! valida_ipv4 "$IP_INFORMADO"; then
      echo "Erro: '$IP_INFORMADO' nao e um IPv4 valido." >&2
      exit 1
    fi
    ;;
  close | status) ;;
  *) uso ;;
esac

for cmd in aws kubectl; do
  command -v "$cmd" >/dev/null || { echo "Erro: '$cmd' nao encontrado no PATH." >&2; exit 1; }
done

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null

# CIDR da VPC do cluster (sempre mantido, para o trafego interno e os health checks)
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$AWS_REGION" \
  --query 'Vpcs[0].CidrBlock' --output text)

if [[ -z "$VPC_CIDR" || "$VPC_CIDR" == "None" ]]; then
  echo "Erro: nao foi possivel descobrir o CIDR da VPC do cluster $CLUSTER_NAME." >&2
  exit 1
fi

aplica() {
  local ranges_json="$1" item ns svc
  for item in "${SERVICES[@]}"; do
    ns="${item%%/*}"
    svc="${item##*/}"
    if kubectl get svc "$svc" -n "$ns" >/dev/null 2>&1; then
      kubectl patch svc "$svc" -n "$ns" --type merge \
        -p "{\"spec\":{\"loadBalancerSourceRanges\":${ranges_json}}}" >/dev/null
      echo "  ok: $ns/$svc"
    else
      echo "  aviso: $ns/$svc nao encontrado (addon ainda nao instalado?)" >&2
    fi
  done
}

mostra_status() {
  local item ns svc ranges host
  for item in "${SERVICES[@]}"; do
    ns="${item%%/*}"
    svc="${item##*/}"
    if kubectl get svc "$svc" -n "$ns" >/dev/null 2>&1; then
      ranges=$(kubectl get svc "$svc" -n "$ns" -o jsonpath='{.spec.loadBalancerSourceRanges}')
      host=$(kubectl get svc "$svc" -n "$ns" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
      echo "  $ns/$svc"
      echo "    ranges: ${ranges:-<VAZIO: aberto para o mundo>}"
      echo "    host:   ${host:-<ainda sem endereco>}"
    else
      echo "  $ns/$svc: nao encontrado"
    fi
  done
}

case "$ACAO" in
  open)
    MEU_IP="$IP_INFORMADO"
    if [[ -z "$MEU_IP" ]]; then
      MEU_IP=$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]')
      valida_ipv4 "$MEU_IP" || { echo "Erro: nao consegui detectar seu IP. Informe: $0 open <IPV4>" >&2; exit 1; }
    fi
    echo "Liberando ${MEU_IP}/32 (alem da VPC ${VPC_CIDR}) em ${CLUSTER_NAME}:"
    aplica "[\"${VPC_CIDR}\",\"${MEU_IP}/32\"]"
    echo "Lembre de rodar '$0 close' ao terminar."
    ;;
  close)
    echo "Fechando para so a VPC ${VPC_CIDR} em ${CLUSTER_NAME}:"
    aplica "[\"${VPC_CIDR}\"]"
    ;;
  status)
    echo "VPC: ${VPC_CIDR} (cluster ${CLUSTER_NAME})"
    mostra_status
    ;;
esac
