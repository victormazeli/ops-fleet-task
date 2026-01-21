provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)
  tags = merge(var.tags, { Project = var.name })
}

################################################################################
# VPC
################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.3"

  name = var.name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, 48 + i)]
  intra_subnets   = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, 52 + i)]

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.name
  }

  tags = local.tags
}

################################################################################
# EKS
################################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.14.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Gives Terraform identity admin access to deploy Karpenter via Helm provider
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  # Baseline on-demand nodes
  eks_managed_node_groups = {
    on_demand_arm64 = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = ["m5.large"]

      min_size     = 2
      max_size     = 3
      desired_size = 2

      labels = {
        "karpenter.sh/controller" = "true"
        "capacity"                = "ON_DEMAND"
        "arch"                    = "amd64"
      }
    }
  }

  # Tag the node security group for Karpenter discovery
  node_security_group_tags = merge(local.tags, {
    "karpenter.sh/discovery" = var.name
  })

  tags = local.tags
}

################################################################################
# Karpenter AWS infrastructure (IAM, Pod Identity, Spot interruption handling)
# The terraform-aws-modules project ships Karpenter infrastructure as a submodule:
#   source = "terraform-aws-modules/eks/aws//modules/karpenter"
################################################################################
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.14.0"

  cluster_name = module.eks.cluster_name

  tags = local.tags
}

################################################################################
# Providers for Helm/Kubernetes
################################################################################
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

data "aws_ecrpublic_authorization_token" "token" {
  region = "us-east-1"
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}


################################################################################
# Install Karpenter (Helm)
################################################################################

resource "helm_release" "karpenter_crds" {
  name             = "karpenter-crd"
  namespace        = "kube-system"
  create_namespace = true

  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter-crd"
  version             = var.karpenter_version
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password

  depends_on = [module.eks]
}


resource "helm_release" "karpenter" {
  name      = "karpenter"
  namespace = "kube-system"

  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  version             = var.karpenter_version
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password

  depends_on = [module.karpenter, helm_release.karpenter_crds]

  values = [
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }

      serviceAccount = {
        name = "karpenter"
      }

      nodeSelector = {
        "karpenter.sh/controller" = "true"
      }

      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [{
              matchExpressions = [{
                key      = "karpenter.sh/controller"
                operator = "In"
                values   = ["true"]
              }]
            }]
          }
        }
      }

      resources = {
        requests = {
          cpu    = "1"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      replicas = var.karpenter_replicas
    })
  ]
}


################################################################################
# Apply Karpenter manifests
################################################################################
resource "kubernetes_manifest" "ec2nodeclass" {
  count = var.enable_karpenter_manifests ? 1 : 0
  manifest = yamldecode(templatefile("${path.module}/templates/ec2nodeclass.yaml.tftpl", {
    cluster_name        = module.eks.cluster_name
    node_role_name      = module.karpenter.node_iam_role_name
    discovery_tag_key   = "karpenter.sh/discovery"
    discovery_tag_value = module.eks.cluster_name
    ami_alias           = "bottlerocket@latest"
  }))

  depends_on = [
    module.eks,
    helm_release.karpenter
  ]
}

resource "kubernetes_manifest" "nodepool_spot_amd64" {
  count = var.enable_karpenter_manifests ? 1 : 0
  manifest = yamldecode(templatefile("${path.module}/templates/nodepool-spot-amd64.yaml.tftpl", {
    cpu_limit                  = var.node_pool_cpu_limit
    consolidation_budget_nodes = var.node_pool_consolidation_budget_nodes
  }))

  depends_on = [
    module.eks,
    helm_release.karpenter
  ]
}

resource "kubernetes_manifest" "nodepool_spot_arm64" {
  count = var.enable_karpenter_manifests ? 1 : 0
  manifest = yamldecode(templatefile("${path.module}/templates/nodepool-spot-arm64.yaml.tftpl", {
    cpu_limit                  = var.node_pool_cpu_limit
    consolidation_budget_nodes = var.node_pool_consolidation_budget_nodes
  }))

  depends_on = [
    module.eks,
    helm_release.karpenter
  ]
}
