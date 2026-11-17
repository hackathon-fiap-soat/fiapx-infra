# Cluster EKS e managed node group usando a LabRole (a AWS Academy não permite criar roles, ADR-019).
# Os pods usam as credenciais da LabRole dos nós pelo IMDS; por isso o launch template libera 2 saltos
# (o pod é um salto a mais que o nó). Acesso ao cluster: o criador (role voclabs do lab) é admin.
data "aws_iam_role" "lab" {
  name = var.lab_role_name
}

resource "aws_eks_cluster" "this" {
  name     = var.prefix
  version  = var.kubernetes_version
  role_arn = data.aws_iam_role.lab.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
}

resource "aws_launch_template" "nodes" {
  name_prefix = "${var.prefix}-nodes-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.node_disk_gb
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.prefix}-node" }
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.prefix}-default"
  node_role_arn   = data.aws_iam_role.lab.arn
  subnet_ids      = var.private_subnet_ids
  capacity_type   = "ON_DEMAND" # spot é negado no lab
  instance_types  = [var.node_instance_type]
  ami_type        = "AL2023_x86_64_STANDARD" # x86: o agente New Relic das imagens é linux/amd64

  scaling_config {
    min_size     = var.node_min
    desired_size = var.node_min
    max_size     = var.node_max
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

resource "aws_eks_addon" "this" {
  for_each                    = toset(["vpc-cni", "kube-proxy", "coredns"])
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.this]
}
