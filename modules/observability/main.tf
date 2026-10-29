################################################################################
# Namespace
################################################################################
resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
  }
}

################################################################################
# kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
################################################################################
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_chart_version
  namespace  = kubernetes_namespace.observability.metadata[0].name

  # Grafana habilitado com LoadBalancer para acesso externo na demo
  set {
    name  = "grafana.enabled"
    value = "true"
  }

  set {
    name  = "grafana.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  # Sidecar para carregar dashboards de ConfigMaps com label grafana_dashboard=1
  set {
    name  = "grafana.sidecar.dashboards.enabled"
    value = "true"
  }

  set {
    name  = "grafana.sidecar.dashboards.label"
    value = "grafana_dashboard"
  }

  set {
    name  = "grafana.sidecar.dashboards.labelValue"
    value = "1"
  }

  set {
    name  = "grafana.sidecar.dashboards.searchNamespace"
    value = "ALL"
  }

  # Sidecar para carregar datasources de ConfigMaps com label grafana_datasource=1
  set {
    name  = "grafana.sidecar.datasources.enabled"
    value = "true"
  }

  set {
    name  = "grafana.sidecar.datasources.label"
    value = "grafana_datasource"
  }

  set {
    name  = "grafana.sidecar.datasources.labelValue"
    value = "1"
  }

  set {
    name  = "grafana.sidecar.datasources.searchNamespace"
    value = "ALL"
  }

  # Prometheus: retenção de 15 dias e scrape de todos os namespaces
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "15d"
  }

  set {
    name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues"
    value = "false"
  }

  # Habilita remote_write no Prometheus para o OTel Collector enviar métricas
  set {
    name  = "prometheus.prometheusSpec.enableRemoteWriteReceiver"
    value = "true"
  }

  wait    = false
  timeout = 600

  depends_on = [kubernetes_namespace.observability]
}

################################################################################
# Loki Stack (Loki + Promtail)
################################################################################
resource "helm_release" "loki_stack" {
  name       = "loki-stack"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  version    = var.loki_stack_chart_version
  namespace  = kubernetes_namespace.observability.metadata[0].name

  # Promtail coleta logs de todos os pods do cluster automaticamente
  set {
    name  = "promtail.enabled"
    value = "true"
  }

  # Grafana já instalado via kube-prometheus-stack
  set {
    name  = "grafana.enabled"
    value = "false"
  }

  wait    = false
  timeout = 300

  depends_on = [kubernetes_namespace.observability]
}

################################################################################
# Datasource do Loki no Grafana (ConfigMap lido pelo sidecar)
################################################################################
resource "kubernetes_config_map" "grafana_datasource_loki" {
  metadata {
    name      = "grafana-datasource-loki"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      grafana_datasource = "1"
    }
  }

  data = {
    "loki-datasource.yaml" = <<-YAML
      apiVersion: 1
      datasources:
        - name: Loki
          type: loki
          access: proxy
          url: http://loki-stack.observability.svc.cluster.local:3100
          isDefault: false
          editable: false
          jsonData:
            maxLines: 1000
    YAML
  }

  depends_on = [helm_release.kube_prometheus_stack, helm_release.loki_stack]
}

