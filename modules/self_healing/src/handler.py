"""
Self-Healing: ponte entre o Alertmanager e o GitHub Actions.

Fluxo:
  Alertmanager (alerta critical) --webhook--> esta Lambda (Function URL)
      --> API do GitHub (workflow_dispatch) --> workflow self-healing.yml
      --> kubectl rollout restart deployment/<servico>

A Lambda vive fora do cluster de proposito: se o cluster estiver degradado, a
recuperacao ainda consegue ser disparada.

Seguranca:
  - A Function URL e publica, entao toda requisicao precisa trazer o token
    compartilhado (Authorization: Bearer ...), comparado em tempo constante.
  - So reinicia servicos da lista permitida (ALLOWED_SERVICES). O namespace nao
    e lido do alerta: e sempre igual ao nome do servico.
"""
import base64
import hmac
import json
import logging
import os
import urllib.error
import urllib.request

log = logging.getLogger()
log.setLevel(logging.INFO)

GITHUB_API = "https://api.github.com"


def _config():
    return {
        "webhook_token": os.environ["WEBHOOK_TOKEN"],
        "github_token": os.environ["GITHUB_TOKEN"],
        "repo": os.environ["GITHUB_REPO"],
        "workflow": os.environ["GITHUB_WORKFLOW"],
        "ref": os.environ["GITHUB_REF_NAME"],
        "allowed": {s.strip() for s in os.environ["ALLOWED_SERVICES"].split(",") if s.strip()},
    }


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _authorized(headers, expected_token):
    """ Valida 'Authorization: Bearer <token>' em tempo constante. """
    auth = {k.lower(): v for k, v in (headers or {}).items()}.get("authorization", "")
    prefix = "Bearer "
    if not auth.startswith(prefix):
        return False
    return hmac.compare_digest(auth[len(prefix):].encode(), expected_token.encode())


def _parse_body(event):
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    return json.loads(body)


def _services_to_heal(payload, allowed):
    """
    Extrai os servicos a reiniciar a partir do payload do Alertmanager.
    O nome vem do label 'service' ou, na falta dele, de 'deployment'
    (alertas de kube-state-metrics, como ToggleMasterPodDown).
    Retorna {servico: alertname}, sem duplicados.
    """
    targets = {}
    skipped = []
    for alert in payload.get("alerts", []):
        if alert.get("status") != "firing":
            continue
        labels = alert.get("labels", {})
        service = labels.get("service") or labels.get("deployment")
        if service not in allowed:
            skipped.append(service)
            continue
        targets.setdefault(service, labels.get("alertname", "desconhecido"))
    if skipped:
        log.info("Alertas ignorados (servico fora da lista permitida ou ausente): %s", skipped)
    return targets


def _dispatch_workflow(cfg, service):
    """ Dispara o workflow no GitHub. Retorna o status HTTP (204 = sucesso). """
    url = f"{GITHUB_API}/repos/{cfg['repo']}/actions/workflows/{cfg['workflow']}/dispatches"
    body = json.dumps({
        "ref": cfg["ref"],
        "inputs": {"service": service, "namespace": service},
    }).encode()
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {cfg['github_token']}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "toggle-master-self-healing",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code
    except urllib.error.URLError as e:
        log.error("Falha de rede ao chamar o GitHub: %s", e.reason)
        return 0


def handler(event, context):
    cfg = _config()

    if not _authorized(event.get("headers"), cfg["webhook_token"]):
        log.warning("Requisicao rejeitada: token ausente ou invalido")
        return _response(401, {"error": "nao autorizado"})

    try:
        payload = _parse_body(event)
    except (ValueError, UnicodeDecodeError):
        log.warning("Requisicao rejeitada: corpo nao e um JSON valido")
        return _response(400, {"error": "corpo invalido"})

    targets = _services_to_heal(payload, cfg["allowed"])
    if not targets:
        return _response(200, {"message": "nenhum servico a reiniciar", "dispatched": []})

    results = {}
    for service, alertname in targets.items():
        status = _dispatch_workflow(cfg, service)
        results[service] = status
        log.info("Self-healing de %s (alerta %s): GitHub respondeu %s", service, alertname, status)

    failed = {s: c for s, c in results.items() if c != 204}
    if failed:
        # 502 faz o Alertmanager tentar de novo (ele repete em erros 5xx)
        return _response(502, {"error": "falha ao disparar o workflow", "results": results})
    return _response(200, {"message": "workflow disparado", "dispatched": sorted(results)})
