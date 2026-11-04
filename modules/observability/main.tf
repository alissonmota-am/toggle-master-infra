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

  # Habilita remote_write para o OTel Collector enviar métricas
  set {
    name  = "prometheus.prometheusSpec.enableRemoteWriteReceiver"
    value = "true"
  }

  values = [
    yamlencode({
      additionalPrometheusRulesMap = {
        "togglemaster-alerts" = yamldecode(file("${path.module}/rules/togglemaster-alerts.yaml"))
      }
    }),
    # Alertmanager: rotas e receivers em arquivo proprio (alertmanager/config.yaml.tftpl).
    # Os alertas com team=togglemaster e severity=critical vao para o PagerDuty e o Slack;
    # os de severity=warning vao so para o Slack; o restante e descartado.
    yamlencode({
      alertmanager = {
        config = yamldecode(templatefile("${path.module}/alertmanager/config.yaml.tftpl", {
          slack_webhook_url     = var.slack_webhook_url
          pagerduty_routing_key = var.pagerduty_routing_key
          self_healing_url      = var.self_healing_url
          self_healing_token    = var.self_healing_webhook_token
        }))
      }
    })
  ]

  wait    = false
  timeout = 600

  cleanup_on_fail = true

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

  cleanup_on_fail = true

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
# Dashboard customizado do Grafana (ConfigMap lido pelo sidecar)
# Centraliza: recursos do cluster, taxa de requisicoes e logs em tempo real
################################################################################
resource "kubernetes_config_map" "grafana_dashboard_overview" {
  metadata {
    name      = "grafana-dashboard-togglemaster"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "togglemaster-overview.json" = file("${path.module}/dashboards/togglemaster-overview.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

################################################################################
# Alertmanager Config — injetada via valores do Helm chart
# (não criamos o Secret manualmente para evitar conflito com o recurso
# que o kube-prometheus-stack cria automaticamente)
################################################################################
# A configuração (rotas e receivers) fica em alertmanager/config.yaml.tftpl e é
# passada no bloco "values" do helm_release kube_prometheus_stack acima.

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
      extensions:
        health_check:
          endpoint: "0.0.0.0:13133"

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
          # Converte atributos de recurso (service.name, deployment.environment...)
          # em labels (service_name, deployment_environment...) para permitir
          # consultas e alertas por servico.
          resource_to_telemetry_conversion:
            enabled: true
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
        extensions: [health_check]
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

  wait_for_rollout = false

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