################################################################################
# Alertmanager Config (Secret — sobrescreve o default do kube-prometheus-stack)
################################################################################
resource "kubernetes_secret" "alertmanager_config" {
  metadata {
    # Este nome específico é lido automaticamente pelo Alertmanager do kube-prometheus-stack
    name      = "alertmanager-kube-prometheus-stack-alertmanager"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }

  data = {
    "alertmanager.yaml" = <<-YAML
      global:
        resolve_timeout: 5m

      route:
        group_by: ['alertname', 'namespace', 'service']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 4h
        receiver: 'slack-notifications'
        routes:
          - matchers:
              - severity="critical"
            receiver: 'critical'
            continue: true
          - matchers:
              - severity=~"warning|critical"
            receiver: 'slack-notifications'

      receivers:
        - name: 'slack-notifications'
          slack_configs:
            - api_url: "${var.slack_webhook_url}"
              channel: '#toggle-master-alerts'
              title: '🚨 [{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}'
              text: |
                {{ range .Alerts }}
                *Serviço:* {{ .Labels.service }}
                *Namespace:* {{ .Labels.namespace }}
                *Severidade:* {{ .Labels.severity }}
                *Descrição:* {{ .Annotations.description }}
                *Runbook:* {{ .Annotations.runbook_url }}
                {{ end }}
              send_resolved: true

        - name: 'critical'
          pagerduty_configs:
            - routing_key: "${var.pagerduty_routing_key}"
              description: '{{ .CommonLabels.alertname }}: {{ .CommonAnnotations.description }}'
              severity: '{{ .CommonLabels.severity }}'
              details:
                service: '{{ .CommonLabels.service }}'
                namespace: '{{ .CommonLabels.namespace }}'
              links:
                - href: '{{ .CommonAnnotations.runbook_url }}'
                  text: 'Runbook de Self-Healing'

      inhibit_rules:
        - source_matchers:
            - severity="critical"
          target_matchers:
            - severity="warning"
          equal: ['alertname', 'namespace', 'service']
    YAML
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

################################################################################
# PrometheusRule — Alertas dos microsserviços ToggleMaster
################################################################################
resource "kubernetes_manifest" "prometheus_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "togglemaster-alerts"
      namespace = kubernetes_namespace.observability.metadata[0].name
      labels = {
        release = "kube-prometheus-stack"
        app     = "kube-prometheus-stack"
      }
    }
    spec = {
      groups = [
        {
          name     = "togglemaster.http.errors"
          interval = "30s"
          rules = [
            {
              alert = "AuthServiceHighErrorRate"
              expr  = "(\n  sum(rate(http_requests_total{service=\"auth-service\", status=~\"5..\"}[5m]))\n  /\n  sum(rate(http_requests_total{service=\"auth-service\"}[5m]))\n) * 100 > 5\n"
              for   = "2m"
              labels = {
                severity  = "critical"
                service   = "auth-service"
                namespace = "auth-service"
              }
              annotations = {
                summary     = "Taxa de erros 5xx alta no auth-service"
                description = "Auth-service com taxa de erros HTTP 5xx acima de 5% nos últimos 2 minutos (atual: {{ $value | printf \"%.1f\" }}%)"
                runbook_url = "https://github.com/alissonmota-am/auth-service/actions/workflows/self-healing.yml"
              }
            },
            {
              alert = "EvaluationServiceHighErrorRate"
              expr  = "(\n  sum(rate(http_requests_total{service=\"evaluation-service\", status=~\"5..\"}[5m]))\n  /\n  sum(rate(http_requests_total{service=\"evaluation-service\"}[5m]))\n) * 100 > 5\n"
              for   = "2m"
              labels = {
                severity  = "critical"
                service   = "evaluation-service"
                namespace = "evaluation-service"
              }
              annotations = {
                summary     = "Taxa de erros 5xx alta no evaluation-service"
                description = "Evaluation-service com taxa de erros HTTP 5xx acima de 5% nos últimos 2 minutos (atual: {{ $value | printf \"%.1f\" }}%)"
                runbook_url = "https://github.com/alissonmota-am/evaluation-service/actions/workflows/self-healing.yml"
              }
            },
            {
              alert = "FlagServiceHighErrorRate"
              expr  = "(\n  sum(rate(http_requests_total{service=\"flag-service\", status=~\"5..\"}[5m]))\n  /\n  sum(rate(http_requests_total{service=\"flag-service\"}[5m]))\n) * 100 > 5\n"
              for   = "2m"
              labels = {
                severity  = "critical"
                service   = "flag-service"
                namespace = "flag-service"
              }
              annotations = {
                summary     = "Taxa de erros 5xx alta no flag-service"
                description = "Flag-service com taxa de erros HTTP 5xx acima de 5% nos últimos 2 minutos (atual: {{ $value | printf \"%.1f\" }}%)"
                runbook_url = "https://github.com/alissonmota-am/flag-service/actions/workflows/self-healing.yml"
              }
            }
          ]
        },
        {
          name     = "togglemaster.availability"
          interval = "30s"
          rules = [
            {
              alert = "ToggleMasterPodDown"
              expr  = "kube_deployment_status_replicas_available{namespace=~\"auth-service|flag-service|targeting-service|evaluation-service|analytics-service\"} == 0\n"
              for   = "1m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Serviço {{ $labels.deployment }} sem réplicas disponíveis"
                description = "O deployment {{ $labels.deployment }} no namespace {{ $labels.namespace }} está com 0 réplicas disponíveis há mais de 1 minuto."
                runbook_url = "https://github.com/alissonmota-am/toggle-master-infra/actions/workflows/self-healing.yml"
              }
            }
          ]
        },
        {
          name     = "togglemaster.latency"
          interval = "60s"
          rules = [
            {
              alert = "EvaluationServiceHighLatency"
              expr  = "histogram_quantile(0.95,\n  sum(rate(http_request_duration_seconds_bucket{service=\"evaluation-service\"}[5m])) by (le)\n) > 1.0\n"
              for   = "5m"
              labels = {
                severity  = "warning"
                service   = "evaluation-service"
                namespace = "evaluation-service"
              }
              annotations = {
                summary     = "Latência alta no evaluation-service (p95)"
                description = "Evaluation-service com p95 de latência acima de 1s nos últimos 5 minutos (atual: {{ $value | printf \"%.2f\" }}s)"
                runbook_url = "https://github.com/alissonmota-am/evaluation-service/actions/workflows/self-healing.yml"
              }
            }
          ]
        },
        {
          name     = "togglemaster.resources"
          interval = "60s"
          rules = [
            {
              alert = "ToggleMasterHighMemoryUsage"
              expr  = "(\n  container_memory_working_set_bytes{namespace=~\"auth-service|flag-service|targeting-service|evaluation-service|analytics-service\", container!=\"\"}\n  /\n  kube_pod_container_resource_limits{namespace=~\"auth-service|flag-service|targeting-service|evaluation-service|analytics-service\", resource=\"memory\", container!=\"\"}\n) * 100 > 85\n"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Uso de memória alto em {{ $labels.container }}"
                description = "Container {{ $labels.container }} no namespace {{ $labels.namespace }} usando mais de 85% do limite de memória (atual: {{ $value | printf \"%.1f\" }}%)"
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

################################################################################
# OTel Collector — ServiceAccount
################################################################################
resource "kubernetes_service_account" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }
}

################################################################################
# OTel Collector — Secret com chave do New Relic
################################################################################
resource "kubernetes_secret" "otel_collector" {
  metadata {
    name      = "otel-collector-secret"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }

  data = {
    NEW_RELIC_LICENSE_KEY = var.new_relic_license_key
  }
}

################################################################################
# OTel Collector — ConfigMap com pipeline de telemetria
################################################################################
resource "kubernetes_config_map" "otel_collector_config" {
  metadata {
    name      = "otel-collector-config"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }

  data = {
    "config.yaml" = <<-YAML
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: "0.0.0.0:4317"
            http:
              endpoint: "0.0.0.0:4318"

      processors:
        batch:
          timeout: 5s
          send_batch_size: 1024
        memory_limiter:
          limit_mib: 256
          spike_limit_mib: 64
          check_interval: 5s
        resource:
          attributes:
            - key: deployment.environment
              value: "${var.environment}"
              action: upsert
            - key: service.namespace
              value: "toggle-master"
              action: upsert

      exporters:
        prometheusremotewrite:
          endpoint: "http://kube-prometheus-stack-prometheus.observability.svc.cluster.local:9090/api/v1/write"
          tls:
            insecure: true
        loki:
          endpoint: "http://loki-stack.observability.svc.cluster.local:3100/loki/api/v1/push"
          default_labels_enabled:
            exporter: false
            job: true
            instance: true
            level: true
        otlp/newrelic:
          endpoint: "otlp.nr-data.net:4317"
          headers:
            api-key: "$${env:NEW_RELIC_LICENSE_KEY}"
          tls:
            insecure: false

      service:
        pipelines:
          traces:
            receivers: [otlp]
            processors: [memory_limiter, batch, resource]
            exporters: [otlp/newrelic]
          metrics:
            receivers: [otlp]
            processors: [memory_limiter, batch, resource]
            exporters: [prometheusremotewrite]
          logs:
            receivers: [otlp]
            processors: [memory_limiter, batch, resource]
            exporters: [loki]
    YAML
  }

  depends_on = [kubernetes_namespace.observability]
}

################################################################################
# OTel Collector — Deployment
################################################################################
resource "kubernetes_deployment" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      app = "otel-collector"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "otel-collector"
      }
    }

    template {
      metadata {
        labels = {
          app = "otel-collector"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.otel_collector.metadata[0].name

        container {
          name  = "otel-collector"
          image = "otel/opentelemetry-collector-contrib:0.105.0"
          args  = ["--config=/conf/config.yaml"]

          port {
            name           = "otlp-grpc"
            container_port = 4317
            protocol       = "TCP"
          }
          port {
            name           = "otlp-http"
            container_port = 4318
            protocol       = "TCP"
          }
          port {
            name           = "metrics"
            container_port = 8888
            protocol       = "TCP"
          }
          port {
            name           = "health"
            container_port = 13133
            protocol       = "TCP"
          }

          env {
            name = "NEW_RELIC_LICENSE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.otel_collector.metadata[0].name
                key  = "NEW_RELIC_LICENSE_KEY"
              }
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/conf"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 13133
            }
            initial_delay_seconds = 15
            period_seconds        = 30
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 13133
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.otel_collector_config.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map.otel_collector_config,
    kubernetes_secret.otel_collector,
    helm_release.kube_prometheus_stack,
    helm_release.loki_stack,
  ]
}

################################################################################
# OTel Collector — Service (ClusterIP — acessível por todos os microsserviços)
################################################################################
resource "kubernetes_service" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      app = "otel-collector"
    }
  }

  spec {
    selector = {
      app = "otel-collector"
    }

    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
      protocol    = "TCP"
    }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
      protocol    = "TCP"
    }
    port {
      name        = "metrics"
      port        = 8888
      target_port = 8888
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
