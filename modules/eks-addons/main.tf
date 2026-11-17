# Add-ons instalados por Helm antes de qualquer serviço (ADR-010): AWS Load Balancer Controller (para o
# TargetGroupBinding), metrics-server (HPA), KEDA (workers pela fila) e, se houver license key, o New Relic
# nri-bundle. Na AWS Academy todos usam as credenciais da LabRole dos nós (ADR-019).
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  atomic     = true # instalação que falha é desfeita, sem deixar release "failed" no cluster
  version    = var.chart_versions.aws_load_balancer_controller

  set = [
    { name = "clusterName", value = var.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = var.vpc_id },
    { name = "replicaCount", value = "1" },
    # Sem isso, todo upgrade gera um certificado novo para o webhook e o pod segue servindo o antigo até
    # reiniciar: a criação de Services (KEDA, metrics-server, apps) falha com "certificate signed by unknown authority".
    { name = "keepTLSSecret", value = "true" },
  ]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  atomic     = true # instalação que falha é desfeita, sem deixar release "failed" no cluster
  version    = var.chart_versions.metrics_server
  # O controller registra um webhook para Services; sem ele pronto, criar Service falha.
  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "helm_release" "keda" {
  name             = "keda"
  namespace        = "keda"
  create_namespace = true
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  atomic           = true # instalação que falha é desfeita, sem deixar release "failed" no cluster
  version          = var.chart_versions.keda
  depends_on       = [helm_release.aws_load_balancer_controller]
}

resource "helm_release" "newrelic" {
  count            = var.newrelic_license_key == "" ? 0 : 1
  name             = "newrelic-bundle"
  namespace        = "newrelic"
  create_namespace = true
  repository       = "https://helm-charts.newrelic.com"
  chart            = "nri-bundle"
  atomic           = true # instalação que falha é desfeita, sem deixar release "failed" no cluster
  version          = var.chart_versions.nri_bundle
  depends_on       = [helm_release.aws_load_balancer_controller]

  set = [
    { name = "global.cluster", value = var.cluster_name },
    { name = "newrelic-infrastructure.privileged", value = "true" },
    { name = "kube-state-metrics.enabled", value = "true" },
    { name = "kubeEvents.enabled", value = "true" },
    { name = "logging.enabled", value = "true" },
    # O DaemonSet de logs (fluent-bit) reserva 250m de CPU por nó; com dois t3.large e os serviços, um nó fica
    # sem espaço e o pod fica Pending. O uso real é bem menor: 50m de reserva, mantendo o limite do chart.
    { name = "newrelic-logging.resources.requests.cpu", value = "50m" },
  ]
  set_sensitive = [
    { name = "global.licenseKey", value = var.newrelic_license_key },
  ]
}
